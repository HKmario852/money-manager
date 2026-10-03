import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../domain/ledger.dart';
import '../providers.dart';
import 'common.dart';
import 'entry_screen.dart';
import 'theme.dart';

class TxTile extends StatelessWidget {
  const TxTile(this.tx, {super.key, this.forAccount, this.accounts});
  final TxView tx;
  final String? forAccount;
  final Map<String, Account>? accounts;

  @override
  Widget build(BuildContext context) {
    final kind = tx.entry.kind;
    final isTransfer = kind == EntryKind.transfer;
    final isSystem = kind == EntryKind.opening || kind == EntryKind.adjustment;
    final avatarAccount = isTransfer || isSystem ? (forAccount == tx.from.id ? tx.to : tx.from) : tx.category;
    final title = isTransfer
        ? '${tx.from.name} → ${tx.to.name}'
        : isSystem
        ? kindLabel(kind)
        : (accounts != null ? categoryPath(tx.category, accounts!) : tx.category.name);
    final subtitle = [
      if (!isTransfer && !isSystem && forAccount == null) tx.fund.name,
      if (tx.entry.note != null) tx.entry.note!,
      ...tx.tags.map((t) => '#${t.name}'),
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      leading: isTransfer
          ? Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.swap_horiz, size: 20),
            )
          : AccountAvatar(avatarAccount),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tx.attachments.isNotEmpty) const Icon(Icons.attach_file, size: 16),
          AmountText(
            displayAmount(tx, forAccount: forAccount),
            neutral: isTransfer && forAccount == null,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(tx.entry.id))),
    );
  }
}

