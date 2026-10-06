import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../money.dart';
import '../xlsx.dart';
import 'capture_service.dart';
import 'parser.dart';

/// 淘寶訂單匯入嘅來源 key（用嚟記住淘寶用邊個賬戶俾錢，例如 AlipayHK）。
const taobaoSourceKey = 'taobao';

/// 淘寶訂單 extension 匯出嘅檔案格式名：新版係 taobao-order-export，舊版檔係 money-expense-taobao。
const taobaoExportFormats = {'taobao-order-export', 'money-expense-taobao'};

/// 淘寶訂單入嘅分類：購物 › 淘寶，統計入面可以分開睇。
const taobaoCategoryPath = '購物 › 淘寶';

/// 淘寶訂單金額係人民幣，換算港幣後同錢包通知嘅金額可能差少少，呢個範圍內當同一筆。
const taobaoAmountTolerance = 0.03;

class TaobaoException implements Exception {
  const TaobaoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 訂單入面一件貨。
class TaobaoItem {
  const TaobaoItem(this.title, {this.qty = 1, this.priceFen, this.sku, this.imageUrl, this.url});
  final String title;
  final int qty;

  /// 呢件貨實付（人民幣分），冇就 null
  final int? priceFen;
  final String? sku;
  final String? imageUrl;

  /// 商品頁
  final String? url;

  /// 「手機殼 ×2」
  String get label => qty > 1 ? '$title ×$qty' : title;
}

/// 「已買到的寶貝」入面嘅一張訂單。
class TaobaoOrder {
  TaobaoOrder({
    required this.id,
    required this.at,
    required this.shop,
    List<String>? items,
    this.lines = const [],
    required this.paidFen,
    required this.status,
  }) : items = items ?? [for (final l in lines) l.label];

  final String id;
  final DateTime at;
  final String shop;

  /// 每件貨一行字，例如「手機殼 ×2」
  final List<String> items;

  /// 每件貨嘅詳情（名、款式、相）
  final List<TaobaoItem> lines;

  /// 實付款（人民幣分）
  final int paidFen;
  final String status;
}

// 未俾錢、取消咗或者全數退款嘅訂單唔使記
final _skipStatus = RegExp(r'等待買家付款|等待买家付款|等待付款|交易關閉|交易关闭|已取消|退款成功|已退款');

/// 讀淘寶「导出订单」嘅 Excel，或者 extension 匯出嘅 JSON。都唔係就拋 [TaobaoException]。
Future<List<TaobaoOrder>> readTaobaoExport(String path) async {
  final bytes = await File(path).readAsBytes();
  final List<TaobaoOrder>? orders;
  if (path.toLowerCase().endsWith('.xlsx')) {
    final List<List<String>> rows;
    try {
      rows = readXlsxRows(bytes);
    } on FormatException catch (e) {
      throw TaobaoException('讀唔到個 Excel：${e.message}');
    }
    orders = parseTaobaoXlsx(rows);
  } else {
    orders = parseTaobaoExport(utf8.decode(bytes, allowMalformed: true));
  }
  if (orders == null) {
    throw const TaobaoException('呢個檔唔係淘寶訂單：要用「已買到的寶貝 › 导出订单」下載嘅 Excel，或者 extension 匯出嘅 JSON');
  }
  return orders;
}

/// 唔係淘寶匯出檔返回 null。未付款、取消、退款同讀唔到金額嘅訂單會略過。
List<TaobaoOrder>? parseTaobaoExport(String text) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (data is! Map || !taobaoExportFormats.contains(data['format']) || data['orders'] is! List) return null;
  final out = <TaobaoOrder>[];
  for (final o in (data['orders'] as List).whereType<Map>()) {
    final id = '${o['id'] ?? ''}'.trim();
    final at = _parseTime('${o['time'] ?? ''}');
    final paid = parseMinor('${o['paid'] ?? ''}'.replaceAll(RegExp(r'[^0-9.]'), ''));
    final status = '${o['status'] ?? ''}'.trim();
    if (id.isEmpty || at == null || paid == null || paid <= 0 || _skipStatus.hasMatch(status)) continue;
    out.add(
      TaobaoOrder(
        id: id,
        at: at,
        shop: '${o['shop'] ?? ''}'.trim(),
        lines: [
          for (final i in (o['items'] as List? ?? const []).whereType<Map>())
            if ('${i['title'] ?? ''}'.trim() case final t when t.isNotEmpty)
              TaobaoItem(
                t,
                qty: i['qty'] is num && (i['qty'] as num) > 1 ? (i['qty'] as num).toInt() : 1,
                priceFen: _fen('${i['price'] ?? ''}'),
                sku: _blank('${i['sku'] ?? ''}'),
                imageUrl: _imageUrl('${i['pic'] ?? ''}'),
                url: _imageUrl('${i['url'] ?? ''}'),
              ),
        ],
        paidFen: paid,
        status: status,
      ),
    );
  }
  return out;
}

