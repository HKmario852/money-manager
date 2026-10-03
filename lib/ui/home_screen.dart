import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'common.dart';
import 'entry_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(thisPeriodProvider);
    final summary = ref.watch(summaryProvider(range));
    final accounts = ref.watch(accountMapProvider);
    final templates = ref.watch(templatesProvider).value ?? const <Template>[];
    final budgets = ref.watch(budgetStatusProvider).value ?? const <BudgetStatus>[];
    final total = budgets.where((b) => b.category == null).firstOrNull;
    final overs = budgets.where((b) => b.category != null && b.ratio >= 0.8).toList();
    final TxFilter recentFilter = (
      from: null,
      to: null,
      accountId: null,
      categoryId: null,
      tagId: null,
      kind: null,
      search: null,
      limit: 10,
    );
    final recent = ref.watch(transactionsProvider(recentFilter));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('記錄課金'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: summary.when(
                loading: () => const SizedBox(height: 64),
                error: (e, _) => Text('$e'),
                data: (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${periodLabel(range.$1)} 支出', style: theme.textTheme.labelLarge),
                    Text(formatMoney(s.expense), style: theme.textTheme.headlineMedium?.copyWith(color: expenseColor)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text('收入 ${formatMoney(s.income)}')),
                        Expanded(child: Row(children: [const Text('結餘 '), AmountText(s.net)])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (total != null || overs.isNotEmpty)
            Card(
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsScreen())),
                child: Column(children: [if (total != null) BudgetBar(total), for (final o in overs) BudgetBar(o)]),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: const Text('設定每月預算'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsScreen())),
              ),
            ),
          const NetWorthCard(),
          if (templates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text('常用（撳一下即記，長撳先改）', style: theme.textTheme.titleSmall),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in templates)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onLongPress: () => openTemplateForEdit(context, ref, t),
                        child: ActionChip(
                          avatar: accounts[t.toAccountId] != null
                              ? Icon(iconFor(accounts[t.toAccountId]!), size: 18)
                              : null,
                          label: Text('${t.name} ${formatMoney(t.amount)}'),
                          onPressed: () => _useTemplate(context, ref, t),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Text('最近交易', style: theme.textTheme.titleSmall),
          ),
          recent.when(
            loading: () => const SizedBox(height: 64),
            error: (e, _) => Text('$e'),
            data: (list) => list.isEmpty
                ? const EmptyState('未有交易。撳下面 + 記第一筆。', icon: Icons.edit_note)
                : Card(
                    child: Column(children: [for (final t in list) TxTile(t, accounts: accounts)]),
                  ),
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  Future<void> _useTemplate(BuildContext context, WidgetRef ref, Template t) async {
    final ledger = ref.read(ledgerProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ledger.useTemplate(t);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已記低「${t.name}」${formatMoney(t.amount)}'),
          persist: false,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: '復原', onPressed: () => ledger.deleteEntry(id)),
        ),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// 長撳模板：改金額先記
Future<void> openTemplateForEdit(BuildContext context, WidgetRef ref, Template t) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => EntryScreen(initial: ref.read(ledgerProvider).draftFromTemplate(t))),
);
