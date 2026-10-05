import 'package:drift/drift.dart';

import '../data/database.dart';
import 'app_spending.dart';
import 'capture/parser.dart';
import 'capture/taobao.dart' show taobaoSourceKey;
import 'ledger.dart';

/// 冇寫商戶嘅支出歸入呢度。
const unknownPlace = '冇寫地方';

/// 一個地方（淘寶、Google Play、九巴…）使咗幾多；有分店舖 / App 嘅就有 [parts]。
class PlaceSpend {
  PlaceSpend(this.name);
  final String name;
  final List<TxView> txs = [];
  int total = 0;
  DateTime? last;

  /// 淘寶按店舖、Google Play 按 App 分；其他地方係空。
  final Map<String, PlaceSpend> parts = {};

  void _add(TxView t) {
    txs.add(t);
    total += t.amount;
    if (last == null || t.entry.occurredAt.isAfter(last!)) last = t.entry.occurredAt;
  }

  /// [parts] 多到少排。
  List<PlaceSpend> get sortedParts => parts.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

/// 一筆支出喺邊度使：淘寶匯入嘅 = 淘寶、Google Play 購買 = Google Play、其他用商戶名。
/// 第二個值係淘寶店舖或者 Play 嘅 App 名，其他係 null。
(String, String?) placeOf(TxView t) {
  final id = t.entry.externalId ?? '';
  final merchant = t.entry.merchant?.trim();
  if (id.startsWith('taobao:')) return ('淘寶', merchant == null || merchant.isEmpty ? null : merchant);
  if (id.startsWith('takeout:')) {
    return ('Google Play', merchant == null || merchant.isEmpty ? null : appNameFromTitle(merchant));
  }
  if (merchant == null || merchant.isEmpty) return (unknownPlace, null);
  return (merchant, null);
}

/// 支出按地方分組，多到少排；每組入面嘅交易新到舊。
List<PlaceSpend> groupByPlace(Iterable<TxView> txs) {
  final byKey = <String, PlaceSpend>{};
  for (final t in txs) {
    if (t.entry.kind != EntryKind.expense) continue;
    final (name, part) = placeOf(t);
    final place = byKey.putIfAbsent(merchantKey(name), () => PlaceSpend(name)).._add(t);
    if (part != null) place.parts.putIfAbsent(merchantKey(part), () => PlaceSpend(part))._add(t);
  }
  final list = byKey.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  for (final p in list) {
    for (final x in [p, ...p.parts.values]) {
      x.txs.sort((a, b) => b.entry.occurredAt.compareTo(a.entry.occurredAt));
    }
  }
  return list;
}

/// 淘寶匯入時記低嘅商品名，按入帳記錄 id（匯入內容第一行係商品，第二行係人民幣金額）。
Future<Map<String, String>> loadBoughtItems(AppDatabase db) async {
  final rows = await (db.select(
    db.captures,
  )..where((c) => c.entryId.isNotNull() & c.sourceKey.equals(taobaoSourceKey))).get();
  return {
    for (final c in rows)
      if (c.body.split('\n') case [final items, _, ...]) c.entryId!: items,
  };
}