/// 按日分組嘅交易列表
class TxList extends StatelessWidget {
  const TxList(this.txs, {super.key, this.forAccount, required this.accounts, this.header});
  final List<TxView> txs;
  final String? forAccount;
  final Map<String, Account> accounts;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[?header];
    DateTime? day;
    var group = <Widget>[];
    void flush() {
      if (group.isEmpty) return;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(children: group),
          ),
        ),
      );
      group = [];
    }

    for (var i = 0; i < txs.length; i++) {
      final tx = txs[i];
      final d = DateTime(tx.entry.occurredAt.year, tx.entry.occurredAt.month, tx.entry.occurredAt.day);
      if (d != day) {
        flush();
        day = d;
        final dayTotal = txs
            .where((t) => DateUtils.isSameDay(t.entry.occurredAt, d))
            .where((t) => forAccount != null || t.entry.kind != EntryKind.transfer)
            .fold(0, (s, t) => s + displayAmount(t, forAccount: forAccount));
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
            child: Row(
              children: [
                Text(
                  formatDate(d),
                  style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                AmountText(
                  dayTotal,
                  style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
      group.add(TxTile(tx, forAccount: forAccount, accounts: accounts));
    }
    flush();
    if (txs.isEmpty) items.add(const EmptyState('呢段時間未有交易'));
    items.add(const SizedBox(height: 32));
    return ListView(children: items);
  }
}

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String? accountId, categoryId, tagId, search;
  EntryKind? kind;
  bool searching = false;

  bool get hasFilter => accountId != null || categoryId != null || tagId != null || kind != null;

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          void set(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          final accounts = ref.read(accountsProvider).value ?? const <Account>[];
          final tags = ref.read(tagsProvider).value ?? const <Tag>[];
          final cats = [
            ...topCategories(accounts, AccountType.expense),
            ...topCategories(accounts, AccountType.income),
          ];
          Widget section(String title, List<Widget> chips) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(c).textTheme.titleSmall),
                Wrap(spacing: 6, children: chips),
              ],
            ),
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  section('類型', [
                    for (final k in [EntryKind.expense, EntryKind.income, EntryKind.transfer])
                      ChoiceChip(
                        label: Text(kindLabel(k)),
                        selected: kind == k,
                        onSelected: (v) => set(() => kind = v ? k : null),
                      ),
                  ]),
                  section('賬戶', [
                    for (final a in fundAccounts(accounts))
                      ChoiceChip(
                        label: Text(a.name),
                        selected: accountId == a.id,
                        onSelected: (v) => set(() => accountId = v ? a.id : null),
                      ),
                  ]),
                  section('分類', [
                    for (final a in cats)
                      ChoiceChip(
                        label: Text(a.name),
                        selected: categoryId == a.id,
                        onSelected: (v) => set(() => categoryId = v ? a.id : null),
                      ),
                  ]),
                  if (tags.isNotEmpty)
                    section('Tag', [
                      for (final t in tags)
                        ChoiceChip(
                          label: Text('#${t.name}'),
                          selected: tagId == t.id,
                          onSelected: (v) => set(() => tagId = v ? t.id : null),
                        ),
                    ]),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => set(() => accountId = categoryId = tagId = kind = null),
                        child: const Text('清除'),
                      ),
                      const Spacer(),
                      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('完成')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = ref.watch(currentPeriodProvider);
    final accounts = ref.watch(accountMapProvider);
    final searchingAll = search != null && search!.isNotEmpty;
    final TxFilter filter = (
      from: searchingAll ? null : from,
      to: searchingAll ? null : to,
      accountId: accountId,
      categoryId: categoryId,
      tagId: tagId,
      kind: kind,
      search: search,
      limit: null,
    );
    final txs = ref.watch(transactionsProvider(filter));
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜尋備註或商戶', border: InputBorder.none),
                onChanged: (v) => setState(() => search = v),
              )
            : const PeriodSwitcher(),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              searching = !searching;
              if (!searching) search = null;
            }),
          ),
          IconButton(
            icon: Badge(isLabelVisible: hasFilter, child: const Icon(Icons.filter_list)),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: asyncBody(txs, (list) {
        final income = list.where((t) => t.entry.kind == EntryKind.income).fold(0, (s, t) => s + t.amount);
        final expense = list.where((t) => t.entry.kind == EntryKind.expense).fold(0, (s, t) => s + t.amount);
        return TxList(
          list,
          accounts: accounts,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [_Stat('支出', -expense), _Stat('收入', income), _Stat('結餘', income - expense)],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.amount);
  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AmountText(amount, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ],
    ),
  );
}

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = ref.watch(transactionProvider(id));
    final accounts = ref.watch(accountMapProvider);
    final attDir = ref.watch(appPathsProvider).attachments;
    return Scaffold(
      appBar: AppBar(
        title: const Text('交易詳情'),
        actions: [
          if (tx.value case final t?) ...[
            if (t.entry.kind case EntryKind.expense || EntryKind.income || EntryKind.transfer) ...[
              IconButton(
                tooltip: '複製一筆',
                icon: const Icon(Icons.copy),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntryScreen(
                      initial: EntryDraft(
                        kind: t.entry.kind,
                        amount: t.amount,
                        fromAccountId: t.from.id,
                        toAccountId: t.to.id,
                        occurredAt: DateTime.now(),
                        note: t.entry.note,
                        tagIds: t.tags.map((x) => x.id).toList(),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '編輯',
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryScreen(existing: t))),
              ),
            ],
            IconButton(
              tooltip: '刪除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, '刪除呢筆交易？', ok: '刪除')) return;
                await ref.read(ledgerProvider).deleteEntry(id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
      body: asyncBody(tx, (t) {
        if (t == null) return const EmptyState('呢筆交易已經刪除');
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  AccountAvatar(t.entry.kind == EntryKind.transfer ? t.to : t.category, radius: 28),
                  const SizedBox(height: 8),
                  Text(kindLabel(t.entry.kind), style: theme.textTheme.labelLarge),
                  AmountText(
                    displayAmount(t),
                    neutral: t.entry.kind == EntryKind.transfer,
                    style: theme.textTheme.displaySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (t.entry.kind case EntryKind.expense || EntryKind.income) ...[
              _Row('分類', categoryPath(t.category, accounts)),
              _Row('賬戶', t.fund.name),
            ] else ...[
              _Row('由', t.from.name),
              _Row('去', t.to.name),
            ],
            _Row('時間', '${formatDate(t.entry.occurredAt, withYear: true)} ${formatTime(t.entry.occurredAt)}'),
            if (t.entry.note != null) _Row('備註', t.entry.note!),
            if (t.tags.isNotEmpty) _Row('Tag', t.tags.map((x) => '#${x.name}').join(' ')),
            const Divider(height: 32),
            Text('複式分錄', style: theme.textTheme.titleSmall),
            for (final p in t.postings)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(accounts[p.accountId] != null ? categoryPath(accounts[p.accountId]!, accounts) : '?'),
                trailing: Text(
                  '${p.amount > 0 ? '借' : '貸'} ${(p.amount.abs() / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            if (t.attachments.isNotEmpty) ...[
              const Divider(height: 32),
              Text('收據', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final a in t.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                          body: InteractiveViewer(
                            child: Center(child: Image.file(File(p.join(attDir, p.basename(a.filePath))))),
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(p.join(attDir, p.basename(a.filePath))), height: 200, fit: BoxFit.cover),
                    ),
                  ),
                ),
            ],
          ],
        );
      }),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
