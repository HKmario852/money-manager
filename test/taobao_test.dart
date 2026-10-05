import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/capture/capture_service.dart';
import 'package:money_manager/domain/capture/taobao.dart';
import 'package:money_manager/domain/ledger.dart';
import 'package:money_manager/domain/xlsx.dart';

// 假資料，唔係真訂單
final export = jsonEncode({
  'format': 'money-expense-taobao',
  'version': 1,
  'exportedAt': '2026-10-05T16:00:00.000Z',
  'orders': [
    {
      'id': '3001',
      'time': '2026-10-02 21:05:11',
      'shop': '測試小店',
      'items': [
        {'title': '手機殼', 'qty': 2, 'price': '29.45'},
        {'title': '數據線', 'qty': 1, 'price': '10.00'},
      ],
      'paid': '68.90',
      'status': '交易成功',
    },
    {'id': '3002', 'time': '2026-10-03 10:00:00', 'shop': '另一間', 'items': [], 'paid': '20.00', 'status': '等待买家付款'},
    {'id': '3003', 'time': '2026-10-03 11:00:00', 'shop': '另一間', 'items': [], 'paid': '15.00', 'status': '交易关闭'},
    {'id': '3004', 'time': '2026-10-03 12:00:00', 'shop': '另一間', 'items': [], 'paid': '9.00', 'status': '退款成功'},
    {'id': '3005', 'time': '2025-01-01 09:00:00', 'shop': '舊店', 'items': [], 'paid': '5.00', 'status': '交易成功'},
    {'id': '3006', 'time': 'bad', 'shop': 'x', 'items': [], 'paid': '1.00', 'status': '交易成功'},
  ],
});

