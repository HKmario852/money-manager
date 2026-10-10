import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/data/database_key.dart';
import 'package:money_manager/data/encryption.dart';
import 'package:money_manager/domain/backup.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('mm-enc');
    path = '${dir.path}/money_manager.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// 舊版 App 留低嘅明文資料庫，入面有一個賬戶
  Future<void> plaintextDatabase() async {
    final db = AppDatabase(NativeDatabase(File(path)));
    await db.into(db.accounts).insert(AccountsCompanion.insert(name: '測試銀行', type: AccountType.asset, subtype: const Value(AccountSubtype.bank)));
    await db.close();
  }

  AppDatabase openEncrypted(String key) => AppDatabase(NativeDatabase(File(path), setup: (raw) => applyDatabaseKey(raw, key)));

  test('新金鑰係 32 byte hex，每次唔同', () {
    final a = newDatabaseKey();
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(newDatabaseKey(), isNot(a));
  });

  test('明文資料庫就地加密，數據保留，冇金鑰開唔到', () async {
    await plaintextDatabase();
    expect(isPlaintextDatabase(path), isTrue);
    final key = newDatabaseKey();

    expect(encryptIfPlaintext(path, key), isTrue);
    expect(isPlaintextDatabase(path), isFalse);
    expect(File('$path.pre-encrypt').existsSync(), isFalse); // 明文副本已清走
    expect(encryptIfPlaintext(path, key), isFalse); // 已加密就唔使再做

    final db = openEncrypted(key);
    final names = (await db.select(db.accounts).get()).map((a) => a.name);
    expect(names, contains('測試銀行'));
    await db.close();

    // 冇金鑰或者金鑰唔啱都開唔到
    for (final setup in <void Function(sql.Database)?>[null, (raw) => applyDatabaseKey(raw, newDatabaseKey())]) {
      final raw = sql.sqlite3.open(path);
      setup?.call(raw);
      expect(() => raw.select('SELECT count(*) FROM accounts'), throwsA(isA<sql.SqliteException>()));
      raw.close();
    }
  });

  test('新資料庫一開始就加密', () async {
    final key = newDatabaseKey();
    final db = openEncrypted(key);
    await db.select(db.accounts).get(); // 建表同種子數據
    await db.close();
    expect(isPlaintextDatabase(path), isFalse);
  });

  test('匯出嘅備份係明文，可以喺另一部手機還原；還原後再加密', () async {
    await plaintextDatabase();
    final key = newDatabaseKey();
    encryptIfPlaintext(path, key);
    final db = openEncrypted(key);
    final atts = Directory('${dir.path}/attachments')..createSync();
    final tmp = Directory('${dir.path}/tmp')..createSync();

    final zip = await exportBackup(db, attachmentsDir: atts.path, tempDir: tmp.path, password: 'pw', databaseKey: key);
    await db.close();
    final unpacked = await unpackBackup(zip, tempDir: tmp.path, maxSchemaVersion: 4, password: 'pw');
    final restoredFile = '$unpacked/$backupDbName';
    expect(isPlaintextDatabase(restoredFile), isTrue);

    await applyBackup(unpacked, databasePath: path, attachmentsDir: atts.path);
    expect(isPlaintextDatabase(path), isTrue);
    final newKey = newDatabaseKey(); // 新手機有自己嘅金鑰
    expect(encryptIfPlaintext(path, newKey), isTrue);
    final reopened = openEncrypted(newKey);
    expect((await reopened.select(reopened.accounts).get()).map((a) => a.name), contains('測試銀行'));
    await reopened.close();
  });

  test('唔啱嘅金鑰格式唔會用', () {
    final raw = sql.sqlite3.openInMemory();
    expect(() => applyDatabaseKey(raw, "x'; DROP TABLE accounts; --"), throwsArgumentError);
    raw.close();
  });

  group('開 App 攞金鑰', () {
    String? stored;
    Future<DatabaseKeyResult> load({bool failRead = false, bool dropWrites = false}) => loadDatabaseKey(
      databasePath: path,
      read: () async => failRead ? throw StateError('keystore') : stored,
      write: (key) async => dropWrites ? null : stored = key,
    );
    setUp(() => stored = null);

    test('新安裝：整一條新金鑰並存低', () async {
      final result = await load();
      expect(result, isA<DatabaseKeyReady>());
      expect((result as DatabaseKeyReady).key, stored);
    });

    test('已有金鑰就用返', () async {
      stored = newDatabaseKey();
      expect((await load() as DatabaseKeyReady).key, stored);
    });

    test('由舊版升級（明文資料庫、未有金鑰）：整新金鑰', () async {
      await plaintextDatabase();
      expect(await load(), isA<DatabaseKeyReady>());
    });

    test('已加密但金鑰唔見咗：唔整新金鑰，交俾用戶揀', () async {
      await plaintextDatabase();
      encryptIfPlaintext(path, newDatabaseKey());
      expect(await load(), isA<DatabaseKeyMissing>());
      expect(stored, isNull);

      final aside = setAsideUnreadableDatabase(path);
      expect(File(path).existsSync(), isFalse);
      expect(File(aside).existsSync(), isTrue); // 改名留低，冇刪除
      expect(await load(), isA<DatabaseKeyReady>());
    });

    test('讀唔到或者存唔到 secure storage：唔開 App', () async {
      expect(await load(failRead: true), isA<DatabaseKeyUnavailable>());
      expect(await load(dropWrites: true), isA<DatabaseKeyUnavailable>());
    });
  });
}
