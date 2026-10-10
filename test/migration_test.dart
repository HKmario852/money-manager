import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';

import 'generated_migrations/schema.dart';

/// 每個舊版本嘅資料庫結構（drift_schemas/，由當時嘅程式碼匯出）升級到而家，結果要同新安裝一樣。
/// 改 schemaVersion 之後：dart run drift_dev schema dump lib/data/database.dart drift_schemas/drift_schema_vN.json
/// 再 dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in [1, 2, 3]) {
    test('由第 $from 版升級到第 4 版', () async {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      await verifier.migrateAndValidate(db, 4);
      await db.close();
    });
  }
}
