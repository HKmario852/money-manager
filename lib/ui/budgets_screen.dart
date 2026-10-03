import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';

class BudgetStatus {
  BudgetStatus(this.budget, this.category, this.spent);
  final Budget budget;
  final Account? category; // null = 總預算
  final int spent;
  double get ratio => budget.amount == 0 ? 0 : spent / budget.amount;
  int get remaining => budget.amount - spent;
}

/// 今期每個預算用咗幾多。
final budgetStatusProvider = Provider<AsyncValue<List<BudgetStatus>>>((ref) {
  final range = ref.watch(thisPeriodProvider);
  final accounts = ref.watch(accountMapProvider);
  final budgets = ref.watch(budgetsProvider);
  final totals = ref.watch(categoryTotalsProvider(range));
  if (budgets is! AsyncData || totals is! AsyncData) {
    return budgets is AsyncError ? AsyncError(budgets.error!, StackTrace.current) : const AsyncLoading();
  }
  final byRoot = <String, int>{};
  var totalExpense = 0;
  totals.value!.forEach((id, v) {
    final a = accounts[id];
    if (a == null || a.type != AccountType.expense) return;
    totalExpense += v;
    final root = a.parentId ?? a.id;
    byRoot[root] = (byRoot[root] ?? 0) + v;
  });
  final list =
      [
        for (final b in budgets.value!)
          BudgetStatus(b, accounts[b.accountId], b.accountId == null ? totalExpense : (byRoot[b.accountId] ?? 0)),
      ]..sort(
        (a, b) => (a.category == null ? -1 : a.category!.sortOrder).compareTo(
          b.category == null ? -1 : b.category!.sortOrder,
        ),
      );
  return AsyncData(list);
});

Color budgetColor(double ratio) => ratio >= 1
    ? expenseColor
    : ratio >= 0.8
    ? const Color(0xFFF9A825)
    : incomeColor;

class BudgetBar extends StatelessWidget {
  const BudgetBar(this.status, {super.key, this.onTap});
  final BudgetStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final c = budgetColor(s.ratio);
    return ListTile(
      onTap: onTap,
      leading: s.category != null
          ? AccountAvatar(s.category!)
          : const CircleAvatar(child: Icon(Icons.account_balance_wallet)),
      title: Row(
        children: [
          Expanded(child: Text(s.category?.name ?? '每月總預算')),
          Text(
            '${formatMoney(s.spent)} / ${formatMoney(s.budget.amount)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: s.ratio.clamp(0, 1).toDouble(),
                minHeight: 8,
                color: c,
                backgroundColor: c.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.remaining >= 0 ? '仲有 ${formatMoney(s.remaining)}' : '超支 ${formatMoney(-s.remaining)}',
            style: TextStyle(color: s.ratio >= 0.8 ? c : null),
          ),
        ],
      ),
    );
  }
}

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {BudgetStatus? existing}) async {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final budgets = ref.read(budgetsProvider).value ?? const <Budget>[];
    String? categoryId = existing?.budget.accountId;
    var isTotal = existing != null && existing.budget.accountId == null;
    if (existing == null) {
      final hasTotal = budgets.any((b) => b.accountId == null);
      final used = budgets.map((b) => b.accountId).toSet();
      final options = topCategories(accounts, AccountType.expense).where((a) => !used.contains(a.id)).toList();
      if (!context.mounted) return;
      final choice = await showModalBottomSheet<Object>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (!hasTotal)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet)),
                  title: const Text('每月總預算'),
                  onTap: () => Navigator.pop(c, 'total'),
                ),
              for (final a in options)
                ListTile(leading: AccountAvatar(a), title: Text(a.name), onTap: () => Navigator.pop(c, a)),
            ],
          ),
        ),
      );
      if (choice == null) return;
      isTotal = choice == 'total';
      categoryId = choice is Account ? choice.id : null;
    }
    if (!context.mounted) return;
    final title = isTotal ? '每月總預算' : (accounts.firstWhere((a) => a.id == categoryId).name);
    final v = await promptText(
      context,
      '$title 上限',
      initial: existing != null ? minorToInput(existing.budget.amount) : '',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
    if (v == null) return;
    final amount = parseMinor(v.trim());
    if (amount == null || amount <= 0) {
      if (context.mounted) showError(context, '金額唔啱');
      return;
    }
    await ref.read(ledgerProvider).saveBudget(id: existing?.budget.id, categoryId: categoryId, amount: amount);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(budgetStatusProvider);
    final (start, _) = ref.watch(thisPeriodProvider);
    return Scaffold(
      appBar: AppBar(title: Text('預算 · ${periodLabel(start)}')),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增預算',
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: asyncBody(status, (list) {
        if (list.isEmpty) return const EmptyState('未設預算。撳 + 設定每月總預算或者分類上限。');
        return ListView(
          children: [
            for (final s in list)
              Dismissible(
                key: ValueKey(s.budget.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: expenseColor,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) => confirm(context, '刪除呢個預算？', ok: '刪除'),
                onDismissed: (_) => ref.read(ledgerProvider).deleteBudget(s.budget.id),
                child: BudgetBar(s, onTap: () => _edit(context, ref, existing: s)),
              ),
            const SizedBox(height: 96),
          ],
        );
      }),
    );
  }
}
