import 'package:intl/intl.dart';

/// 金額一律用整數「最小單位」（HKD = 仙）。MVP 只支援兩位小數嘅貨幣。
const minorPerUnit = 100;

final _fmt = NumberFormat('#,##0.00', 'en_US');

String formatMoney(int minor, {bool showPlus = false}) {
  final sign = minor < 0 ? '-' : (showPlus && minor > 0 ? '+' : '');
  return '$sign\$${_fmt.format(minor.abs() / minorPerUnit)}';
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
