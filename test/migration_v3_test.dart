import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';

void main() {
  test('由第 2 版升級：開「購物 › 淘寶」、搬淘寶記錄、加訂單商品表', () async {
    final dir = Directory.systemTemp.createTempSync('mm');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // 第 2 版：冇「淘寶」子分類，有一筆入咗「購物」嘅淘寶待確認
    var db = AppDatabase(NativeDatabase(file));
    final all = await db.select(db.accounts).get();
    final shopping = all.firstWhere((a) => a.name == '購物' && a.parentId == null).id;
    await (db.delete(db.accounts)..where((a) => a.name.equals('淘寶'))).go();
    await db
        .into(db.captures)
        .insert(
          CapturesCompanion.insert(
            source: EntrySource.import,
            sourceKey: 'taobao',
            externalId: 'taobao:1',
            body: 'x',
            occurredAt: DateTime(2020),
            categoryId: Value(shopping),
          ),
        );
    await db.customStatement('DROP TABLE purchase_items'); // 第 4 版先有
    await db.customStatement('PRAGMA user_version = 2');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final taobao = (await (db.select(db.accounts)..where((a) => a.name.equals('淘寶'))).get()).single;
    expect(taobao.parentId, shopping);
    expect((await db.select(db.captures).getSingle()).categoryId, taobao.id);
    expect(await db.select(db.purchaseItems).get(), isEmpty); // 第 4 版加嘅表
  });
}
