import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';

const backupDbName = 'money_manager.sqlite';

/// 將資料庫同收據相打包成 zip，返回 zip 路徑。
Future<String> exportBackup(AppDatabase db, {required String attachmentsDir, required String tempDir}) async {
  final work = await Directory(p.join(tempDir, 'backup_${DateTime.now().millisecondsSinceEpoch}'))
      .create(recursive: true);
  final dbCopy = p.join(work.path, backupDbName);
  // VACUUM INTO 喺資料庫開住嘅情況下都可以出一個一致嘅副本
  await db.customStatement('VACUUM INTO ?', [dbCopy]);

  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final zipPath = p.join(
    tempDir,
    '記錄課金備份_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.zip',
  );
  final encoder = ZipFileEncoder()..create(zipPath);
  await encoder.addFile(File(dbCopy), backupDbName);
  final atts = Directory(attachmentsDir);
  if (await atts.exists()) {
    await encoder.addDirectory(atts, includeDirName: true);
  }
  await encoder.close();
  await work.delete(recursive: true);
  return zipPath;
}

/// 解壓備份去暫存目錄並檢查內容。返回解壓目錄。
Future<String> unpackBackup(String zipPath, {required String tempDir}) async {
  final out = p.join(tempDir, 'restore_${DateTime.now().millisecondsSinceEpoch}');
  await extractFileToDisk(zipPath, out);
  if (!await File(p.join(out, backupDbName)).exists()) {
    await Directory(out).delete(recursive: true);
    throw const FormatException('呢個唔係記錄課金嘅備份檔');
  }
  return out;
}

/// 用解壓咗嘅備份覆蓋現有數據。呼叫之前資料庫一定要已經關閉。
Future<void> applyBackup(String unpackedDir, {required String databasePath, required String attachmentsDir}) async {
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$databasePath$suffix');
    if (await f.exists()) await f.delete();
  }
  await File(p.join(unpackedDir, backupDbName)).copy(databasePath);

  final atts = Directory(attachmentsDir);
  if (await atts.exists()) await atts.delete(recursive: true);
  await atts.create(recursive: true);
  final restored = Directory(p.join(unpackedDir, 'attachments'));
  if (await restored.exists()) {
    await for (final f in restored.list()) {
      if (f is File) await f.copy(p.join(attachmentsDir, p.basename(f.path)));
    }
  }
  await Directory(unpackedDir).delete(recursive: true);
}