// 淘寶 Excel 嘅欄位名（簡體為主，繁體都認）
const _colId = ['订单号', '訂單號', '订单编号', '訂單編號'];
const _colTime = ['订单提交时间', '訂單提交時間', '订单创建时间', '下单时间', '成交时间'];
const _colStatus = ['订单状态', '訂單狀態', '交易状态'];
const _colShop = ['店铺名称', '店鋪名稱', '卖家', '賣家'];
const _colTitle = ['商品名称', '商品名稱', '宝贝名称', '商品标题'];
const _colQty = ['商品数量', '商品數量', '购买数量', '数量'];
const _colPaid = ['实付金额', '實付金額', '实付款', '买家实付'];
const _colSku = ['型号款式', '型號款式', '商品属性', '商品屬性'];
const _colPrice = ['商品金额', '商品金額'];
const _colLink = ['商品链接', '商品鏈接', '商品連結'];

/// 淘寶「导出订单」Excel：每件貨一行；同一張單第二件貨起嗰幾行冇訂單號同實付。唔係呢種表就返回 null。
List<TaobaoOrder>? parseTaobaoXlsx(List<List<String>> rows) {
  final headerAt = rows.indexWhere((r) => r.any((c) => _colId.contains(c.trim())));
  if (headerAt < 0) return null;
  final header = [for (final c in rows[headerAt]) c.trim()];
  int col(List<String> names) => header.indexWhere(names.contains);
  final (iId, iTime, iStatus, iShop, iTitle, iQty, iPaid, iSku, iPrice, iLink) = (
    col(_colId),
    col(_colTime),
    col(_colStatus),
    col(_colShop),
    col(_colTitle),
    col(_colQty),
    col(_colPaid),
    col(_colSku),
    col(_colPrice),
    col(_colLink),
  );
  if (iTime < 0 || iPaid < 0) return null;
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  final byOrder = <String, List<List<String>>>{};
  String? last;
  for (final r in rows.skip(headerAt + 1)) {
    final id = cell(r, iId);
    if (id.isEmpty) {
      // 同一張單嘅第二件貨起：淘寶淨係寫商品，冇訂單號同實付
      if (last != null && cell(r, iTitle).isNotEmpty) byOrder[last]!.add(r);
      continue;
    }
    // 太長嘅訂單號存咗做數字會變「1.23E+18」，用唔到
    if (id.contains('E+')) {
      last = null;
      continue;
    }
    byOrder.putIfAbsent(id, () => []).add(r);
    last = id;
  }

  final out = <TaobaoOrder>[];
  for (final MapEntry(key: id, value: lines) in byOrder.entries) {
    final first = lines.first;
    final status = cell(first, iStatus);
    final at = _parseTime(cell(first, iTime)) ?? _excelTime(cell(first, iTime));
    final paidEach = [
      for (final r in lines)
        if (cell(r, iPaid).isNotEmpty) _fen(cell(r, iPaid)),
    ];
    if (at == null || paidEach.isEmpty || paidEach.any((p) => p == null) || _skipStatus.hasMatch(status)) continue;
    // 只得一個實付 = 成張單；每行一樣 = 每件都寫咗成張單嘅數；唔一樣 = 每件嘅實付，要加埋
    final same = paidEach.every((p) => p == paidEach.first);
    final paid = same ? paidEach.first! : paidEach.fold(0, (s, p) => s + p!);
    if (paid <= 0) continue;
    out.add(
      TaobaoOrder(
        id: id,
        at: at,
        shop: cell(first, iShop),
        lines: [
          for (final r in lines)
            if (cell(r, iTitle) case final t when t.isNotEmpty)
              TaobaoItem(
                t,
                qty: (int.tryParse(cell(r, iQty)) ?? 1).clamp(1, 1 << 30),
                priceFen: _fen(cell(r, iPrice)),
                sku: _blank(cell(r, iSku)),
                url: _imageUrl(cell(r, iLink)),
              ),
        ],
        paidFen: paid,
        status: status,
      ),
    );
  }
  return out;
}

