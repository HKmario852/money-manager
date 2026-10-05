import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 讀 Excel（.xlsx）第一張工作表，每行變做一串文字。數字保持 Excel 入面嘅原始寫法（例如日期係序號）。
/// 唔係 xlsx 就拋 [FormatException]。
List<List<String>> readXlsxRows(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('唔係 Excel 檔');
  }
  String? text(String name) {
    final f = zip.findFile(name);
    final content = f?.readBytes();
    return content == null ? null : utf8.decode(content, allowMalformed: true);
  }

  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in XmlDocument.parse(sst).findAllElements('si')) {
      // 有格式嘅字會拆做幾段 <r><t>…</t></r>；拼音 <rPh> 唔要
      shared.add(
        si.findAllElements('t').where((t) => t.parentElement?.name.local != 'rPh').map((t) => t.innerText).join(),
      );
    }
  }

  final sheetName = _firstSheetPath(text) ?? 'xl/worksheets/sheet1.xml';
  final sheet = text(sheetName);
  if (sheet == null) throw const FormatException('Excel 檔入面冇工作表');

  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(sheet).findAllElements('row')) {
    final cells = <int, String>{};
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? next : _columnIndex(ref);
      next = col + 1;
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText;
      final value = switch (type) {
        's' => v == null ? '' : (shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? ''),
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        _ => v ?? '',
      };
      cells[col] = value;
    }
    if (cells.isEmpty) {
      rows.add(const []);
      continue;
    }
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
  }
  return rows;
}

/// workbook.xml 第一張 sheet 對應嘅檔案（唔一定叫 sheet1.xml）。
String? _firstSheetPath(String? Function(String) text) {
  final wb = text('xl/workbook.xml');
  final rels = text('xl/_rels/workbook.xml.rels');
  if (wb == null || rels == null) return null;
  final first = XmlDocument.parse(wb).findAllElements('sheet').firstOrNull;
  final id = first?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
  if (id == null) return null;
  for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
    if (r.getAttribute('Id') != id) continue;
    final target = r.getAttribute('Target') ?? '';
    return target.startsWith('/') ? target.substring(1) : 'xl/$target';
  }
  return null;
}

/// 「C12」→ 2
int _columnIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// Excel 日期序號（例如 46297.5）轉做 DateTime。
DateTime excelSerialToDate(double serial) {
  final ms = (serial * Duration.millisecondsPerDay).round();
  final utc = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: ms));
  // Excel 冇時區：當本地時間
  return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
}
