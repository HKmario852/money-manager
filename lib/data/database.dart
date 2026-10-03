import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'seed.dart';

part 'database.g.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// 賬戶類型。分類（餐飲、人工）都係 income / expense 賬戶。
enum AccountType { asset, liability, income, expense, equity }

/// 資金賬戶子類型，只用於 asset / liability。
enum AccountSubtype { cash, bank, creditCard, ewallet, other }

enum EntryKind { expense, income, transfer, opening, adjustment }

enum EntryStatus { posted, pending }

enum EntrySource { manual, template, notification, wallet, email, import }

enum BudgetPeriod { monthly }

mixin Timestamps on Table {
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class Accounts extends Table with Timestamps {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text()();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get subtype => textEnum<AccountSubtype>().nullable()();
  TextColumn get parentId => text().nullable().references(Accounts, #id)();
  TextColumn get currency => text().withDefault(const Constant('HKD'))();
  TextColumn get icon => text().nullable()();
  IntColumn get color => integer().nullable()();
  IntColumn get creditLimit => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_entries_occurred_at', columns: {#occurredAt})
class JournalEntries extends Table with Timestamps {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get kind => textEnum<EntryKind>()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get merchant => text().nullable()();
  TextColumn get source =>
      textEnum<EntrySource>().withDefault(const Constant('manual'))();
  TextColumn get externalId => text().nullable()();
  TextColumn get status =>
      textEnum<EntryStatus>().withDefault(const Constant('posted'))();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_postings_account', columns: {#accountId})
@TableIndex(name: 'idx_postings_entry', columns: {#entryId})
class Postings extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get entryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text().references(Accounts, #id)();

  /// 帶正負號，最小貨幣單位（仙）。正數 = 借方，負數 = 貸方。
  IntColumn get amount => integer()();
  IntColumn get baseAmount => integer().nullable()();
  TextColumn get fxRate => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table with Timestamps {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text().unique()();
  IntColumn get color => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class EntryTags extends Table {
  TextColumn get entryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {entryId, tagId};
}

class Attachments extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get entryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();

  /// 相對於 App 附件文件夾嘅路徑。
  TextColumn get filePath => text()();
  TextColumn get mimeType => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table with Timestamps {
  TextColumn get id => text().clientDefault(newId)();

  /// null = 全月總預算；否則係一個 expense 主分類。
  TextColumn get accountId => text().nullable().references(Accounts, #id)();
  TextColumn get period =>
      textEnum<BudgetPeriod>().withDefault(const Constant('monthly'))();
  IntColumn get amount => integer()();

  /// 'YYYY-MM'
  TextColumn get startMonth => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Templates extends Table with Timestamps {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<EntryKind>()();
  IntColumn get amount => integer()();
  @ReferenceName('templatesFrom')
  TextColumn get fromAccountId => text().references(Accounts, #id)();
  @ReferenceName('templatesTo')
  TextColumn get toAccountId => text().references(Accounts, #id)();
  TextColumn get note => text().nullable()();

  /// JSON 陣列，例如 ["tag-id-1","tag-id-2"]
  TextColumn get tagIds => text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Accounts,
    JournalEntries,
    Postings,
    Tags,
    EntryTags,
    Attachments,
    Budgets,
    Templates,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaults(this);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) => into(
    settings,
  ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

/// 設定鍵
abstract final class SettingKeys {
  static const baseCurrency = 'base_currency';
  static const biometricLock = 'biometric_lock';
  static const monthStartDay = 'month_start_day';
  static const onboarded = 'onboarded';
}

/// 系統賬戶 id（固定，方便引擎搵返）
abstract final class SystemAccounts {
  static const openingBalance = 'sys-opening-balance';
  static const adjustment = 'sys-adjustment';
}