String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

/// 淘寶網址（商品相、商品頁）：「//img…」補 https；唔係網址就 null
String? _imageUrl(String s) {
  final u = s.trim();
  if (u.startsWith('//')) return 'https:$u';
  return u.startsWith('https://') ? u : (u.startsWith('http://') ? 'https://${u.substring(7)}' : null);
}

/// 記低每張單嘅每件貨（再匯入會換新），睇訂單詳情用。
Future<void> saveTaobaoItems(AppDatabase db, Iterable<TaobaoOrder> orders) => db.transaction(() async {
  for (final o in orders) {
    if (o.lines.isEmpty) continue;
    final key = 'taobao:${o.id}';
    await (db.delete(db.purchaseItems)..where((i) => i.captureExternalId.equals(key))).go();
    await db.batch((b) {
      for (final (n, l) in o.lines.indexed) {
        b.insert(
          db.purchaseItems,
          PurchaseItemsCompanion.insert(
            captureExternalId: key,
            position: n,
            title: l.title,
            qty: Value(l.qty),
            price: Value(l.priceFen),
            currency: const Value('CNY'),
            sku: Value(l.sku),
            imageUrl: Value(l.imageUrl),
            url: Value(l.url),
          ),
        );
      }
    });
  }
});

/// 「¥68.90」「68.9」→ 6890
int? _fen(String s) {
  final n = s.replaceAll(RegExp(r'[^0-9.]'), '');
  return n.isEmpty ? null : parseMinor(n);
}

DateTime? _excelTime(String s) {
  final v = double.tryParse(s);
  return v == null || v < 30000 ? null : excelSerialToDate(v);
}

/// 「2026-09-30 21:05:11」（中國時間，同香港一樣）
DateTime? _parseTime(String s) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(s.trim());
  if (m == null) return null;
  int n(int g) => int.parse(m.group(g) ?? '0');
  return DateTime(n(1), n(2), n(3), n(4), n(5), n(6));
}

/// 轉做待確認嘅捕捉，金額換做港幣：有 [daily] 就用訂單當日匯率，冇就用 [rate]（1 人民幣 = 幾多港幣）。
/// [since] 之前嘅略過。
List<(RawCapture, ParsedPayment)> taobaoToCaptures(
  List<TaobaoOrder> orders, {
  required double rate,
  DailyRates? daily,
  DateTime? since,
}) {
  String rmb(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';
  return [
    for (final o in orders)
      if (since == null || !o.at.isBefore(since))
        if (daily?.on(o.at) ?? rate case final r)
          (
            RawCapture(
              source: EntrySource.import,
              sourceKey: taobaoSourceKey,
              sourceLabel: '淘寶',
              externalId: 'taobao:${o.id}',
              title: o.shop.isEmpty ? '淘寶訂單' : o.shop,
              body: [
                if (o.items.isNotEmpty) o.items.join('、'),
                '${rmb(o.paidFen)} × ${r.toStringAsFixed(4)}',
              ].join('\n'),
              occurredAt: o.at,
            ),
            ParsedPayment(
              amount: (o.paidFen * r).round(),
              merchant: o.shop.isEmpty ? '淘寶' : o.shop,
              categoryHint: taobaoCategoryPath,
            ),
          ),
  ];
}

/// 每日人民幣兌港幣匯率。冇嗰日（例如假期）就用之前最近一日；比最早一日仲早就用最早一日。
class DailyRates {
  DailyRates(Map<DateTime, double> rates)
    : _days = (rates.keys.map(_day).toList()..sort()),
      _rates = {for (final MapEntry(:key, :value) in rates.entries) _day(key): value};

  final List<DateTime> _days;
  final Map<DateTime, double> _rates;

  bool get isEmpty => _days.isEmpty;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// [at] 嗰日嘅匯率；一個都冇就返回 null。
  double? on(DateTime at) {
    if (_days.isEmpty) return null;
    final day = _day(at);
    // 搵最後一個唔遲過 [day] 嘅日子
    var lo = 0, hi = _days.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_days[mid].isAfter(day)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return _rates[_days[lo == 0 ? 0 : lo - 1]];
  }
}

/// 人民幣兌港幣匯率（1 人民幣 = 幾多港幣）。攞唔到返回 null。
Future<double?> fetchCnyToHkd({HttpClient? client, Uri? url}) async {
  final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 8));
  try {
    final req = await http.getUrl(url ?? Uri.parse('https://open.er-api.com/v6/latest/CNY'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    final rates = data is Map ? data['rates'] : null;
    final rate = rates is Map ? rates['HKD'] : null;
    // 合理範圍先用，避免壞資料
    return rate is num && rate > 0.8 && rate < 1.5 ? rate.toDouble() : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) http.close(force: true);
  }
}

