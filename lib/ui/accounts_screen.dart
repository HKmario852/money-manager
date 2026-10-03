import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';
import 'transactions_screen.dart';

class NetWorthCard extends ConsumerWidget {
  const NetWorthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nw = ref.watch(netWorthProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: nw.when(
          loading: () => const SizedBox(height: 72),
          error: (e, _) => Text('$e'),
          data: (v) {
            final (assets, liabilities) = v;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('淨資產', style: theme.textTheme.labelLarge),
                AmountText(assets - liabilities, neutral: true, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('資產 ${formatMoney(assets)}')),
                    Expanded(child: Text('負債 ${formatMoney(liabilities)}')),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool showArchived = false;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final balances = ref.watch(balancesProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('賬戶'),
        actions: [
          IconButton(
            tooltip: showArchived ? '隱藏已封存' : '顯示已封存',
            icon: Icon(showArchived ? Icons.visibility_off : Icons.inventory_2_outlined),
            onPressed: () => setState(() => showArchived = !showArchived),
          ),
          IconButton(
            tooltip: '新增賬戶',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountEditScreen())),
          ),
        ],
      ),
      body: asyncBody(accounts, (all) {
        final funds = fundAccounts(all, includeArchived: showArchived);
        final groups = <String, List<Account>>{};
        for (final a in funds) {
          groups.putIfAbsent(subtypeLabel(a.type, a.subtype), () => []).add(a);
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const NetWorthCard(),
            for (final MapEntry(key: label, value: list) in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Row(
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    AmountText(
                      list.fold(0, (s, a) => s + (balances[a.id] ?? 0)),
                      neutral: true,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              Card(child: Column(children: [for (final a in list) _AccountTile(a, balances[a.id] ?? 0)])),
            ],
            if (funds.isEmpty) const EmptyState('未有賬戶，撳右上角 + 新增'),
            const SizedBox(height: 96),
          ],
        );
      }),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.account, this.signedBalance);
  final Account account;
  final int signedBalance;

  @override
  Widget build(BuildContext context) {
    final isCard = account.subtype == AccountSubtype.creditCard;
    final owed = -signedBalance;
    final limit = account.creditLimit;
    return ListTile(
      leading: AccountAvatar(account),
      title: Text(account.name + (account.isArchived ? '（已封存）' : '')),
      subtitle: isCard && limit != null && limit > 0
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                ExcludeSemantics(child: LinearProgressIndicator(value: (owed / limit).clamp(0, 1).toDouble())),
                const SizedBox(height: 2),
                Text('可用 ${formatMoney(limit - owed)} / 額度 ${formatMoney(limit)}'),
              ],
            )
          : null,
      trailing: AmountText(
        account.type == AccountType.liability ? -owed : signedBalance,
        neutral: account.type == AccountType.asset,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailScreen(account.id))),
    );
  }
}

