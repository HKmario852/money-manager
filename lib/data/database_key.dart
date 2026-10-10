import 'dart:io';

import 'encryption.dart';

/// 開 App 時攞資料庫金鑰嘅結果。
sealed class DatabaseKeyResult {
  const DatabaseKeyResult();
}

/// 有金鑰（舊有或者啱啱整）。
final class DatabaseKeyReady extends DatabaseKeyResult {
  const DatabaseKeyReady(this.key);
  final String key;
}

/// 資料庫已加密但金鑰唔見咗（例如清除咗 App 部分數據），開唔到。
final class DatabaseKeyMissing extends DatabaseKeyResult {
  const DatabaseKeyMissing();
}

/// 讀取 secure storage 失敗。
final class DatabaseKeyUnavailable extends DatabaseKeyResult {
  const DatabaseKeyUnavailable(this.error);
  final Object error;
}

/// 讀金鑰；冇就整一條新嘅存低。資料庫已經加密但冇金鑰就唔整新嘅（整咗都開唔到），交俾用戶決定。
Future<DatabaseKeyResult> loadDatabaseKey({
  required String databasePath,
  required Future<String?> Function() read,
  required Future<void> Function(String key) write,
}) async {
  final String? existing;
  try {
    existing = await read();
  } catch (e) {
    return DatabaseKeyUnavailable(e);
  }
  if (existing != null && existing.isNotEmpty) return DatabaseKeyReady(existing);
  final file = File(databasePath);
  if (file.existsSync() && file.lengthSync() > 0 && !isPlaintextDatabase(databasePath)) return const DatabaseKeyMissing();
  final key = newDatabaseKey();
  try {
    await write(key);
    // 確認真係存到先用，唔係下次開 App 就冇金鑰
    if (await read() != key) return DatabaseKeyUnavailable(StateError('Database key was not saved'));
  } catch (e) {
    return DatabaseKeyUnavailable(e);
  }
  return DatabaseKeyReady(key);
}

/// 「重新開始」：開唔到嘅資料庫改名留低（唔刪除），之後會用新金鑰開一個新資料庫。返回改咗嘅檔名。
String setAsideUnreadableDatabase(String databasePath) {
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
  final target = '$databasePath.unreadable-$stamp';
  File(databasePath).renameSync(target);
  for (final s in ['-wal', '-shm', '-journal']) {
    final f = File('$databasePath$s');
    if (f.existsSync()) f.renameSync('$target$s');
  }
  return target;
}