/// 由 [from] 到 [to] 每日嘅人民幣兌港幣匯率（歐洲央行公佈，經 frankfurter.dev），只傳日子同幣種。
/// 每年問一次；全部攞唔到返回 null，攞到部分就用部分。
Future<DailyRates?> fetchCnyHkdHistory(DateTime from, DateTime to, {HttpClient? client, Uri? base}) async {
  final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 8));
  final api = base ?? Uri.parse('https://api.frankfurter.dev/v1/');
  String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final rates = <DateTime, double>{};
  try {
    // 早幾日開始，令頭一張單之前都有個交易日
    for (var start = from.subtract(const Duration(days: 7)); !start.isAfter(to);) {
      final end = DateTime(start.year, 12, 31).isAfter(to) ? to : DateTime(start.year, 12, 31);
      final url = api.resolve('${ymd(start)}..${ymd(end)}').replace(queryParameters: {'base': 'CNY', 'symbols': 'HKD'});
      final req = await http.getUrl(url);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(await res.transform(utf8.decoder).join());
        final byDay = data is Map ? data['rates'] : null;
        if (byDay is Map) {
          for (final MapEntry(:key, :value) in byDay.entries) {
            final day = DateTime.tryParse('$key');
            final rate = value is Map ? value['HKD'] : null;
            if (day != null && rate is num && rate > 0.8 && rate < 1.5) rates[day] = rate.toDouble();
          }
        }
      } else {
        await res.drain<void>();
      }
      start = DateTime(end.year + 1);
    }
  } catch (_) {
    // 用住攞到嘅
  } finally {
    if (client == null) http.close(force: true);
  }
  return rates.isEmpty ? null : DailyRates(rates);
}

/// 舊版將淘寶訂單入咗「購物」：開「購物 › 淘寶」，將淘寶匯入嘅記錄、待確認同店舖規則由「購物」搬過去。
/// 用戶自己揀咗其他分類嘅唔郁。冇「購物」或者冇淘寶記錄就乜都唔做。
Future<void> moveTaobaoToOwnCategory(AppDatabase db) => db.transaction(() async {
  final expense = await (db.select(db.accounts)..where((a) => a.type.equalsValue(AccountType.expense))).get();
  final shopping = expense.where((a) => a.parentId == null && a.name == '購物' && a.deletedAt == null).firstOrNull;
  if (shopping == null) return;
  final captures = await (db.select(db.captures)..where((c) => c.sourceKey.equals(taobaoSourceKey))).get();
  var taobao = expense.where((a) => a.parentId == shopping.id && a.name == '淘寶' && a.deletedAt == null).firstOrNull?.id;
  if (taobao == null) {
    if (captures.isEmpty) return;
    final last = expense
        .where((a) => a.parentId == shopping.id)
        .map((a) => a.sortOrder)
        .fold(-1, (a, b) => a > b ? a : b);
    taobao = newId();
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: Value(taobao),
            name: '淘寶',
            type: AccountType.expense,
            parentId: Value(shopping.id),
            icon: const Value('shopping'),
            color: Value(shopping.color),
            sortOrder: Value(last + 1),
          ),
        );
  }
  final merchants = <String>{};
  for (final c in captures) {
    if (c.categoryId != shopping.id) continue;
    if (c.entryId case final entryId?) {
      await (db.update(db.postings)..where((p) => p.entryId.equals(entryId) & p.accountId.equals(shopping.id))).write(
        PostingsCompanion(accountId: Value(taobao)),
      );
    }
    await (db.update(db.captures)..where((x) => x.id.equals(c.id))).write(CapturesCompanion(categoryId: Value(taobao)));
    if (c.merchant case final m?) merchants.add('m:${merchantKey(m)}');
  }
  if (merchants.isNotEmpty) {
    await (db.update(db.captureRules)..where((r) => r.key.isIn(merchants) & r.categoryId.equals(shopping.id))).write(
      CaptureRulesCompanion(categoryId: Value(taobao)),
    );
  }
});
