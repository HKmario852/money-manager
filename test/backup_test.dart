import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/backup.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory tmp;
  late Directory atts;

  setUp(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await db.setSetting(SettingKeys.onboarded, 'true');
    tmp = Directory.systemTemp.createTempSync('mm_backup');
    atts = Directory(p.join(tmp.path, 'attachments'))..createSync();
    File(p.join(atts.path, 'receipt.jpg')).writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<String> export({String? password}) =>
      exportBackup(db, attachmentsDir: atts.path, tempDir: tmp.path, password: password);

  test('冇密碼嘅備份可以解壓同通過檢查', () async {
    final zip = await export();
    expect(await isEncryptedBackup(zip), isFalse);
    final out = await unpackBackup(zip, tempDir: tmp.path, maxSchemaVersion: db.schemaVersion);
    expect(File(p.join(out, backupDbName)).existsSync(), isTrue);
    expect(File(p.join(out, 'attachments', 'receipt.jpg')).existsSync(), isTrue);
  });

  test('有密碼嘅備份要啱密碼先解到', () async {
    final zip = await export(password: 'secret');
    expect(await isEncryptedBackup(zip), isTrue);
    await expectLater(
      unpackBackup(zip, tempDir: tmp.path, maxSchemaVersion: db.schemaVersion, password: 'wrong'),
      throwsA(isA<BackupException>()),
    );
    final out = await unpackBackup(zip, tempDir: tmp.path, maxSchemaVersion: db.schemaVersion, password: 'secret');
    expect(File(p.join(out, backupDbName)).existsSync(), isTrue);
  });

  test('再匯出會清走舊嘅暫存備份', () async {
    final first = await export();
    File(first).renameSync(p.join(tmp.path, 'MoneyExpense_backup_old.zip'));
    await export();
    expect(File(p.join(tmp.path, 'MoneyExpense_backup_old.zip')).existsSync(), isFalse);
  });

  test('假資料庫或者新版本備份會被拒絕', () async {
    final fake = p.join(tmp.path, 'fake.zip');
    final garbage = File(p.join(tmp.path, backupDbName))..writeAsStringSync('not a database');
    final encoder = ZipFileEncoder()..create(fake);
    await encoder.addFile(garbage, backupDbName);
    await encoder.close();
    await expectLater(
      unpackBackup(fake, tempDir: tmp.path, maxSchemaVersion: db.schemaVersion),
      throwsA(isA<BackupException>()),
    );

    final zip = await export();
    await expectLater(unpackBackup(zip, tempDir: tmp.path, maxSchemaVersion: 0), throwsA(isA<BackupException>()));
    expect(tmp.listSync().where((e) => p.basename(e.path).startsWith('restore_')), isEmpty);
  });

  test('還原會將舊數據留做 pre-restore', () async {
    final zip = await export();
    final out = await unpackBackup(zip, tempDir: tmp.path, maxSchemaVersion: db.schemaVersion);
    final dbPath = p.join(tmp.path, 'live.sqlite');
    File(dbPath).writeAsStringSync('old data');
    final liveAtts = Directory(p.join(tmp.path, 'live_attachments'))..createSync();
    File(p.join(liveAtts.path, 'old.jpg')).writeAsBytesSync([9]);

    await applyBackup(out, databasePath: dbPath, attachmentsDir: liveAtts.path);

    expect(File('$dbPath.pre-restore').readAsStringSync(), 'old data');
    expect(File(p.join('${liveAtts.path}.pre-restore', 'old.jpg')).existsSync(), isTrue);
    expect(File(p.join(liveAtts.path, 'receipt.jpg')).existsSync(), isTrue);
    expect(Directory(out).existsSync(), isFalse);
  });
}