void main() {
  test('讀匯出檔：未付款、關閉、退款同壞資料略過', () {
    final orders = parseTaobaoExport(export)!;
    expect(orders.map((o) => o.id), ['3001', '3005']);
    final o = orders.first;
    expect(o.at, DateTime(2026, 10, 2, 21, 5, 11));
    expect(o.shop, '測試小店');
    expect(o.items, ['手機殼 ×2', '數據線']);
    expect(o.paidFen, 6890);
  });

  test('唔係匯出檔返回 null', () {
    expect(parseTaobaoExport('[]'), isNull);
    expect(parseTaobaoExport('{"format":"other","orders":[]}'), isNull);
    expect(parseTaobaoExport('not json'), isNull);
  });

  test('人民幣換港幣，訂單號做 id', () {
    final items = taobaoToCaptures(parseTaobaoExport(export)!, rate: 1.0850, since: DateTime(2026));
    expect(items, hasLength(1));
    final (raw, payment) = items.single;
    expect(raw.externalId, 'taobao:3001');
    expect(raw.sourceKey, taobaoSourceKey);
    expect(raw.body, contains('手機殼 ×2、數據線'));
    expect(raw.body, contains('¥68.90 × 1.0850'));
    expect(payment.amount, 7476); // 68.90 × 1.085 = 74.7565
    expect(payment.currency, 'HKD');
    expect(payment.merchant, '測試小店');
    expect(payment.categoryHint, '購物');
  });

  group('當日匯率', () {
    final daily = DailyRates({DateTime(2017, 3, 17): 1.12, DateTime(2017, 3, 20): 1.13, DateTime(2026, 10, 2): 1.17});

    test('冇嗰日就用之前最近一日；太早用最早一日', () {
      expect(daily.on(DateTime(2017, 3, 20, 23, 59)), 1.13);
      expect(daily.on(DateTime(2017, 3, 19)), 1.12); // 星期日
      expect(daily.on(DateTime(2017, 1, 1)), 1.12);
      expect(daily.on(DateTime(2026, 10, 5)), 1.17);
      expect(DailyRates({}).on(DateTime(2026)), isNull);
    });

    test('每張單用自己嗰日嘅匯率', () {
      final items = taobaoToCaptures(parseTaobaoExport(export)!, rate: 1.5, daily: daily);
      expect(items.map((i) => i.$2.amount), [8061, 565]); // 68.90 × 1.17、5.00 × 1.13
      expect(items.first.$1.body, contains('¥68.90 × 1.1700'));
    });

    test('攞歷史匯率：逐年問，壞數略過', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asked = <String>[];
      server.listen((req) async {
        asked.add('${req.uri.pathSegments.last}?${req.uri.query}');
        final year = req.uri.pathSegments.last.substring(0, 4);
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'base': 'CNY',
              'rates': {
                '$year-06-01': {'HKD': year == '2025' ? 1.09 : 1.15},
                '$year-06-02': {'HKD': 9.9},
              },
            }),
          );
        await req.response.close();
      });
      final rates = await fetchCnyHkdHistory(
        DateTime(2024, 3, 20),
        DateTime(2025, 10, 5),
        base: Uri.parse('http://127.0.0.1:${server.port}/v1/'),
      );
      await server.close(force: true);
      expect(asked, ['2024-03-13..2024-12-31?base=CNY&symbols=HKD', '2025-01-01..2025-10-05?base=CNY&symbols=HKD']);
      expect(rates!.on(DateTime(2024, 12, 1)), 1.15);
      expect(rates.on(DateTime(2025, 7, 1)), 1.09);
    });
  });

  group('淘寶「导出订单」Excel', () {
    const header = ['订单号', '订单提交时间', '订单状态', '店铺名称', '商品名称', '商品数量', '商品金额', '实付金额', '运费'];
    final rows = [
      ['订单数据'],
      header,
      // 兩件貨，实付金额每行寫成張單嘅數
      ['5001', '2026-10-02 21:05:11', '交易成功', '測試小店', '手機殼', '2', '29.45', '68.90', '0'],
      ['5001', '2026-10-02 21:05:11', '交易成功', '測試小店', '數據線', '1', '10.00', '68.90', '0'],
      // 兩件貨，实付金额每件唔同 = 要加埋
      ['5002', '2026-10-03 09:00:00', '卖家已发货', '文具店', '筆', '1', '5.00', '4.50', '0'],
      ['5002', '2026-10-03 09:00:00', '卖家已发货', '文具店', '簿', '1', '8.00', '7.20', '0'],
      ['5003', '2026-10-03 10:00:00', '交易关闭', '另一間', '杯', '1', '20.00', '20.00', '0'],
      ['5004', '#46298.5', '交易成功', '日期係數字', '襪', '1', '#12.5', '#12.5', '0'],
      ['1.23E+18', '2026-10-03 10:00:00', '交易成功', '壞訂單號', '帽', '1', '9.00', '9.00', '0'],
    ];

    test('同一張單合併做一筆，關閉同壞訂單號略過', () {
      final orders = parseTaobaoXlsx(readXlsxRows(makeXlsx(rows)))!;
      expect(orders.map((o) => o.id), ['5001', '5002', '5004']);
      final a = orders[0];
      expect(a.paidFen, 6890);
      expect(a.items, ['手機殼 ×2', '數據線']);
      expect(a.shop, '測試小店');
      expect(a.at, DateTime(2026, 10, 2, 21, 5, 11));
      expect(orders[1].paidFen, 1170);
      expect(orders[2].at, DateTime(2026, 10, 3, 12));
      expect(orders[2].paidFen, 1250);
    });

    test('真實排法：第二件貨嗰行冇訂單號同實付，表頭喺第一行', () {
      final real = [
        ['订单号', '订单提交时间', '订单状态', '店铺名称', '商品名称', '商品链接', '型号款式', '商品数量', '商品金额', '实付金额', '运费', '物流'],
        ['6001', '2026-10-01 20:15:03', '交易成功', '測試小店', '手機殼', 'https://x', '黑色', '1', '￥30.00', '￥45.50', '￥5.00', ''],
        ['', '', '', '', '數據線', 'https://y', '1米', '1', '￥10.50', '', '', ''],
        ['6002', '2026-10-01 21:00:00', '交易关闭', '另一間', '杯', '', '', '1', '￥20.00', '￥20.00', '', ''],
        ['', '', '', '', '碟', '', '', '1', '￥5.00', '', '', ''],
        ['6003', '2026-10-02 08:00:00', '卖家已发货', '文具店', '筆', '', '', '3', '￥6.00', '￥6.00', '', ''],
      ];
      final orders = parseTaobaoXlsx(readXlsxRows(makeXlsx(real)))!;
      expect(orders.map((o) => o.id), ['6001', '6003']);
      expect(orders[0].items, ['手機殼', '數據線']);
      expect(orders[0].paidFen, 4550);
      expect(orders[1].items, ['筆 ×3']);
      expect(orders[1].paidFen, 600);
    });

    test('唔係淘寶表返回 null；唔係 Excel 拋錯', () {
      expect(
        parseTaobaoXlsx(
          readXlsxRows(
            makeXlsx([
              ['名', '金額'],
              ['x', '1'],
            ]),
          ),
        ),
        isNull,
      );
      expect(() => readXlsxRows(utf8.encode('not a zip')), throwsFormatException);
    });
  });

  group('同其他來源去重', () {
    late AppDatabase db;
    late CaptureService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      service = CaptureService(Ledger(db));
    });

    tearDown(() => db.close());

    Future<Capture> byId(String externalId) =>
        (db.select(db.captures)..where((c) => c.externalId.equals(externalId))).getSingle();

    RawCapture alipay(DateTime at) => RawCapture(
      source: EntrySource.notification,
      sourceKey: 'hk.alipay.wallet',
      externalId: 'n:1',
      title: '付款成功',
      body: r'你已於 淘寶 付款 HK$75.12',
      occurredAt: at,
    );

    test('再匯入唔會重複', () async {
      final items = taobaoToCaptures(parseTaobaoExport(export)!, rate: 1.085);
      for (final (raw, p) in items) {
        expect(await service.ingestParsed(raw, p), IngestOutcome.added);
      }
      for (final (raw, p) in items) {
        expect(await service.ingestParsed(raw, p), IngestOutcome.alreadySeen);
      }
    });

    test('再匯入：未確認嘅改用新匯率，已確認嘅唔郁', () async {
      final orders = parseTaobaoExport(export)!;
      for (final (raw, p) in taobaoToCaptures(orders, rate: 1.0)) {
        await service.ingestParsed(raw, p);
      }
      await (db.update(db.captures)..where((c) => c.externalId.equals('taobao:3005'))).write(
        const CapturesCompanion(status: Value(CaptureStatus.confirmed)),
      );
      final again = [
        for (final (raw, p) in taobaoToCaptures(orders, rate: 1.2))
          await service.ingestParsed(raw, p, refreshPending: true),
      ];
      expect(again, [IngestOutcome.updated, IngestOutcome.alreadySeen]);
      final a = await byId('taobao:3001');
      expect(a.amount, 8268);
      expect(a.body, contains('× 1.2000'));
      expect((await byId('taobao:3005')).amount, 500);
      // 冇 refreshPending 就唔郁
      final (raw, p) = taobaoToCaptures(orders, rate: 1.3).first;
      expect(await service.ingestParsed(raw, p), IngestOutcome.alreadySeen);
      expect((await byId('taobao:3001')).amount, 8268);
    });

    test('AlipayHK 通知先到：淘寶估算金額差少少都當重複', () async {
      final (raw, p) = taobaoToCaptures(parseTaobaoExport(export)!, rate: 1.085).first;
      expect(await service.ingest(alipay(raw.occurredAt.add(const Duration(minutes: 1)))), IngestOutcome.added);
      expect(await service.ingestParsed(raw, p), IngestOutcome.duplicate);
    });

    test('淘寶先匯入：之後嘅通知有準確金額，淘寶嗰筆當重複', () async {
      final (raw, p) = taobaoToCaptures(parseTaobaoExport(export)!, rate: 1.085).first;
      expect(await service.ingestParsed(raw, p), IngestOutcome.added);
      expect(await service.ingest(alipay(raw.occurredAt.add(const Duration(minutes: 1)))), IngestOutcome.added);
      expect((await byId('taobao:3001')).status, CaptureStatus.duplicate);
      expect((await byId('n:1')).status, CaptureStatus.pending);
    });

    test('金額差太遠唔當重複', () async {
      final (raw, p) = taobaoToCaptures(parseTaobaoExport(export)!, rate: 1.2).first;
      expect(await service.ingest(alipay(raw.occurredAt)), IngestOutcome.added);
      expect(await service.ingestParsed(raw, p), IngestOutcome.added);
    });
  });
}

/// 整一個細 xlsx：字串用 sharedStrings，以「#」開頭嘅當數字格。
List<int> makeXlsx(List<List<String>> rows) {
  final strings = <String>[];
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
  final sheet = StringBuffer(
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v.isEmpty) continue;
      final ref = '${String.fromCharCode(65 + c)}${r + 1}';
      if (v.startsWith('#')) {
        sheet.write('<c r="$ref"><v>${v.substring(1)}</v></c>');
      } else {
        strings.add(v);
        sheet.write('<c r="$ref" t="s"><v>${strings.length - 1}</v></c>');
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  final sst = StringBuffer('<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  for (final s in strings) {
    sst.write('<si><t>${esc(s)}</t></si>');
  }
  sst.write('</sst>');
  final archive = Archive()
    ..addFile(ArchiveFile.string('xl/sharedStrings.xml', sst.toString()))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet.toString()));
  return ZipEncoder().encode(archive);
}
