import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'app_spending_screen.dart';
import 'common.dart';
import 'theme.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  PeriodUnit unit = PeriodUnit.month;
  DateTime anchor = DateTime.now();
  AccountType type = AccountType.expense;
  String? drillParent; // 撳入咗邊個主分類
  int touched = -1;

  void _shift(int n) => setState(() {
    anchor = shiftUnit(unit, anchor, n, ref.read(monthStartDayProvider));
    touched = -1;
  });

  @override
  Widget build(BuildContext context) {
    final startDay = ref.watch(monthStartDayProvider);
    final range = unitRange(unit, anchor, startDay);
    final accounts = ref.watch(accountMapProvider);
    final totals = ref.watch(categoryTotalsProvider(range));
    final trend = ref.watch(unitSummariesProvider((unit, range.$1, 6)));
    final isCurrent = !DateTime.now().isBefore(range.$1) && DateTime.now().isBefore(range.$2);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            PageHeader(
              '統計',
              actions: [
                PillSegment<PeriodUnit>(
                  dense: true,
                  options: const {PeriodUnit.week: '週', PeriodUnit.month: '月', PeriodUnit.year: '年'},
                  value: unit,
                  onChanged: (u) => setState(() {
                    unit = u;
                    touched = -1;
                  }),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(tooltip: '上一期', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => anchor = DateTime.now()),
                    child: Text(
                      unitLabel(unit, range.$1, startDay: startDay),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一期',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrent ? null : () => _shift(1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            asyncBody(trend, (t) => _SummaryCard(unit: unit, current: t.last, previous: t[t.length - 2])),
            const SizedBox(height: 6),
            SectionCard(
              title: type == AccountType.expense ? '支出分類' : '收入分類',
              trailing: PillSegment<AccountType>(
                dense: true,
                options: const {AccountType.expense: '支出', AccountType.income: '收入'},
                value: type,
                onChanged: (v) => setState(() {
                  type = v;
                  drillParent = null;
                  touched = -1;
                }),
              ),
              child: asyncBody(totals, (t) => _breakdown(context, t, accounts)),
            ),
            const SizedBox(height: 6),
            asyncBody(trend, (t) => _TrendCard(unit: unit, periods: t, type: type)),
            AppSpendingCard(range),
            _TagTotals(range),
          ],
        ),
      ),
    );
  }

  Widget _breakdown(BuildContext context, Map<String, int> totals, Map<String, Account> accounts) {
    final slices = _slices(totals, accounts);
    final sum = slices.fold(0, (s, x) => s + x.$2);
    if (sum == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '呢期未有記錄',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    final focus = touched >= 0 && touched < slices.length ? touched : 0;
    final (focusAccount, focusValue) = slices[focus];
    String pct(int v) => '${(v * 100 / sum).toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drillParent != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                drillParent = null;
                touched = -1;
              }),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('返回 · ${accounts[drillParent]?.name ?? ''}'),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 148,
              height: 148,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: 46,
                      sectionsSpace: 0,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, resp) {
                          if (!event.isInterestedForInteractions) return;
                          final i = resp?.touchedSection?.touchedSectionIndex ?? -1;
                          if (i >= 0) setState(() => touched = i);
                        },
                      ),
                      sections: [
                        for (var i = 0; i < slices.length; i++)
                          PieChartSectionData(
                            value: slices[i].$2.toDouble(),
                            color: colorFor(slices[i].$1, context),
                            radius: i == touched ? 30 : 26,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          touched >= 0
                              ? formatMoney(focusValue, trimZero: true)
                              : (type == AccountType.expense ? '最大開支' : '最大收入'),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          focusAccount.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          pct(focusValue),
                          style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < slices.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        final a = slices[i].$1;
                        final canDrill = drillParent == null && accounts.values.any((c) => c.parentId == a.id);
                        setState(() {
                          if (canDrill) {
                            drillParent = a.id;
                            touched = -1;
                          } else {
                            touched = i;
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colorFor(slices[i].$1, context),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                slices[i].$1.id == drillParent ? '${slices[i].$1.name}（其他）' : slices[i].$1.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: i == touched ? FontWeight.w800 : FontWeight.w500),
                              ),
                            ),
                            Text(pct(slices[i].$2), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          drillParent == null ? '撳分類睇子分類，撳圓環睇金額' : '撳圓環或者分類睇金額',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 6),
      ],
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

/// 總支出 / 總收入 / 儲蓄率三格。
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.unit, required this.current, required this.previous});
  final PeriodUnit unit;
  final PeriodSummary current;
  final PeriodSummary previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(savingsTargetProvider);
    final rate = current.income > 0 ? current.net * 100 / current.income : null;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            Expanded(
              child: _Cell(
                label: '總支出',
                value: formatMoney(current.expense),
                note: _change(current.expense, previous.expense, upIsBad: true),
              ),
            ),
            const VerticalDivider(width: 20, color: AppColors.line),
            Expanded(
              child: _Cell(
                label: '總收入',
                value: formatMoney(current.income),
                valueColor: AppColors.blue,
                note: _change(current.income, previous.income, upIsBad: false),
              ),
            ),
            const VerticalDivider(width: 20, color: AppColors.line),
            Expanded(
              child: _Cell(
                label: '儲蓄率',
                value: rate == null ? '—' : '${rate.toStringAsFixed(1)}%',
                note: ('目標 $target%', rate != null && rate < target ? AppColors.orange : AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _change(int now, int before, {required bool upIsBad}) {
    final prev = previousLabel(unit);
    if (before == 0) return (now == 0 ? '與$prev持平' : '$prev冇記錄', AppColors.muted);
    final pct = (now - before) * 100 / before;
    if (pct.abs() < 0.5) return ('與$prev持平', AppColors.muted);
    final bad = (pct > 0) == upIsBad;
    return ('比$prev ${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%', bad ? AppColors.orange : AppColors.limeInk);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.note, this.valueColor});
  final String label;
  final String value;
  final (String, Color) note;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: valueColor ?? AppColors.ink),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        note.$1,
        style: TextStyle(color: note.$2, fontSize: 11, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

/// 灰色柱，今期黑色，柱頂有簡寫金額。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.unit, required this.periods, required this.type});
  final PeriodUnit unit;
  final List<PeriodSummary> periods;
  final AccountType type;

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in periods) type == AccountType.expense ? p.expense : p.income];
    final maxV = values.fold(0, (m, v) => v > m ? v : m);
    final avg = values.isEmpty ? 0 : values.reduce((a, b) => a + b) ~/ values.length;
    final unitName = switch (unit) {
      PeriodUnit.week => '週',
      PeriodUnit.month => '個月',
      PeriodUnit.year => '年',
    };
    return SectionCard(
      title: type == AccountType.expense ? '支出趨勢' : '收入趨勢',
      trailing: Text(
        '${periods.length}$unitName平均 ${formatMoney(avg)}',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: SizedBox(
          height: 170,
          child: BarChart(
            BarChartData(
              maxY: maxV == 0 ? 1 : maxV * 1.18,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                enabled: false,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.transparent,
                  tooltipPadding: EdgeInsets.zero,
                  tooltipMargin: 4,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    compactMoney(values[group.x]),
                    TextStyle(
                      color: group.x == values.length - 1 ? AppColors.ink : AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= periods.length) return const SizedBox();
                      final last = i == periods.length - 1;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          unitShortLabel(unit, periods[i].start),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: last ? FontWeight.w800 : FontWeight.w500,
                            color: last ? AppColors.ink : AppColors.muted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(
                    x: i,
                    showingTooltipIndicators: values[i] > 0 ? const [0] : const [],
                    barRods: [
                      BarChartRodData(
                        toY: values[i].toDouble(),
                        color: i == values.length - 1 ? AppColors.ink : AppColors.barGrey,
                        width: 30,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SectionCard(
        title: '按 Tag 支出',
        child: Column(
          children: [
            for (final (tag, v) in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Pill('#${tag.name}', background: AppColors.chip),
                    const Spacer(),
                    Text(formatMoney(v), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
