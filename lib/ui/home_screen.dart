import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'budgets_screen.dart';
import 'capture_screens.dart';
import 'common.dart';
import 'entry_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'transactions_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(thisPeriodProvider);
    final startDay = ref.watch(monthStartDayProvider);
    final summary = ref.watch(summaryProvider(range));
    final accounts = ref.watch(accountMapProvider);
    final templates = ref.watch(templatesProvider).value ?? const <Template>[];
    final budgets = ref.watch(budgetStatusProvider).value ?? const <BudgetStatus>[];
    final netWorth = ref.watch(spendingOnlyProvider) ? null : ref.watch(netWorthProvider).value;
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
    void goTab(int i) => ref.read(homeTabProvider.notifier).select(i);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            PageHeader(
              'Money Expense',
              overline: formatDate(DateTime.now()),
              actions: [
                CircleAction(
                  tooltip: '設定',
                  icon: Icons.settings_outlined,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              onTap: () => goTab(1),
              child: summary.when(
                loading: () => const SizedBox(height: 110),
                error: (e, _) => Text('$e', style: const TextStyle(color: Colors.white)),
                data: (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${unitLabel(PeriodUnit.month, range.$1, startDay: startDay)} 總支出',
                      style: const TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: BigMoney(s.expense, color: Colors.white, dimColor: const Color(0xFF8C9099)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _DarkFigure('收入', formatMoney(s.income))),
                        Expanded(child: _DarkFigure('結餘', formatMoney(s.net, showPlus: true))),
                        if (netWorth != null)
                          Expanded(child: _DarkFigure('淨資產', formatMoney(netWorth.$1 - netWorth.$2))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const PendingCapturesCard(),
            if (budgets.isNotEmpty) ...[
              const SizedBox(height: 6),
              SectionCard(
                title: '預算',
                trailing: TextButton(onPressed: () => goTab(2), child: const Text('查看')),
                child: Column(children: [for (final b in _highlights(budgets)) BudgetBar(b, onTap: () => goTab(2))]),
              ),
            ] else ...[
              const SizedBox(height: 6),
              AppCard(
                onTap: () => goTab(2),
                child: const Row(
                  children: [
                    Icon(Icons.savings_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('設定每月預算', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
            if (templates.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Text(
                  '常用（撳一下即記，長撳先改）',
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
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
                            backgroundColor: AppColors.card,
                            avatar: accounts[t.toAccountId] != null
                                ? AccountAvatar(accounts[t.toAccountId]!, radius: 10)
                                : null,
                            label: Text('${t.name} ${formatMoney(t.amount, trimZero: true)}'),
                            onPressed: () => _useTemplate(context, ref, t),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            SectionCard(
              title: '最近交易',
              trailing: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                child: const Text('查看全部'),
              ),
              child: recent.when(
                loading: () => const SizedBox(height: 64),
                error: (e, _) => Text('$e'),
                data: (list) => list.isEmpty
                    ? const EmptyState('未有交易。撳下面 + 記第一筆。', icon: Icons.edit_note)
                    : Column(children: [for (final t in list) TxTile(t, accounts: accounts)]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 首頁只顯示總預算同最緊張嘅兩個分類。
  List<BudgetStatus> _highlights(List<BudgetStatus> all) {
    final total = all.where((b) => b.category == null);
    final cats = all.where((b) => b.category != null).toList()..sort((a, b) => b.ratio.compareTo(a.ratio));
    return [...total, ...cats.take(total.isEmpty ? 3 : 2)];
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

class _DarkFigure extends StatelessWidget {
  const _DarkFigure(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFB9BDC4), fontSize: 12)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ],
    ),
  );
}

/// 長撳模板：改金額先記
Future<void> openTemplateForEdit(BuildContext context, WidgetRef ref, Template t) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => EntryScreen(initial: ref.read(ledgerProvider).draftFromTemplate(t))),
);
