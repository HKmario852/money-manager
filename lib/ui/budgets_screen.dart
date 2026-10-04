import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';
import 'theme.dart';

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

Color budgetColor(double ratio) => ratio >= 1 ? AppColors.orange : AppColors.ink;

/// 預算一行：分類字塊、已用 / 上限、百分比、進度條（超支轉橙）。
class BudgetBar extends StatelessWidget {
  const BudgetBar(this.status, {super.key, this.onTap, this.onLongPress});
  final BudgetStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final over = s.ratio >= 1;
    final c = budgetColor(s.ratio);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            s.category != null
                ? AccountAvatar(s.category!, radius: 20)
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        s.category?.name ?? '總預算',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: formatMoney(s.spent),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: over ? AppColors.orange : null,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' / ${formatMoney(s.budget.amount, trimZero: true)}',
                                    style: const TextStyle(color: AppColors.muted),
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ProgressBar(s.ratio, color: c, height: 7),
                ],
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '${(s.ratio * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, color: over ? AppColors.orange : AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 黑色圓環 + 已用 / 總預算 / 剩餘 + 青檸色「每日可用」。
class BudgetOverviewCard extends ConsumerWidget {
  const BudgetOverviewCard(this.list, {super.key, this.onTap});
  final List<BudgetStatus> list;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = list.where((b) => b.category == null).firstOrNull;
    final int spent = total?.spent ?? list.fold<int>(0, (s, b) => s + b.spent);
    final int limit = total?.budget.amount ?? list.fold<int>(0, (s, b) => s + b.budget.amount);
    final ratio = limit == 0 ? 0.0 : spent / limit;
    final remaining = limit - spent;
    final (_, end) = ref.watch(thisPeriodProvider);
    final now = DateTime.now();
    final daysLeft = end.difference(DateTime(now.year, now.month, now.day)).inDays.clamp(1, 31);
    final over = remaining < 0;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: ExcludeSemantics(
                        child: CircularProgressIndicator(
                          value: ratio.clamp(0, 1).toDouble(),
                          strokeWidth: 18,
                          strokeCap: StrokeCap.butt,
                          color: over ? AppColors.orange : AppColors.ink,
                          backgroundColor: AppColors.track,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(ratio * 100).round()}%',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                        const Text('已使用', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Figure('已用', spent),
                    _Figure(total != null ? '總預算' : '分類預算合計', limit),
                    _Figure(over ? '超支' : '剩餘', remaining.abs(), color: over ? AppColors.orange : null),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: over ? AppColors.peach : AppColors.lime,
              borderRadius: BorderRadius.circular(AppRadius.tile),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    over ? '剩 $daysLeft 日 · 已經超支' : '剩 $daysLeft 日 · 每日可用',
                    style: TextStyle(color: over ? AppColors.peachInk : AppColors.ink),
                  ),
                ),
                Text(
                  formatMoney(over ? -remaining : remaining ~/ daysLeft),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: over ? AppColors.peachInk : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.amount, {this.color});
  final String label;
  final int amount;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        Text(
          formatMoney(amount),
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color),
        ),
      ],
    ),
  );
}

/// 超支 / 就爆預算嘅提示（淺橙卡）。冇就唔顯示。
class BudgetAlertCard extends StatelessWidget {
  const BudgetAlertCard(this.list, {super.key});
  final List<BudgetStatus> list;

  @override
  Widget build(BuildContext context) {
    final cats = list.where((b) => b.category != null).toList();
    final overs = cats.where((b) => b.ratio >= 1).toList()..sort((a, b) => b.ratio.compareTo(a.ratio));
    final near = cats.where((b) => (b.ratio * 100).round() >= 90 && b.ratio < 1).toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
    final lines = [
      for (final b in overs) '${b.category!.name}已超出預算 ${formatMoney(-b.remaining)}',
      for (final b in near) '${b.category!.name}已用 ${(b.ratio * 100).round()}%，留意下',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return AppCard(
      color: AppColors.peach,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lines.first,
                  style: const TextStyle(color: AppColors.peachInk, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                for (final l in lines.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(l, style: const TextStyle(color: AppColors.peachInk, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {BudgetStatus? existing, bool total = false}) async {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final budgets = ref.read(budgetsProvider).value ?? const <Budget>[];
    String? categoryId = existing?.budget.accountId;
    var isTotal = total || (existing != null && existing.budget.accountId == null);
    if (existing == null && !total) {
      final used = budgets.map((b) => b.accountId).toSet();
      final options = topCategories(accounts, AccountType.expense).where((a) => !used.contains(a.id)).toList();
      if (options.isEmpty) {
        showError(context, '全部分類都已經有預算');
        return;
      }
      final choice = await pickAccount(context, options, title: '揀分類');
      if (choice == null) return;
      categoryId = choice.id;
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
    await ref
        .read(ledgerProvider)
        .saveBudget(id: existing?.budget.id, categoryId: isTotal ? null : categoryId, amount: amount);
  }

  Future<void> _editTotal(BuildContext context, WidgetRef ref, BudgetStatus? total) async {
    if (total == null) return _edit(context, ref, total: true);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('改每月總預算'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('刪除每月總預算'),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') return _edit(context, ref, existing: total);
    if (action == 'delete') return _delete(context, ref, total);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, BudgetStatus s) async {
    if (await confirm(context, '刪除「${s.category?.name ?? '每月總預算'}」預算？', ok: '刪除')) {
      await ref.read(ledgerProvider).deleteBudget(s.budget.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(budgetStatusProvider);
    final (start, _) = ref.watch(thisPeriodProvider);
    final startDay = ref.watch(monthStartDayProvider);
    return Scaffold(
      body: SafeArea(
        child: asyncBody(status, (list) {
          final total = list.where((b) => b.category == null).firstOrNull;
          final cats = list.where((b) => b.category != null).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              PageHeader(
                '預算',
                overline: unitLabel(PeriodUnit.month, start, startDay: startDay),
                actions: [
                  CircleAction(
                    tooltip: total == null ? '設定每月總預算' : '改每月總預算',
                    icon: Icons.edit_outlined,
                    onPressed: () => _editTotal(context, ref, total),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (list.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('未設預算', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 6),
                      const Text(
                        '設定每月總預算或者分類上限，超支前會提你。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => _edit(context, ref, total: true), child: const Text('設定每月總預算')),
                    ],
                  ),
                )
              else ...[
                BudgetOverviewCard(list),
                BudgetAlertCard(list),
              ],
              const SizedBox(height: 6),
              SectionCard(
                title: '分類預算',
                trailing: TextButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
                child: cats.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('未有分類預算', style: TextStyle(color: AppColors.muted)),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < cats.length; i++) ...[
                            if (i > 0) const Divider(),
                            BudgetBar(
                              cats[i],
                              onTap: () => _edit(context, ref, existing: cats[i]),
                              onLongPress: () => _delete(context, ref, cats[i]),
                            ),
                          ],
                        ],
                      ),
              ),
              if (list.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    '撳一行改上限，長撳刪除。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}
