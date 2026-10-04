import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../data/database.dart';

const backupDbName = 'money_manager.sqlite';
const _backupPrefix = '記錄課金備份_';

/// 備份檔有問題（唔係備份、壞咗、密碼唔啱）。
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 將資料庫同收據相打包成 zip，返回 zip 路徑。[password] 唔係空就用 AES 加密。
Future<String> exportBackup(
  AppDatabase db, {
  required String attachmentsDir,
  required String tempDir,
  String? password,
}) async {
  // 清走之前匯出留低喺暫存嘅備份，唔好喺手機留多份明文副本
  await for (final f in Directory(tempDir).list()) {
    if (f is File && p.basename(f.path).startsWith(_backupPrefix)) await f.delete();
  }
  final work = await Directory(p.join(tempDir, 'backup_${DateTime.now().millisecondsSinceEpoch}'))
      .create(recursive: true);
  try {
    final dbCopy = p.join(work.path, backupDbName);
    // VACUUM INTO 喺資料庫開住嘅情況下都可以出一個一致嘅副本
    await db.customStatement('VACUUM INTO ?', [dbCopy]);

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final zipPath = p.join(
      tempDir,
      '$_backupPrefix${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.zip',
    );
    final encoder = ZipFileEncoder(password: password == null || password.isEmpty ? null : password)..create(zipPath);
    await encoder.addFile(File(dbCopy), backupDbName);
    final atts = Directory(attachmentsDir);
    if (await atts.exists()) {
      await encoder.addDirectory(atts, includeDirName: true);
    }
    await encoder.close();
    return zipPath;
  } finally {
    await work.delete(recursive: true);
  }
}

/// 睇 zip 第一個檔案有冇加密（local file header 嘅 general purpose flag bit 0）。
Future<bool> isEncryptedBackup(String zipPath) async {
  final raf = await File(zipPath).open();
  try {
    final header = await raf.read(8);
    if (header.length < 8 || header[0] != 0x50 || header[1] != 0x4b || header[2] != 0x03 || header[3] != 0x04) {
      throw const BackupException('呢個唔係記錄課金嘅備份檔');
    }
    return (header[6] & 0x1) != 0;
  } finally {
    await raf.close();
  }
}

/// 解壓備份去暫存目錄並檢查內容。返回解壓目錄。檢查唔過會清走解壓目錄並拋 [BackupException]。
Future<String> unpackBackup(
  String zipPath, {
  required String tempDir,
  required int maxSchemaVersion,
  String? password,
}) async {
  final out = p.join(tempDir, 'restore_${DateTime.now().millisecondsSinceEpoch}');
  try {
    try {
      await extractFileToDisk(zipPath, out, password: password == null || password.isEmpty ? null : password);
    } catch (_) {
      throw BackupException(password != null ? '密碼唔啱，或者備份檔壞咗' : '備份檔壞咗，開唔到');
    }
    final dbFile = File(p.join(out, backupDbName));
    if (!await dbFile.exists()) throw const BackupException('呢個唔係記錄課金嘅備份檔');
    validateBackupDatabase(dbFile.path, maxSchemaVersion: maxSchemaVersion);
    return out;
  } catch (_) {
    final dir = Directory(out);
    if (await dir.exists()) await dir.delete(recursive: true);
    rethrow;
  }
}

/// 確認係完整、版本唔高過呢個 App 嘅記錄課金資料庫。
void validateBackupDatabase(String path, {required int maxSchemaVersion}) {
  final sql.Database db;
  try {
    db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  } catch (_) {
    throw const BackupException('備份入面嘅資料庫開唔到');
  }
  try {
    final integrity = db.select('PRAGMA integrity_check').first.values.first;
    if (integrity != 'ok') throw const BackupException('備份入面嘅資料庫壞咗');
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((r) => r['name'] as String)
        .toSet();
    const required = {'accounts', 'journal_entries', 'postings', 'settings'};
    if (!tables.containsAll(required)) throw const BackupException('呢個唔係記錄課金嘅備份檔');
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > maxSchemaVersion) throw const BackupException('呢個備份係新版 App 整嘅，請先更新 App');
  } on BackupException {
    rethrow;
  } catch (_) {
    throw const BackupException('備份入面嘅資料庫壞咗');
  } finally {
    db.close();
  }
}

/// 用解壓咗嘅備份覆蓋現有數據。呼叫之前資料庫一定要已經關閉。
/// 舊數據會改名做 *.pre-restore 留低一份；中途出錯會還原返舊數據。
Future<void> applyBackup(String unpackedDir, {required String databasePath, required String attachmentsDir}) async {
  const keep = '.pre-restore';
  const suffixes = ['', '-wal', '-shm', '-journal'];
  final oldAtts = Directory('$attachmentsDir$keep');

  // 清走上一次還原留低嘅舊副本，再將而家嘅數據搬去做新副本
  for (final s in suffixes) {
    final f = File('$databasePath$keep$s');
    if (await f.exists()) await f.delete();
  }
  if (await oldAtts.exists()) await oldAtts.delete(recursive: true);
  final moved = <(String, String)>[];
  for (final s in suffixes) {
    final f = File('$databasePath$s');
    if (await f.exists()) {
      await f.rename('$databasePath$keep$s');
      moved.add(('$databasePath$s', '$databasePath$keep$s'));
    }
  }
  final atts = Directory(attachmentsDir);
  final hadAtts = await atts.exists();
  if (hadAtts) await atts.rename(oldAtts.path);

  try {
    await File(p.join(unpackedDir, backupDbName)).copy(databasePath);
    await atts.create(recursive: true);
    final restored = Directory(p.join(unpackedDir, 'attachments'));
    if (await restored.exists()) {
      await for (final f in restored.list()) {
        if (f is File) await f.copy(p.join(attachmentsDir, p.basename(f.path)));
      }
    }
  } catch (_) {
    // 還原返舊數據
    for (final s in suffixes) {
      final f = File('$databasePath$s');
      if (await f.exists()) await f.delete();
    }
    for (final (original, backup) in moved) {
      await File(backup).rename(original);
    }
    if (await atts.exists()) await atts.delete(recursive: true);
    if (hadAtts) await oldAtts.rename(attachmentsDir);
    rethrow;
  } finally {
    await Directory(unpackedDir).delete(recursive: true);
  }
}
