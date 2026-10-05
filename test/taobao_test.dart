import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/domain/capture/taobao.dart';

/// 砌一個同淘寶「导出订单」一樣格式嘅 .xlsx（t="str" 嘅儲存格），內容係假資料。
List<int> xlsx(List<List<String?>> rows) {
  String col(int i) => String.fromCharCode(65 + i);
  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null) continue; // 淘寶嘅續行會漏咗啲儲存格
      sheet.write('<c r="${col(c)}${r + 1}" t="str"><v>${const HtmlEscape().convert(v)}</v></c>');
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  final archive = Archive()..addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheet.toString())));
  return ZipEncoder().encodeBytes(archive);
}

const header = ['订单号', '订单提交时间', '订单状态', '店铺名称', '商品名称', '商品链接', '型号款式', '商品数量', '商品金额', '实付金额', '运费'];

void main() {
  final file = xlsx([
    header,
    [
      '1000000000000000001',
      '2026-10-05 20:39:23',
      '买家已付款',
      '甲小店',
      '斜挎包',
      'https://x',
      '黑色',
      '1',
      '￥26.80',
      '￥26.80',
      '￥0.00',
    ],
    [
      '1000000000000000002',
      '2026-09-22 14:03:55',
      '卖家已发货',
      '乙旗舰店',
      '折叠伞',
      'https://x',
      '藍',
      '1',
      '￥186.28',
      '￥194.28',
      '￥8.00',
    ],
    [
      '1000000000000000003',
      '2026-09-01 21:00:00',
      '交易成功',
      '丙宠物店',
      '尿垫 S',
      'https://x',
      'S',
      '2',
      '￥19.54',
      '￥83.68',
      '￥0.00',
    ],
    [null, null, null, null, '尿垫 M', 'https://x', 'M', '2', '￥22.30'],
    [
      '1000000000000000004',
      '2026-08-31 17:00:00',
      '交易关闭',
      '丁店',
      '炉头支架',
      'https://x',
      '-',
      '1',
      '￥14.86',
      '￥14.86',
      '￥0.00',
    ],
  ]);

  test('reads orders, merges extra item rows and keeps shipping in the paid amount', () {
    final orders = parseTaobaoXlsx(file);
    expect(orders.map((o) => o.id), [
      '1000000000000000001',
      '1000000000000000002',
      '1000000000000000003',
      '1000000000000000004',
    ]);
    expect(orders[1].paidFen, 19428);
    expect(orders[1].at, DateTime(2026, 9, 22, 14, 3, 55));
    expect(orders[2].items, ['尿垫 S', '尿垫 M']);
    expect(orders[3].isClosed, isTrue);
  });

  test('converts RMB to HKD, skips closed orders and older ones', () {
    final orders = parseTaobaoXlsx(file);
    final all = taobaoToCaptures(orders, cnyToHkd: 1.09);
    expect(all, hasLength(3));
    final (raw, payment) = all[1];
    expect(raw.externalId, 'taobao:1000000000000000002');
    expect(raw.sourceKey, taobaoSourceKey);
    expect(payment.amount, 21177); // ￥194.28 × 1.09 = HK$211.77
    expect(payment.currency, 'HKD');
    expect(payment.merchant, '淘寶 · 乙旗舰店');
    expect(raw.body, contains('實付 ￥194.28'));

    final recent = taobaoToCaptures(orders, cnyToHkd: 1.09, since: DateTime(2026, 9, 10));
    expect(recent.map((c) => c.$1.externalId), ['taobao:1000000000000000001', 'taobao:1000000000000000002']);
  });

  test('rejects files that are not a Taobao order export', () {
    expect(() => parseTaobaoXlsx(utf8.encode('not a zip')), throwsA(isA<TaobaoException>()));
    expect(
      () => parseTaobaoXlsx(
        xlsx([
          ['a', 'b'],
          ['1', '2'],
        ]),
      ),
      throwsA(isA<TaobaoException>()),
    );
  });

  test('parses yuan strings', () {
    expect(parseYuanToFen('￥1,234.50'), 123450);
    expect(parseYuanToFen('¥0.56'), 56);
    expect(parseYuanToFen(''), isNull);
  });
}
