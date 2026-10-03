import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  AccountType type = AccountType.expense;
  String? drillParent; // 撳入咗邊個主分類
  int touched = -1;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(currentPeriodProvider);
    final accounts = ref.watch(accountMapProvider);
    final totals = ref.watch(categoryTotalsProvider(range));
    final periods = ref.watch(recentPeriodsProvider(range.$1));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const PeriodSwitcher(), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Center(
            child: SegmentedButton<AccountType>(
              segments: const [
                ButtonSegment(value: AccountType.expense, label: Text('支出')),
                ButtonSegment(value: AccountType.income, label: Text('收入')),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() {
                type = s.first;
                drillParent = null;
              }),
            ),
          ),
          const SizedBox(height: 8),
          asyncBody(totals, (t) {
            final slices = _slices(t, accounts);
            final sum = slices.fold(0, (s, x) => s + x.$2);
            if (sum == 0) return const EmptyState('呢個月未有記錄', icon: Icons.pie_chart_outline);
            return Column(
              children: [
                if (drillParent != null)
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: Text(accounts[drillParent]?.name ?? ''),
                    onTap: () => setState(() => drillParent = null),
                  ),
                SizedBox(
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: 60,
                          sectionsSpace: 2,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, resp) {
                              if (!event.isInterestedForInteractions) return;
                              setState(() => touched = resp?.touchedSection?.touchedSectionIndex ?? -1);
                            },
                          ),
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                value: slices[i].$2.toDouble(),
                                color: colorFor(slices[i].$1, context),
                                radius: i == touched ? 58 : 50,
                                title: slices[i].$2 / sum >= 0.06 ? '${(slices[i].$2 * 100 / sum).round()}%' : '',
                                titleStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(type == AccountType.expense ? '總支出' : '總收入', style: theme.textTheme.labelMedium),
                          Text(formatMoney(sum), style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ],
                  ),
                ),
                for (final (a, v) in slices)
                  ListTile(
                    leading: AccountAvatar(a),
                    title: Text(a.id == drillParent ? '${a.name}（未分子類）' : a.name),
                    subtitle: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: ExcludeSemantics(
                        child: LinearProgressIndicator(
                          value: v / sum,
                          color: colorFor(a, context),
                          backgroundColor: colorFor(a, context).withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    trailing: SizedBox(
                      width: 104,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(v)),
                          Text('${(v * 100 / sum).toStringAsFixed(1)}%', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    onTap: drillParent == null && accounts.values.any((c) => c.parentId == a.id)
                        ? () => setState(() => drillParent = a.id)
                        : null,
                  ),
              ],
            );
          }),
          const Divider(height: 32),
          Text('近 6 個月收支', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          SizedBox(height: 220, child: asyncBody(periods, (p) => _TrendChart(p))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_Legend(incomeColor, '收入'), const SizedBox(width: 16), _Legend(expenseColor, '支出')],
          ),
          const Divider(height: 32),
          _TagTotals(range),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  /// 主分類（或撳入咗之後嘅子分類）同合計，大到細。
  List<(Account, int)> _slices(Map<String, int> totals, Map<String, Account> accounts) {
    final sign = type == AccountType.income ? -1 : 1;
    final sums = <String, int>{};
    totals.forEach((id, v) {
      final a = accounts[id];
      if (a == null || a.type != type) return;
      final key = drillParent == null
          ? (a.parentId ?? a.id)
          : (a.parentId == drillParent || a.id == drillParent ? a.id : null);
      if (key == null) return;
      sums[key] = (sums[key] ?? 0) + v * sign;
    });
    final list = [
      for (final MapEntry(:key, :value) in sums.entries)
        if (value > 0 && accounts[key] != null) (accounts[key]!, value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return list;
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart(this.periods);
  final List<PeriodSummary> periods;

  @override
  Widget build(BuildContext context) {
    final maxY = periods.fold(0, (m, p) => [m, p.income, p.expense].reduce((a, b) => a > b ? a : b));
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 100 : maxY / 100 * 1.15,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              formatMoney((rod.toY * 100).round()),
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                if (v == meta.max) return const SizedBox();
                return Text(_compact(v), style: const TextStyle(fontSize: 10));
              },
            ),
          ),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= periods.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${periods[i].start.month}月', style: const TextStyle(fontSize: 12)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < periods.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(toY: periods[i].income / 100, color: incomeColor, width: 10),
                BarChartRodData(toY: periods[i].expense / 100, color: expenseColor, width: 10),
              ],
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}

/// 按 Tag 統計今期支出。
class _TagTotals extends ConsumerWidget {
  const _TagTotals(this.range);
  final (DateTime, DateTime) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TxFilter filter = (
      from: range.$1,
      to: range.$2,
      accountId: null,
      categoryId: null,
      tagId: null,
      kind: EntryKind.expense,
      search: null,
      limit: null,
    );
    final txs = ref.watch(transactionsProvider(filter)).value ?? const <TxView>[];
    final byTag = <String, (Tag, int)>{};
    for (final t in txs) {
      for (final tag in t.tags) {
        final cur = byTag[tag.id]?.$2 ?? 0;
        byTag[tag.id] = (tag, cur + t.amount);
      }
    }
    if (byTag.isEmpty) return const SizedBox();
    final list = byTag.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('按 Tag 支出', style: Theme.of(context).textTheme.titleSmall),
        for (final (tag, v) in list)
          ListTile(dense: true, leading: const Icon(Icons.tag), title: Text(tag.name), trailing: Text(formatMoney(v))),
      ],
    );
  }
}

/// 坐標軸用嘅簡寫，例如 12000 -> 1.2萬
String _compact(double dollars) {
  if (dollars >= 10000) return '${(dollars / 10000).toStringAsFixed(dollars % 10000 == 0 ? 0 : 1)}萬';
  if (dollars >= 1000) return '${(dollars / 1000).toStringAsFixed(dollars % 1000 == 0 ? 0 : 1)}千';
  return dollars.toStringAsFixed(0);
}
