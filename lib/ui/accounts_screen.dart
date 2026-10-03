import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'capture_screens.dart';
import 'common.dart';
import 'theme.dart';
import 'transactions_screen.dart';

/// 黑色淨資產卡：大字淨資產、比上月變動、資產 / 負債比例條。
class NetWorthCard extends ConsumerWidget {
  const NetWorthCard({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nw = ref.watch(netWorthProvider);
    final (periodStart, _) = ref.watch(thisPeriodProvider);
    final before = ref.watch(netWorthAtProvider(periodStart)).value;
    return AppCard(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      onTap: onTap,
      child: nw.when(
        loading: () => const SizedBox(height: 120),
        error: (e, _) => Text('$e', style: const TextStyle(color: Colors.white)),
        data: (v) {
          final (assets, liabilities) = v;
          final net = assets - liabilities;
          final total = assets + liabilities;
          final change = before == null ? null : net - before;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '淨資產',
                      style: TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (change != null && change != 0) Pill('比上月 ${formatMoney(change, showPlus: true)}'),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BigMoney(net, color: Colors.white, dimColor: const Color(0xFF8C9099)),
              ),
              const SizedBox(height: 14),
              if (total > 0)
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 7,
                      child: Row(
                        children: [
                          if (assets > 0)
                            Expanded(
                              flex: assets,
                              child: Container(color: AppColors.lime),
                            ),
                          if (assets > 0 && liabilities > 0) const SizedBox(width: 3),
                          if (liabilities > 0)
                            Expanded(
                              flex: liabilities < total ~/ 50 ? total ~/ 50 : liabilities,
                              child: Container(color: const Color(0xFFF08A55)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Legend(AppColors.lime, '資產', assets)),
                  Expanded(child: _Legend(const Color(0xFFF08A55), '負債', liabilities)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label, this.amount);
  final Color color;
  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFFB9BDC4), fontSize: 12)),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        formatMoney(amount),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ],
  );
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
      body: SafeArea(
        child: asyncBody(accounts, (all) {
          // 資產先，負債（信用卡）排尾
          final unsorted = fundAccounts(all, includeArchived: showArchived);
          final funds = [
            ...unsorted.where((a) => a.type != AccountType.liability),
            ...unsorted.where((a) => a.type == AccountType.liability),
          ];
          final hasArchived = fundAccounts(all, includeArchived: true).any((a) => a.isArchived);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              PageHeader(
                '帳戶',
                actions: [
                  CircleAction(
                    tooltip: '新增帳戶',
                    icon: Icons.add,
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountEditScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const NetWorthCard(),
              const SizedBox(height: 6),
              SectionCard(
                title: '我的帳戶',
                trailing: hasArchived
                    ? TextButton(
                        onPressed: () => setState(() => showArchived = !showArchived),
                        child: Text(showArchived ? '隱藏已封存' : '顯示已封存'),
                      )
                    : null,
                child: funds.isEmpty
                    ? const EmptyState('未有帳戶，撳右上角 + 新增')
                    : Column(
                        children: [
                          for (var i = 0; i < funds.length; i++) ...[
                            if (i > 0) const Divider(),
                            _AccountTile(funds[i], balances[funds[i].id] ?? 0),
                          ],
                        ],
                      ),
              ),
            ],
          );
        }),
      ),
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
    final display = account.type == AccountType.liability ? -owed : signedBalance;
    final String subtitle;
    Color subColor = AppColors.muted;
    if (isCard && limit != null && limit > 0) {
      final pct = (owed * 100 / limit).round();
      subtitle = '已用額度 $pct% · 可用 ${formatMoney(limit - owed)}';
      if (pct >= 80) subColor = AppColors.orange;
    } else {
      subtitle = subtypeLabel(account.type, account.subtype);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailScreen(account.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AccountAvatar(account, radius: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name + (account.isArchived ? '（已封存）' : ''),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: subColor, fontSize: 12)),
                ],
              ),
            ),
            Text(
              formatMoney(display),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
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
          header: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.type == AccountType.liability ? '欠款' : '結餘'),
                        BigMoney(display, size: 32),
                      ],
                    ),
                  ),
                  if (_isOctopus(account)) ...[
                    IconButton.outlined(
                      tooltip: '匯入八達通截圖',
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: () => importOctopusScreenshots(context, ref),
                    ),
                    if (ref.read(notificationBridgeProvider).supported)
                      IconButton.outlined(
                        tooltip: '拍卡同步餘額',
                        icon: const Icon(Icons.contactless_outlined),
                        onPressed: () => syncOctopusBalance(context, ref, account),
                      ),
                    const SizedBox(width: 4),
                  ],
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

bool _isOctopus(Account a) =>
    a.type == AccountType.asset &&
    (a.icon == 'octopus' || a.name.contains('八達通') || a.name.toLowerCase().contains('octopus'));

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
