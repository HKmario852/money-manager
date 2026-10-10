import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart' as sql;

/// 資料庫加密（SQLite3 Multiple Ciphers，pubspec 嘅 hooks 揀咗 sqlite3mc）。
///
/// 金鑰係 32 個隨機 byte，用 hex 存喺 Android Keystore 保護嘅 secure storage，唔入資料庫同備份。
/// 舊版 App 留低嘅明文資料庫、或者還原返嚟嘅備份（備份入面係明文），開之前會就地加密。

/// SQLite 明文檔案開頭嘅 16 byte："SQLite format 3\0"
const _plainHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];

/// 新金鑰：32 個隨機 byte 嘅 hex。
String newDatabaseKey() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

bool _validKey(String key) => RegExp(r'^[0-9a-f]{64}$').hasMatch(key);

/// 開資料庫連線之後第一件事：設定金鑰。drift 嘅 NativeDatabase setup 同 sqlite3 都用佢。
void applyDatabaseKey(sql.Database db, String key) {
  if (!_validKey(key)) throw ArgumentError('Invalid database key');
  db.execute("PRAGMA hexkey = '$key'");
}

/// 檔案存在而且係明文 SQLite。
bool isPlaintextDatabase(String path) {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() < _plainHeader.length) return false;
  final raf = file.openSync();
  try {
    final head = raf.readSync(_plainHeader.length);
    for (var i = 0; i < _plainHeader.length; i++) {
      if (head[i] != _plainHeader[i]) return false;
    }
    return true;
  } finally {
    raf.closeSync();
  }
}

/// 如果 [path] 係明文資料庫，就用 [key] 就地加密，再用金鑰重開檢查完整性。
/// 中途出錯會還原返原本嘅明文檔案，唔會半加密。返回有冇加密過。
bool encryptIfPlaintext(String path, String key) {
  if (!isPlaintextDatabase(path)) return false;
  if (!_validKey(key)) throw ArgumentError('Invalid database key');
  final copy = File('$path.pre-encrypt');
  // 舊連線已經關咗；WAL 入面未寫返主檔嘅記錄要先合併，副本先完整
  if (File('$path-wal').existsSync()) _checkpoint(path);
  File(path).copySync(copy.path);
  try {
    final db = sql.sqlite3.open(path);
    try {
      // rekey 唔支援 WAL 模式
      db.execute('PRAGMA journal_mode = DELETE');
      db.execute("PRAGMA hexrekey = '$key'");
    } finally {
      db.close();
    }
    if (isPlaintextDatabase(path)) throw StateError('Encryption is not available in this SQLite build');
    final check = sql.sqlite3.open(path);
    try {
      applyDatabaseKey(check, key);
      final result = check.select('PRAGMA integrity_check').first.values.first;
      if (result != 'ok') throw StateError('Encrypted database failed integrity check: $result');
    } finally {
      check.close();
    }
    copy.deleteSync();
    return true;
  } catch (_) {
    // 還原明文副本
    for (final s in ['-wal', '-shm', '-journal']) {
      final f = File('$path$s');
      if (f.existsSync()) f.deleteSync();
    }
    copy.renameSync(path);
    rethrow;
  }
}

void _checkpoint(String path) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    db.close();
  }
}

/// 將加密資料庫嘅副本 [path] 轉做明文（匯出備份用，備份喺另一部手機都要開到）。
void decryptCopy(String path, String key) {
  if (isPlaintextDatabase(path)) return;
  final db = sql.sqlite3.open(path);
  try {
    applyDatabaseKey(db, key);
    db.execute('PRAGMA journal_mode = DELETE');
    db.execute("PRAGMA rekey = ''");
  } finally {
    db.close();
  }
  if (!isPlaintextDatabase(path)) throw StateError('Could not decrypt the backup copy');
}