class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountMapProvider);
    final account = accounts[id];
    final balance = ref.watch(balancesProvider).value?[id] ?? 0;
    final TxFilter filter = (
      from: null,
      to: null,
      accountId: id,
      categoryId: null,
      tagId: null,
      kind: null,
      search: null,
      limit: 300,
    );
    final txs = ref.watch(transactionsProvider(filter));
    if (account == null) return const Scaffold(body: SizedBox());
    final display = toDisplay(account.type, balance);
    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => AccountEditScreen(account: account))),
          ),
        ],
      ),
      body: asyncBody(
        txs,
        (list) => TxList(
          list,
          forAccount: id,
          accounts: accounts,
          header: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.type == AccountType.liability ? '欠款' : '結餘'),
                        Text(formatMoney(display), style: Theme.of(context).textTheme.headlineMedium),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final v = await promptText(
                        context,
                        account.type == AccountType.liability ? '實際欠款' : '實際結餘',
                        initial: minorToInput(display),
                        keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      );
                      if (v == null) return;
                      final neg = v.trim().startsWith('-');
                      final parsed = parseMinor(v.trim().replaceFirst('-', ''));
                      if (parsed == null) {
                        if (context.mounted) showError(context, '金額唔啱');
                        return;
                      }
                      await ref.read(ledgerProvider).adjustBalance(id, neg ? -parsed : parsed);
                    },
                    child: const Text('調整結餘'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Kind = (AccountType, AccountSubtype, String icon);

const _kinds = <_Kind>[
  (AccountType.asset, AccountSubtype.cash, 'cash'),
  (AccountType.asset, AccountSubtype.bank, 'bank'),
  (AccountType.asset, AccountSubtype.ewallet, 'octopus'),
  (AccountType.liability, AccountSubtype.creditCard, 'card'),
  (AccountType.asset, AccountSubtype.other, 'savings'),
  (AccountType.liability, AccountSubtype.other, 'tax'),
];

class AccountEditScreen extends ConsumerStatefulWidget {
  const AccountEditScreen({super.key, this.account, this.firstRun = false});
  final Account? account;
  final bool firstRun;

  @override
  ConsumerState<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends ConsumerState<AccountEditScreen> {
  late final name = TextEditingController(text: widget.account?.name ?? (widget.firstRun ? '現金' : ''));
  final opening = TextEditingController();
  late final limit = TextEditingController(
    text: widget.account?.creditLimit != null ? minorToInput(widget.account!.creditLimit!) : '',
  );
  late _Kind kind = widget.account != null
      ? _kinds.firstWhere(
          (k) => k.$1 == widget.account!.type && k.$2 == widget.account!.subtype,
          orElse: () => _kinds.first,
        )
      : _kinds.first;
  late String? icon = widget.account?.icon;
  late int color = widget.account?.color ?? kPalette[6];

  bool get editing => widget.account != null;

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      showError(context, '請輸入名稱');
      return;
    }
    final ledger = ref.read(ledgerProvider);
    final creditLimit = kind.$2 == AccountSubtype.creditCard ? parseMinor(limit.text.trim()) : null;
    try {
      if (editing) {
        await ledger.updateAccount(
          widget.account!.id,
          AccountsCompanion(
            name: Value(name.text.trim()),
            icon: Value(icon),
            color: Value(color),
            creditLimit: Value(creditLimit),
          ),
        );
      } else {
        await ledger.createFundAccount(
          name: name.text.trim(),
          type: kind.$1,
          subtype: kind.$2,
          icon: icon,
          color: color,
          creditLimit: creditLimit,
          openingBalance: parseMinor(opening.text.trim()) ?? 0,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _archive() async {
    if (!await confirm(context, '刪除或封存「${widget.account!.name}」？', message: '有交易嘅賬戶會封存（記錄保留，唔再出現喺揀選清單）；冇交易就會直接刪除。')) {
      return;
    }
    final deleted = await ref.read(ledgerProvider).archiveOrDelete(widget.account!.id);
    if (!mounted) return;
    Navigator.of(context)
      ..pop()
      ..pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(deleted ? '已刪除' : '已封存')));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '編輯賬戶' : '新增賬戶'),
        actions: [
          if (editing && a!.isArchived)
            TextButton(
              onPressed: () async {
                await ref.read(ledgerProvider).updateAccount(a.id, const AccountsCompanion(isArchived: Value(false)));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('取消封存'),
            )
          else if (editing)
            IconButton(tooltip: '刪除或封存', icon: const Icon(Icons.delete_outline), onPressed: _archive),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
        children: [
          if (!editing) ...[
            Text('類型', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final k in _kinds)
                  ChoiceChip(
                    label: Text(subtypeLabel(k.$1, k.$2)),
                    selected: kind == k,
                    onSelected: (_) => setState(() {
                      kind = k;
                      icon = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '名稱', hintText: '例如 滙豐儲蓄、八達通'),
          ),
          if (!editing)
            TextField(
              controller: opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: kind.$1 == AccountType.liability ? '而家欠款' : '而家結餘',
                prefixText: '\$ ',
              ),
            ),
          if (kind.$2 == AccountSubtype.creditCard)
            TextField(
              controller: limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '信用額', prefixText: '\$ '),
            ),
          const SizedBox(height: 16),
          Text('圖示', style: Theme.of(context).textTheme.titleSmall),
          IconPicker(selected: icon ?? kind.$3, color: Color(color), onChanged: (v) => setState(() => icon = v)),
          const SizedBox(height: 8),
          Text('顏色', style: Theme.of(context).textTheme.titleSmall),
          ColorPicker(selected: color, onChanged: (c) => setState(() => color = c)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('儲存')),
        ],
      ),
    );
  }
}

class IconPicker extends StatelessWidget {
  const IconPicker({super.key, required this.selected, required this.color, required this.onChanged});
  final String? selected;
  final Color color;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: [
        for (final MapEntry(:key, :value) in kIcons.entries)
          IconButton(
            isSelected: key == selected,
            style: key == selected ? IconButton.styleFrom(backgroundColor: color.withValues(alpha: 0.2)) : null,
            icon: Icon(value, color: key == selected ? color : null),
            onPressed: () => onChanged(key),
          ),
      ],
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({super.key, required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in kPalette)
          GestureDetector(
            onTap: () => onChanged(c),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Color(c),
              child: c == selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
            ),
          ),
      ],
    );
  }
}
