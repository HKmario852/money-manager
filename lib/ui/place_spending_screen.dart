import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/money.dart';
import '../domain/place_spending.dart';
import '../providers.dart';
import 'app_spending_screen.dart' show AppIcon;
import 'common.dart';
import 'theme.dart';
import 'transactions_screen.dart';

/// 支出按地方（淘寶、Google Play、商戶）分組。
final placeSpendingProvider = Provider.autoDispose.family<AsyncValue<List<PlaceSpend>>, (DateTime?, DateTime?)>((
  ref,
  range,
) {
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
  return ref.watch(transactionsProvider(filter)).whenData(groupByPlace);
});

/// 匯入時記低嘅貨品（例如淘寶訂單嘅商品名），按入帳記錄 id。
final boughtItemsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(pendingCapturesProvider); // 入帳之後再讀
  return loadBoughtItems(db);
});

class _PlaceRow extends StatelessWidget {
  const _PlaceRow(this.place, this.max, {required this.onTap});
  final PlaceSpend place;
  final int max;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final extra = place.parts.isEmpty ? '' : ' · ${place.parts.length} ${place.name == '淘寶' ? '間店' : '個 App'}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AppIcon(place.name, null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(formatMoney(place.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : place.total / max,
                      minHeight: 6,
                      color: AppColors.ink,
                      backgroundColor: AppColors.track,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${place.txs.length} 筆$extra · 最近 ${formatDate(place.last!, withYear: true)}',
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

void _open(BuildContext context, PlaceSpend place, (DateTime?, DateTime?) range) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlaceDetailScreen(place.name, range: range)));

/// 統計頁：今期喺邊度使錢最多。
class PlaceSpendingCard extends ConsumerWidget {
  const PlaceSpendingCard(this.range, {super.key});
  final (DateTime, DateTime) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = (ref.watch(placeSpendingProvider((range.$1, range.$2))).value ?? const <PlaceSpend>[])
        .where((p) => p.name != unknownPlace)
        .toList();
    if (places.isEmpty) return const SizedBox();
    final top = places.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SectionCard(
        title: '邊度使錢',
        trailing: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaceSpendingScreen())),
          child: const Text('全部'),
        ),
        child: Column(
          children: [
            for (final p in top) _PlaceRow(p, top.first.total, onTap: () => _open(context, p, (range.$1, range.$2))),
          ],
        ),
      ),
    );
  }
}

enum _Span { month, year, all }

(DateTime?, DateTime?) _spanRange(_Span span, int startDay) {
  final now = DateTime.now();
  return switch (span) {
    _Span.month => unitRange(PeriodUnit.month, now, startDay),
    _Span.year => unitRange(PeriodUnit.year, now, startDay),
    _Span.all => (null, null),
  };
}

class PlaceSpendingScreen extends ConsumerStatefulWidget {
  const PlaceSpendingScreen({super.key});

  @override
  ConsumerState<PlaceSpendingScreen> createState() => _PlaceSpendingScreenState();
}

class _PlaceSpendingScreenState extends ConsumerState<PlaceSpendingScreen> {
  _Span span = _Span.year;

  @override
  Widget build(BuildContext context) {
    final range = _spanRange(span, ref.watch(monthStartDayProvider));
    final places = ref.watch(placeSpendingProvider(range));
    return Scaffold(
      appBar: AppBar(title: const Text('邊度使錢')),
      body: asyncBody(places, (list) {
        final total = list.fold(0, (s, p) => s + p.total);
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
                    '${list.length} 個地方 · ${list.fold(0, (s, p) => s + p.txs.length)} 筆',
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
              const EmptyState('呢段時間未有支出', icon: Icons.storefront_outlined)
            else
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    for (final p in list) _PlaceRow(p, list.first.total, onTap: () => _open(context, p, range)),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// 一個地方：有分店舖 / App 就先列佢哋，再列每筆。
class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen(this.name, {super.key, this.range = (null, null), this.part});
  final String name;
  final (DateTime?, DateTime?) range;

  /// 淘寶嘅某間店（或者 Play 嘅某個 App）
  final String? part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placeSpendingProvider(range));
    final accounts = ref.watch(accountMapProvider);
    final items = ref.watch(boughtItemsProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: Text(part ?? name)),
      body: asyncBody(places, (list) {
        var place = list.where((p) => p.name == name).firstOrNull;
        if (place != null && part != null) place = place.parts.values.where((x) => x.name == part).firstOrNull;
        if (place == null) return const EmptyState('呢段時間冇記錄', icon: Icons.storefront_outlined);
        final parts = place.sortedParts;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    range.$1 == null ? '總共用咗' : '${formatDate(range.$1!, withYear: true)} 起',
                    style: const TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BigMoney(place.total, color: Colors.white, dimColor: const Color(0xFF8C9099), size: 36),
                  ),
                  Text('${place.txs.length} 筆', style: const TextStyle(color: Color(0xFFB9BDC4))),
                ],
              ),
            ),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: 6),
              SectionCard(
                title: name == '淘寶' ? '店舖' : 'App',
                child: Column(
                  children: [
                    for (final p in parts)
                      _PlaceRow(
                        p,
                        parts.first.total,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaceDetailScreen(name, range: range, part: p.name),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final t in place.txs)
                    if (items[t.entry.id] case final bought?)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TxTile(t, accounts: accounts),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                            child: Text(
                              bought,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ),
                        ],
                      )
                    else
                      TxTile(t, accounts: accounts),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
