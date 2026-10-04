import 'package:flutter/material.dart';

import '../domain/money.dart';

/// 設計圖嘅顏色：淺灰底、白卡、黑色主色、青檸色強調。
abstract final class AppColors {
  static const bg = Color(0xFFEEF0F3);
  static const card = Colors.white;
  static const ink = Color(0xFF131417);
  static const inkSoft = Color(0xFF2B2D33);
  static const muted = Color(0xFF7A7F88);
  static const line = Color(0xFFECEEF1);
  static const track = Color(0xFFE6E8EC);
  static const chip = Color(0xFFF1F2F4);
  static const keypadBg = Color(0xFFDFE2E6);
  static const keyGrey = Color(0xFFC9CDD3);
  static const lime = Color(0xFFC8F169);
  static const limeInk = Color(0xFF4B6410);
  static const orange = Color(0xFFC2501A);
  static const peach = Color(0xFFFBE4D8);
  static const peachInk = Color(0xFF8A3A12);
  static const blue = Color(0xFF2F55D4);
  static const barGrey = Color(0xFFCDD1D7);
}

abstract final class AppRadius {
  static const card = 24.0;
  static const tile = 14.0;
  static const field = 16.0;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.ink, brightness: Brightness.light).copyWith(
    primary: AppColors.ink,
    onPrimary: Colors.white,
    secondary: AppColors.lime,
    onSecondary: AppColors.ink,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    surfaceContainerHighest: AppColors.chip,
    outline: AppColors.muted,
    outlineVariant: AppColors.line,
    error: AppColors.orange,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 28),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.card))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.field), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.chip,
      selectedColor: AppColors.ink,
      secondarySelectedColor: AppColors.ink,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: AppColors.ink),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      checkmarkColor: AppColors.lime,
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.ink),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: AppColors.lime,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.track,
      circularTrackColor: AppColors.track,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.lime : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.ink : null),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.ink,
      foregroundColor: AppColors.lime,
      shape: CircleBorder(),
    ),
  );
}

/// 白色圓角卡。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 有標題（同可選右上角動作）嘅卡。
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// 右上角白色圓形掣。
class CircleAction extends StatelessWidget {
  const CircleAction({super.key, required this.icon, required this.onPressed, required this.tooltip, this.size = 46});
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.card,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: AppColors.ink, size: 22),
          ),
        ),
      ),
    );
  }
}

/// 頁頂大標題，例如「預算」，上面可以有細字（2026年10月）。
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.overline, this.actions = const []});
  final String title;
  final String? overline;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) Text(overline!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                Text(title, style: Theme.of(context).textTheme.headlineLarge),
              ],
            ),
          ),
          for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
        ],
      ),
    );
  }
}

/// 黑色膠囊分段掣（支出 / 收入 / 轉帳、週 / 月 / 年）。
class PillSegment<T> extends StatelessWidget {
  const PillSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.keyGrey.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(:key, value: label) in options.entries)
            Semantics(
              button: true,
              selected: key == value,
              child: GestureDetector(
                onTap: () => onChanged(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 20, vertical: dense ? 8 : 10),
                  decoration: BoxDecoration(
                    color: key == value ? AppColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: key == value ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 細膠囊標籤，例如「比上月 +HK$4,215.20」。
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.background = AppColors.lime, this.foreground = AppColors.ink});
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

/// 大字金額：細前綴 HK$、大整數、淡色小數。
class BigMoney extends StatelessWidget {
  const BigMoney(this.minor, {super.key, this.color = AppColors.ink, this.size = 44, this.dimColor});
  final int minor;
  final Color color;
  final double size;
  final Color? dimColor;

  @override
  Widget build(BuildContext context) {
    final (whole, decimals) = splitMoney(minor);
    final dim = dimColor ?? color.withValues(alpha: 0.45);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${minor < 0 ? '-' : ''}$moneySymbol ',
            style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: dim),
          ),
          TextSpan(
            text: whole,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color, letterSpacing: -1),
          ),
          TextSpan(
            text: decimals,
            style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w800, color: dim),
          ),
        ],
      ),
      semanticsLabel: formatMoney(minor),
    );
  }
}

/// 進度條（圓角、可轉色）。唔會將數值讀出嚟，避免干擾標籤。
class ProgressBar extends StatelessWidget {
  const ProgressBar(this.value, {super.key, this.color = AppColors.ink, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: height,
          color: color,
          backgroundColor: AppColors.track,
        ),
      ),
    );
  }
}
