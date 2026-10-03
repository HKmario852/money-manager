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

/// 自動捕捉到嘅消費：等確認、已入帳、已略過、同另一筆重複。
enum CaptureStatus { pending, confirmed, dismissed, duplicate }

/// 解析方法：規則定 Gemini。
enum ParsedBy { rule, gemini, none }

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
  TextColumn get source => textEnum<EntrySource>().withDefault(const Constant('manual'))();
  TextColumn get externalId => text().nullable()();
  TextColumn get status => textEnum<EntryStatus>().withDefault(const Constant('posted'))();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_postings_account', columns: {#accountId})
@TableIndex(name: 'idx_postings_entry', columns: {#entryId})
class Postings extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get entryId => text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get entryId => text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {entryId, tagId};
}

class Attachments extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get entryId => text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();

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
  TextColumn get period => textEnum<BudgetPeriod>().withDefault(const Constant('monthly'))();
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

/// 由通知或者電郵自動捕捉到、未入帳嘅消費。確認後會變成一張 journal entry。
@TableIndex(name: 'idx_captures_status', columns: {#status})
class Captures extends Table {
  TextColumn get id => text().clientDefault(newId)();

  /// notification / email
  TextColumn get source => textEnum<EntrySource>()();

  /// 來源 App 套件名或者寄件人，例如 hk.alipay.wallet、googleplay-noreply@google.com
  TextColumn get sourceKey => text()();

  /// 顯示用嘅來源名，例如 AlipayHK、Google Play
  TextColumn get sourceLabel => text().nullable()();

  /// 去重用：通知 key + 時間，或者 Gmail message id
  TextColumn get externalId => text().unique()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text()();
  DateTimeColumn get occurredAt => dateTime()();

  /// 解析結果（可能係 null = 解析唔到）
  IntColumn get amount => integer().nullable()();
  TextColumn get currency => text().nullable()();
  TextColumn get merchant => text().nullable()();
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();

  /// 增值（例如現金轉入八達通）：[categoryId] 係轉出嘅資金賬戶，[fundAccountId] 係轉入嘅。
  BoolColumn get isTransfer => boolean().withDefault(const Constant(false))();
  TextColumn get categoryId => text().nullable().references(Accounts, #id)();
  @ReferenceName('capturesFund')
  TextColumn get fundAccountId => text().nullable().references(Accounts, #id)();
  TextColumn get parsedBy => textEnum<ParsedBy>().withDefault(const Constant('none'))();

  TextColumn get status => textEnum<CaptureStatus>().withDefault(const Constant('pending'))();
  TextColumn get entryId => text().nullable().references(JournalEntries, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 確認過之後學返嘅對應：「m:商戶」→ 分類，「s:來源」→ 資金賬戶。
class CaptureRules extends Table {
  TextColumn get key => text()();
  TextColumn get categoryId => text().nullable().references(Accounts, #id)();
  @ReferenceName('captureRulesFund')
  TextColumn get fundAccountId => text().nullable().references(Accounts, #id)();

  @override
  Set<Column> get primaryKey => {key};
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
    Captures,
    CaptureRules,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaults(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(captures);
        await m.createTable(captureRules);
        await m.createIndex(idxCapturesStatus);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<String?> getSetting(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

/// 設定鍵
abstract final class SettingKeys {
  static const baseCurrency = 'base_currency';
  static const biometricLock = 'biometric_lock';
  static const monthStartDay = 'month_start_day';
  static const onboarded = 'onboarded';
  static const savingsTarget = 'savings_target';

  /// 自動捕捉：確認咗分類同賬戶就直接入帳，唔使撳 ✓
  static const autoConfirm = 'capture_auto_confirm';

  /// Gmail 收據：Apps Script 網址同密鑰
  static const gmailScriptUrl = 'gmail_script_url';
  static const gmailScriptToken = 'gmail_script_token';

  /// 上次攞 Gmail 收據嘅時間（毫秒）
  static const gmailLastSync = 'gmail_last_sync';

  /// Gemini 模型名
  static const geminiModel = 'gemini_model';
  static const updateLastCheck = 'update_last_check';
  static const updateSkippedBuild = 'update_skipped_build';
}

/// 系統賬戶 id（固定，方便引擎搵返）
abstract final class SystemAccounts {
  static const openingBalance = 'sys-opening-balance';
  static const adjustment = 'sys-adjustment';
}
