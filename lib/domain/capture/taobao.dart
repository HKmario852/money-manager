import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../data/database.dart';
import 'capture_service.dart';
import 'parser.dart';

/// 淘寶「已買到的寶貝 › 导出订单」匯入嘅來源 key。付款方法 Excel 冇寫，所以全部用同一個 key，
/// 用戶揀一次賬戶（例如 AlipayHK）之後會記住。
const taobaoSourceKey = 'taobao-export';

/// 未設定過嘅時候用嘅人民幣兌港幣匯率。
const defaultCnyToHkd = 1.09;

class TaobaoException implements Exception {
  const TaobaoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 淘寶匯出 Excel 入面嘅一張訂單（同一張單幾件貨會併埋）。
class TaobaoOrder {
  const TaobaoOrder({
    required this.id,
    required this.at,
    required this.status,
    required this.shop,
    required this.items,
    required this.paidFen,
  });

  /// 订单号
  final String id;

  /// 订单提交时间（淘寶用北京時間，同香港一樣 UTC+8）
  final DateTime at;
  final String status;
  final String shop;
  final List<String> items;

  /// 实付金额，人民幣分（包運費）
  final int paidFen;

  /// 交易关闭 = 取消 / 全數退款，唔當消費
  bool get isClosed => status.contains('关闭') || status.contains('關閉');
}

/// 讀淘寶「导出订单」嘅 .xlsx。欄位靠表頭名認，唔靠次序。
Future<List<TaobaoOrder>> readTaobaoExport(String path) async {
  try {
    return parseTaobaoXlsx(await File(path).readAsBytes());
  } on TaobaoException {
    rethrow;
  } on Exception catch (e) {
    throw TaobaoException('讀唔到個 Excel：$e');
  }
}

List<TaobaoOrder> parseTaobaoXlsx(List<int> bytes) {
  final rows = readXlsxRows(bytes);
  if (rows.isEmpty) throw const TaobaoException('個 Excel 係空嘅');
  final header = rows.first;
  int col(String name) => header.indexWhere((h) => h.trim() == name);
  final iId = col('订单号'), iTime = col('订单提交时间'), iStatus = col('订单状态');
  final iShop = col('店铺名称'), iItem = col('商品名称'), iPaid = col('实付金额');
  if ([iId, iTime, iPaid, iItem].contains(-1)) {
    throw const TaobaoException('呢個唔係淘寶「导出订单」嘅 Excel（搵唔到订单号 / 实付金额）');
  }
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  final orders = <TaobaoOrder>[];
  for (final r in rows.skip(1)) {
    final id = cell(r, iId);
    final item = cell(r, iItem);
    if (id.isEmpty) {
      // 同一張單嘅第二件貨：淨係有商品資料，冇單號同實付
      if (orders.isNotEmpty && item.isNotEmpty) orders.last.items.add(item);
      continue;
    }
    final at = DateTime.tryParse(cell(r, iTime).replaceFirst(' ', 'T'));
    final paid = parseYuanToFen(cell(r, iPaid));
    if (at == null || paid == null) continue;
    orders.add(
      TaobaoOrder(
        id: id,
        at: at,
        status: cell(r, iStatus),
        shop: cell(r, iShop),
        items: [if (item.isNotEmpty) item],
        paidFen: paid,
      ),
    );
  }
  return orders;
}

/// 「￥194.28」、「¥1,234.5」→ 分。
int? parseYuanToFen(String s) {
  final m = RegExp(r'[0-9][0-9,]*(?:\.[0-9]+)?').firstMatch(s);
  final v = m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', ''));
  return v == null ? null : (v * 100).round();
}

/// 最簡單嘅 .xlsx 讀法：第一張工作表，每行一個 List（按欄位字母排好，空格補 ''）。
List<List<String>> readXlsxRows(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const TaobaoException('呢個唔係 Excel (.xlsx) 檔案');
  }
  String? text(String name) {
    final f = zip.findFile(name);
    final content = f?.readBytes();
    return content == null ? null : utf8.decode(content, allowMalformed: true);
  }

  final shared = <String>[];
  final sharedXml = text('xl/sharedStrings.xml');
  if (sharedXml != null) {
    for (final si in XmlDocument.parse(sharedXml).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final sheetName = zip.files
      .map((f) => f.name)
      .where((n) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(n))
      .fold<String?>(null, (best, n) => best == null || n.compareTo(best) < 0 ? n : best);
  final sheetXml = sheetName == null ? null : text(sheetName);
  if (sheetXml == null) throw const TaobaoException('Excel 入面冇工作表');

  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
    final cells = <int, String>{};
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final index = ref == null ? next : _columnIndex(ref);
      next = index + 1;
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText;
      cells[index] = switch (type) {
        's' => v == null ? '' : shared[int.parse(v)],
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        _ => v ?? '',
      };
    }
    final width = cells.isEmpty ? 0 : cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
  }
  return rows;
}

int _columnIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// 轉做待確認嘅捕捉。人民幣按 [cnyToHkd] 換做港幣（AlipayHK 實際扣數會有少少出入）。
/// 交易关闭 嘅略過；[since] 之前嘅略過。
List<(RawCapture, ParsedPayment)> taobaoToCaptures(
  List<TaobaoOrder> orders, {
  required double cnyToHkd,
  DateTime? since,
}) => [
  for (final o in orders)
    if (!o.isClosed && o.paidFen > 0 && (since == null || !o.at.isBefore(since)))
      (
        RawCapture(
          source: EntrySource.import,
          sourceKey: taobaoSourceKey,
          sourceLabel: '淘寶',
          externalId: 'taobao:${o.id}',
          title: o.shop.isEmpty ? '淘寶訂單' : o.shop,
          body: '${o.items.join('、')}\n實付 ￥${(o.paidFen / 100).toStringAsFixed(2)} · 訂單 ${o.id}',
          occurredAt: o.at,
        ),
        ParsedPayment(
          amount: (o.paidFen * cnyToHkd).round(),
          merchant: o.shop.isEmpty ? '淘寶' : '淘寶 · ${o.shop}',
          categoryHint: '購物',
        ),
      ),
];
