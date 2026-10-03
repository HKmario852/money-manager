import 'package:intl/intl.dart';

/// 金額一律用整數「最小單位」（HKD = 仙）。MVP 只支援兩位小數嘅貨幣。
const minorPerUnit = 100;

final _fmt = NumberFormat('#,##0.00', 'en_US');

/// 金額前綴，跟基準貨幣設定（App 開啟時更新）。
String moneySymbol = 'HK\$';

const _symbols = {
  'HKD': 'HK\$',
  'CNY': '¥',
  'TWD': 'NT\$',
  'MOP': 'MOP\$',
  'USD': 'US\$',
  'JPY': '¥',
  'GBP': '£',
  'EUR': '€',
  'SGD': 'S\$',
};

String symbolFor(String currency) => _symbols[currency] ?? '\$';

/// 例如 -HK$1,234.50。[symbol] 可以傳 '\$' 做短寫。[trimZero] 會將 .00 省略。
String formatMoney(int minor, {bool showPlus = false, String? symbol, bool trimZero = false}) {
  final sign = minor < 0 ? '-' : (showPlus && minor > 0 ? '+' : '');
  var number = _fmt.format(minor.abs() / minorPerUnit);
  if (trimZero && number.endsWith('.00')) number = number.substring(0, number.length - 3);
  return '$sign${symbol ?? moneySymbol}$number';
}

/// 拆開整數同小數部分，方便大字顯示（小數用淡色）。
(String whole, String decimals) splitMoney(int minor) {
  final s = _fmt.format(minor.abs() / minorPerUnit);
  final i = s.indexOf('.');
  return (s.substring(0, i), s.substring(i));
}

/// 坐標軸 / 標籤用嘅簡寫：12500 元 -> 12.5k
String compactMoney(int minor) {
  final v = minor / minorPerUnit;
  if (v.abs() >= 1000) {
    final k = v / 1000;
    return '${k.toStringAsFixed(k.abs() >= 100 ? 0 : 1)}k';
  }
  return v.toStringAsFixed(0);
}

/// 將數字鍵盤輸入（例如 "12.5+30-3"）計成最小單位。無效輸入返回 null。
int? evaluateAmount(String expression) {
  final cleaned = expression.replaceAll(',', '').replaceAll(' ', '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'^[+-]?\d*\.?\d{0,2}([+-]\d*\.?\d{0,2})*$');
  if (!match.hasMatch(cleaned)) return null;
  var total = 0;
  for (final m in RegExp(r'([+-]?)(\d*\.?\d*)').allMatches(cleaned)) {
    final number = m.group(2)!;
    if (number.isEmpty) continue;
    final value = parseMinor(number);
    if (value == null) return null;
    total += m.group(1) == '-' ? -value : value;
  }
  return total;
}

/// "12.5" -> 1250。用字串處理，避免浮點誤差。
int? parseMinor(String text) {
  if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text) || text == '.') return null;
  final parts = text.split('.');
  final whole = parts[0].isEmpty ? 0 : int.parse(parts[0]);
  final frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return whole * minorPerUnit + int.parse(frac);
}

/// 最小單位 -> 編輯用字串，例如 1250 -> "12.5"
String minorToInput(int minor) {
  final whole = minor ~/ minorPerUnit;
  final frac = minor.abs() % minorPerUnit;
  if (frac == 0) return '$whole';
  final f = frac.toString().padLeft(2, '0');
  return '$whole.${f.endsWith('0') ? f[0] : f}';
}

/// 「月份」可以由每月第 N 日開始（例如出糧日）。返回 [start, end)。
(DateTime, DateTime) periodRange(DateTime anchor, int startDay) {
  final day = startDay.clamp(1, 28);
  var start = DateTime(anchor.year, anchor.month, day);
  if (anchor.isBefore(start)) start = DateTime(anchor.year, anchor.month - 1, day);
  final end = DateTime(start.year, start.month + 1, day);
  return (start, end);
}

/// 期間嘅顯示名，以起始月份命名，例如 "2026年10月"
String periodLabel(DateTime periodStart) => '${periodStart.year}年${periodStart.month}月';

/// 統計頁用嘅期間單位。
enum PeriodUnit { week, month, year }

/// 包含 anchor 嘅一期，返回 [start, end)。週由星期一開始；年用曆年。
(DateTime, DateTime) unitRange(PeriodUnit unit, DateTime anchor, int startDay) => switch (unit) {
  PeriodUnit.week => () {
    final start = DateTime(anchor.year, anchor.month, anchor.day - (anchor.weekday - 1));
    return (start, DateTime(start.year, start.month, start.day + 7));
  }(),
  PeriodUnit.month => periodRange(anchor, startDay),
  PeriodUnit.year => (DateTime(anchor.year), DateTime(anchor.year + 1)),
};

/// 向前 / 向後移 n 期，返回新一期嘅開始日。
DateTime shiftUnit(PeriodUnit unit, DateTime anchor, int n, int startDay) {
  final (start, _) = unitRange(unit, anchor, startDay);
  return switch (unit) {
    PeriodUnit.week => DateTime(start.year, start.month, start.day + 7 * n),
    PeriodUnit.month => DateTime(start.year, start.month + n, start.day),
    PeriodUnit.year => DateTime(start.year + n),
  };
}

/// 由舊到新，最後一期包含 anchor。
List<(DateTime, DateTime)> recentRanges(PeriodUnit unit, DateTime anchor, int startDay, int count) => [
  for (var i = count - 1; i >= 0; i--) unitRange(unit, shiftUnit(unit, anchor, -i, startDay), startDay),
];

/// 例如「2026年9月」、「2026年」、「9月28日 – 10月4日」
String unitLabel(PeriodUnit unit, DateTime start, {int startDay = 1}) {
  switch (unit) {
    case PeriodUnit.week:
      final last = DateTime(start.year, start.month, start.day + 6);
      return '${start.month}月${start.day}日 – ${last.month}月${last.day}日';
    case PeriodUnit.month:
      if (startDay == 1) return periodLabel(start);
      final last = DateTime(start.year, start.month + 1, start.day - 1);
      return '${start.month}/${start.day} – ${last.month}/${last.day}';
    case PeriodUnit.year:
      return '${start.year}年';
  }
}

/// 圖表下面嘅短標籤，例如「9月」、「9/28」、「2026」
String unitShortLabel(PeriodUnit unit, DateTime start) => switch (unit) {
  PeriodUnit.week => '${start.month}/${start.day}',
  PeriodUnit.month => '${start.month}月',
  PeriodUnit.year => '${start.year}',
};

/// 「上月」、「上週」、「上年」
String previousLabel(PeriodUnit unit) => switch (unit) {
  PeriodUnit.week => '上週',
  PeriodUnit.month => '上月',
  PeriodUnit.year => '上年',
};
