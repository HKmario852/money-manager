import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/app_spending.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';
import 'theme.dart';
import 'transactions_screen.dart';

const _appsChannel = MethodChannel('hk.mario.money_manager/apps');

/// 電話上裝咗嘅 App 圖示（按 App 名搵）。冇裝或者唔係 Android 就冇。
final appIconsProvider = FutureProvider.family<Map<String, Uint8List>, String>((ref, joinedNames) async {
  if (defaultTargetPlatform != TargetPlatform.android || joinedNames.isEmpty) return const {};
  try {
    final r = await _appsChannel.invokeMapMethod<String, Uint8List>('icons', joinedNames.split('\n'));
    return r ?? const {};
  } catch (_) {
    return const {};
  }
});

/// 課金 / 訂閱 / 遊戲嘅支出，按 App 分組。
final appSpendingProvider = Provider.autoDispose.family<AsyncValue<List<AppSpend>>, (DateTime?, DateTime?)>((
  ref,
  range,
) {
  final accounts = ref.watch(accountMapProvider);
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
  return ref.watch(transactionsProvider(filter)).whenData((txs) => groupByApp(txs, appCategoryIds(accounts.values)));
});

String _iconKey(Iterable<AppSpend> apps) => (apps.map((a) => a.name).toList()..sort()).join('\n');

/// App 圖示；搵唔到就用 App 名第一個字（同分類方塊一樣）。
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, this.icon, {super.key, this.size = 40});
  final String name;
  final Uint8List? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    if (icon != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(icon!, width: size, height: size, gaplessPlayback: true),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.lime, borderRadius: radius),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: AppColors.limeInk, fontSize: size * 0.45, fontWeight: FontWeight.w800, height: 1),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow(this.app, this.icon, this.max, {required this.onTap});
  final AppSpend app;
  final Uint8List? icon;
  final int max;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AppIcon(app.name, icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(formatMoney(app.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : app.total / max,
                      minHeight: 6,
                      color: AppColors.ink,
                      backgroundColor: AppColors.track,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${app.purchases.length} 筆 · 最近 ${formatDate(app.last!, withYear: true)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 統計頁：今期邊個 App 用最多錢。
class AppSpendingCard extends ConsumerWidget {
  const AppSpendingCard(this.range, {super.key});
  final (DateTime, DateTime) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appSpendingProvider((range.$1, range.$2))).value ?? const <AppSpend>[];
    if (apps.isEmpty) return const SizedBox();
    final top = apps.take(5).toList();
    final icons = ref.watch(appIconsProvider(_iconKey(top))).value ?? const {};
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SectionCard(
        title: 'App 課金',
        trailing: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSpendingScreen())),
          child: const Text('全部'),
        ),
        child: Column(
          children: [
            for (final a in top)
              _AppRow(
                a,
                icons[a.name],
                top.first.total,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailScreen(a.name))),
              ),
          ],
        ),
      ),
    );
  }
}

enum _Span { month, year, all }

class AppSpendingScreen extends ConsumerStatefulWidget {
  const AppSpendingScreen({super.key});

  @override
  ConsumerState<AppSpendingScreen> createState() => _AppSpendingScreenState();
}

class _AppSpendingScreenState extends ConsumerState<AppSpendingScreen> {
  _Span span = _Span.all;

  @override
  Widget build(BuildContext context) {
    final startDay = ref.watch(monthStartDayProvider);
    final now = DateTime.now();
    final (DateTime?, DateTime?) range = switch (span) {
      _Span.month => unitRange(PeriodUnit.month, now, startDay),
      _Span.year => unitRange(PeriodUnit.year, now, startDay),
      _Span.all => (null, null),
    };
    final apps = ref.watch(appSpendingProvider(range));
    final icons = ref.watch(appIconsProvider(_iconKey(apps.value ?? const []))).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('App 課金')),
      body: asyncBody(apps, (list) {
        final total = list.fold(0, (s, a) => s + a.total);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PillSegment<_Span>(
                options: const {_Span.month: '今個月', _Span.year: '今年', _Span.all: '全部'},
                value: span,
                onChanged: (v) => setState(() => span = v),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${list.length} 個 App · ${list.fold(0, (s, a) => s + a.purchases.length)} 筆',
                    style: const TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BigMoney(total, color: Colors.white, dimColor: const Color(0xFF8C9099)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (list.isEmpty)
              const EmptyState('呢段時間未有課金、訂閱或者買 App 嘅記錄', icon: Icons.sports_esports_outlined)
            else
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    for (final a in list)
                      _AppRow(
                        a,
                        icons[a.name],
                        list.first.total,
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailScreen(a.name))),
                      ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// 一個 App 嘅所有購買。
class AppDetailScreen extends ConsumerWidget {
  const AppDetailScreen(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appSpendingProvider((null, null)));
    final accounts = ref.watch(accountMapProvider);
    final icon = ref.watch(appIconsProvider(name)).value?[name];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: asyncBody(apps, (list) {
        final app = list.where((a) => a.name == name).firstOrNull;
        if (app == null) return const EmptyState('冇記錄', icon: Icons.sports_esports_outlined);
        final year = DateTime.now().year;
        final thisYear = app.purchases.where((t) => t.entry.occurredAt.year == year).fold(0, (s, t) => s + t.amount);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Row(
                children: [
                  AppIcon(name, icon, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '總共用咗',
                          style: TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: BigMoney(app.total, color: Colors.white, dimColor: const Color(0xFF8C9099), size: 36),
                        ),
                        Text(
                          '${app.purchases.length} 筆 · $year 年 ${formatMoney(thisYear)}',
                          style: const TextStyle(color: Color(0xFFB9BDC4)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [for (final t in app.purchases) TxTile(t, accounts: accounts)]),
            ),
          ],
        );
      }),
    );
  }
}
