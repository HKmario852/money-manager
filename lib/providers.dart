import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/database.dart';
import 'domain/capture/capture_service.dart';
import 'domain/capture/gemini.dart';
import 'domain/capture/parser.dart';
import 'domain/capture/sources.dart';
import 'domain/ledger.dart';
import 'domain/money.dart';

/// App 數據目錄、資料庫同附件路徑。喺 main() 開 App 之前設定。
class AppPaths {
  AppPaths(this.root);
  final String root;
  String get database => p.join(root, 'money_manager.sqlite');
  String get attachments => p.join(root, 'attachments');

  static Future<AppPaths> resolve() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(p.join(dir.path, 'attachments')).create(recursive: true);
    return AppPaths(dir.path);
  }
}

final appPathsProvider = Provider<AppPaths>((ref) => throw UnimplementedError());

final databaseProvider = Provider<AppDatabase>((ref) {
  final paths = ref.watch(appPathsProvider);
  final db = AppDatabase(NativeDatabase.createInBackground(File(paths.database)));
  ref.onDispose(() async {
    try {
      await db.close();
    } catch (_) {}
  });
  return db;
});

final ledgerProvider = Provider<Ledger>((ref) => Ledger(ref.watch(databaseProvider)));

/// 任何資料表有改動就重新計一次。個人記賬數據量細，咁做最簡單可靠。
Stream<T> _live<T>(Ref ref, Future<T> Function(Ledger ledger) compute) async* {
  final ledger = ref.watch(ledgerProvider);
  yield await compute(ledger);
  await for (final _ in ledger.db.tableUpdates()) {
    yield await compute(ledger);
  }
}

final accountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)
        ..where((a) => a.deletedAt.isNull())
        ..orderBy([(a) => OrderingTerm.asc(a.sortOrder), (a) => OrderingTerm.asc(a.name)]))
      .watch();
});

final accountMapProvider = Provider<Map<String, Account>>((ref) {
  final list = ref.watch(accountsProvider).value ?? const [];
  return {for (final a in list) a.id: a};
});

final balancesProvider = StreamProvider<Map<String, int>>((ref) => _live(ref, (l) => l.balances()));

final tagsProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tags)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

final templatesProvider = StreamProvider<List<Template>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.templates)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.budgets)..where((b) => b.deletedAt.isNull())).watch();
});

final settingsProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.settings).watch().map((rows) => {for (final r in rows) r.key: r.value});
});

final monthStartDayProvider = Provider<int>((ref) {
  final v = ref.watch(settingsProvider).value?[SettingKeys.monthStartDay];
  return int.tryParse(v ?? '') ?? 1;
});

/// 只記支出模式：唔顯示淨資產同帳戶結餘。
final spendingOnlyProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider).value?[SettingKeys.spendingOnly] == 'true',
);

/// 底部導航揀咗邊頁：0 首頁、1 統計、2 預算、3 帳戶。
class HomeTab extends Notifier<int> {
  @override
  int build() => 0;
  void select(int i) => state = i;
}

final homeTabProvider = NotifierProvider<HomeTab, int>(HomeTab.new);

/// 儲蓄率目標（%），預設 50。
final savingsTargetProvider = Provider<int>((ref) {
  final v = ref.watch(settingsProvider).value?[SettingKeys.savingsTarget];
  return (int.tryParse(v ?? '') ?? 50).clamp(0, 90);
});

/// 交易列表同報表而家睇緊邊個月（任何喺嗰期入面嘅日子）。
class PeriodAnchor extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void shift(int months) {
    final startDay = ref.read(monthStartDayProvider);
    final (start, _) = periodRange(state, startDay);
    state = DateTime(start.year, start.month + months, start.day);
  }

  void reset() => state = DateTime.now();
}

final periodAnchorProvider = NotifierProvider<PeriodAnchor, DateTime>(PeriodAnchor.new);

final currentPeriodProvider = Provider<(DateTime, DateTime)>((ref) {
  return periodRange(ref.watch(periodAnchorProvider), ref.watch(monthStartDayProvider));
});

/// 今期（以今日計）。首頁同預算用。
final thisPeriodProvider = Provider<(DateTime, DateTime)>((ref) {
  return periodRange(DateTime.now(), ref.watch(monthStartDayProvider));
});

typedef TxFilter = ({
  DateTime? from,
  DateTime? to,
  String? accountId,
  String? categoryId,
  String? tagId,
  EntryKind? kind,
  String? search,
  int? limit,
});

const TxFilter emptyFilter = (
  from: null,
  to: null,
  accountId: null,
  categoryId: null,
  tagId: null,
  kind: null,
  search: null,
  limit: null,
);

final transactionsProvider = StreamProvider.autoDispose.family<List<TxView>, TxFilter>(
  (ref, f) => _live(
    ref,
    (l) => l.transactions(
      from: f.from,
      to: f.to,
      accountId: f.accountId,
      categoryId: f.categoryId,
      tagId: f.tagId,
      kind: f.kind,
      search: f.search,
      limit: f.limit,
    ),
  ),
);

final transactionProvider = StreamProvider.autoDispose.family<TxView?, String>(
  (ref, id) => _live(ref, (l) => l.transaction(id)),
);

final categoryTotalsProvider = StreamProvider.autoDispose.family<Map<String, int>, (DateTime, DateTime)>(
  (ref, range) => _live(ref, (l) => l.categoryTotals(range.$1, range.$2)),
);

final summaryProvider = StreamProvider.autoDispose.family<PeriodSummary, (DateTime, DateTime)>(
  (ref, range) => _live(ref, (l) => l.summary(range.$1, range.$2)),
);

final recentPeriodsProvider = StreamProvider.autoDispose.family<List<PeriodSummary>, DateTime>((ref, anchor) {
  final startDay = ref.watch(monthStartDayProvider);
  return _live(ref, (l) => l.recentPeriods(6, startDay, now: anchor));
});

/// 統計頁：最近 count 期（週 / 月 / 年）嘅收支，由舊到新。
final unitSummariesProvider = StreamProvider.autoDispose.family<List<PeriodSummary>, (PeriodUnit, DateTime, int)>((
  ref,
  key,
) {
  final startDay = ref.watch(monthStartDayProvider);
  final (unit, anchor, count) = key;
  return _live(ref, (l) => l.summaries(recentRanges(unit, anchor, startDay, count)));
});

/// 某日之前（唔包嗰日）嘅淨資產，用嚟計「比上月」。
final netWorthAtProvider = StreamProvider.autoDispose.family<int, DateTime>(
  (ref, at) => _live(ref, (l) => l.netWorth(asOf: at)),
);

final netWorthProvider = Provider<AsyncValue<(int assets, int liabilities)>>((ref) {
  final accounts = ref.watch(accountMapProvider);
  return ref.watch(balancesProvider).whenData((bal) {
    var assets = 0, liabilities = 0;
    bal.forEach((id, v) {
      final t = accounts[id]?.type;
      if (t == AccountType.asset) assets += v;
      if (t == AccountType.liability) liabilities -= v;
    });
    return (assets, liabilities);
  });
});

// ───────── 自動記錄 ─────────

const _secure = FlutterSecureStorage();
const geminiKeyStorageKey = 'gemini_api_key';

/// Gemini API key，加密存喺手機（Android Keystore / iOS Keychain），唔入資料庫同備份。
class GeminiKey extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    try {
      return await _secure.read(key: geminiKeyStorageKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> set(String? key) async {
    final v = key?.trim();
    if (v == null || v.isEmpty) {
      await _secure.delete(key: geminiKeyStorageKey);
    } else {
      await _secure.write(key: geminiKeyStorageKey, value: v);
    }
    state = AsyncData(v == null || v.isEmpty ? null : v);
  }
}

final geminiKeyProvider = AsyncNotifierProvider<GeminiKey, String?>(GeminiKey.new);

final captureServiceProvider = Provider<CaptureService>((ref) => CaptureService(ref.watch(ledgerProvider)));

final notificationBridgeProvider = Provider<NotificationBridge>((ref) => const NotificationBridge());

/// 待確認嘅自動捕捉，新到舊。
final pendingCapturesProvider = StreamProvider<List<Capture>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.captures)
        ..where((c) => c.status.equalsValue(CaptureStatus.pending))
        ..orderBy([(c) => OrderingTerm.desc(c.occurredAt)]))
      .watch();
});

/// 一次同步嘅結果。
class SyncReport {
  SyncReport({this.added = 0, this.autoConfirmed = 0, this.updated = 0, this.skipped = 0, this.errors = const []});
  int added;
  int autoConfirmed;

  /// 再匯入時更新咗金額嘅待確認
  int updated;

  /// 已經匯入過或者同其他記錄重複
  int skipped;
  List<String> errors;
}

/// 攞通知隊列同 Gmail 收據，逐個解析。App 開啟、返回前景、或者用戶撳重新整理時行。
class CaptureSync {
  CaptureSync(this.ref);
  final Ref ref;
  Future<SyncReport>? _running;

  /// Gmail 最少隔幾耐先再攞（手動重新整理唔受限）。
  static const gmailInterval = Duration(minutes: 15);

  Future<SyncReport> run({bool force = false}) => _running ??= _run(force).whenComplete(() => _running = null);

  Future<SyncReport> _run(bool force) async {
    final report = SyncReport(errors: []);
    final db = ref.read(databaseProvider);
    final service = ref.read(captureServiceProvider);
    final auto = await db.getSetting(SettingKeys.autoConfirm) == 'true';
    final gemini = await _gemini();
    try {
      await service.repairPlayReceipts();
    } catch (e) {
      report.errors.add('$e');
    }

    final raws = <RawCapture>[...await ref.read(notificationBridgeProvider).drain()];

    final url = await db.getSetting(SettingKeys.gmailScriptUrl);
    final token = await db.getSetting(SettingKeys.gmailScriptToken);
    if (url != null && url.isNotEmpty && token != null) {
      final last = int.tryParse(await db.getSetting(SettingKeys.gmailLastSync) ?? '');
      final lastAt = last != null ? DateTime.fromMillisecondsSinceEpoch(last) : null;
      if (force || lastAt == null || DateTime.now().difference(lastAt) > gmailInterval) {
        final gmail = GmailBridge(url: url, token: token);
        try {
          final started = DateTime.now();
          // 由上次攞到嘅時間再退後一日，避免郵件延遲漏咗；重複嘅會用 id 去重
          raws.addAll(await gmail.fetch(since: lastAt?.subtract(const Duration(days: 1))));
          await db.setSetting(SettingKeys.gmailLastSync, '${started.millisecondsSinceEpoch}');
        } on GmailException catch (e) {
          report.errors.add(e.message);
        } finally {
          gmail.close();
        }
      }
    }

    raws.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    for (final raw in raws) {
      try {
        switch (await service.ingest(raw, gemini: gemini, autoConfirm: auto)) {
          case IngestOutcome.added || IngestOutcome.needsGemini:
            report.added++;
          case IngestOutcome.autoConfirmed:
            report.autoConfirmed++;
          default:
        }
      } on GeminiException catch (e) {
        // Gemini 出錯：照樣留低，等用戶自己睇
        await service.ingest(raw);
        report.added++;
        if (!report.errors.contains(e.message)) report.errors.add(e.message);
      } catch (e) {
        report.errors.add('$e');
      }
    }
    gemini?.close();
    return report;
  }

  Future<GeminiParser?> _gemini() async {
    final key = await ref.read(geminiKeyProvider.future);
    if (key == null) return null;
    final model = await ref.read(databaseProvider).getSetting(SettingKeys.geminiModel);
    return GeminiParser(apiKey: key, model: (model == null || model.isEmpty) ? defaultGeminiModel : model);
  }

  /// 用 Gemini 讀八達通 App 交易紀錄截圖，每行放入待確認。重複匯入同一行會略過。
  Future<SyncReport> importOctopusScreenshots(List<({List<int> bytes, String mimeType})> images) async {
    final report = SyncReport(errors: []);
    final gemini = await _gemini();
    if (gemini == null) {
      report.errors.add('請先喺「自動記錄」設定輸入 Gemini API key');
      return report;
    }
    final db = ref.read(databaseProvider);
    final service = ref.read(captureServiceProvider);
    final auto = await db.getSetting(SettingKeys.autoConfirm) == 'true';
    final accounts = await (db.select(db.accounts)..where((a) => a.deletedAt.isNull())).get();
    try {
      for (final image in images) {
        final List<OctopusRow> rows;
        try {
          rows = await gemini.parseOctopusScreenshot(
            image.bytes,
            mimeType: image.mimeType,
            categories: categoryPaths(accounts),
          );
        } on GeminiException catch (e) {
          if (!report.errors.contains(e.message)) report.errors.add(e.message);
          continue;
        }
        rows.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
        for (final (raw, payment) in octopusRowsToCaptures(rows)) {
          switch (await service.ingestParsed(raw, payment, autoConfirm: auto)) {
            case IngestOutcome.added:
              report.added++;
            case IngestOutcome.autoConfirmed:
              report.autoConfirmed++;
            default:
              report.skipped++;
          }
        }
      }
    } finally {
      gemini.close();
    }
    return report;
  }

  /// 開始用 app 嘅時間（最早建立嘅賬戶）。
  Future<DateTime?> appStartedAt() async {
    final db = ref.read(databaseProvider);
    final first = db.accounts.createdAt.min();
    return (await (db.selectOnly(db.accounts)..addColumns([first])).getSingle()).read(first);
  }

  /// 固定格式嘅匯入（Google Takeout 嘅 Play 購買、淘寶訂單）：唔使 Gemini。
  Future<SyncReport> importTakeout(List<(RawCapture, ParsedPayment)> items, {bool refreshPending = false}) async {
    final report = SyncReport(errors: []);
    final service = ref.read(captureServiceProvider);
    final auto = await ref.read(databaseProvider).getSetting(SettingKeys.autoConfirm) == 'true';
    for (final (raw, payment) in items) {
      switch (await service.ingestParsed(
        raw,
        payment,
        parsedBy: ParsedBy.rule,
        autoConfirm: auto,
        refreshPending: refreshPending,
      )) {
        case IngestOutcome.added:
          report.added++;
        case IngestOutcome.autoConfirmed:
          report.autoConfirmed++;
        case IngestOutcome.updated:
          report.updated++;
        default:
          report.skipped++;
      }
    }
    return report;
  }
}

final captureSyncProvider = Provider<CaptureSync>((ref) => CaptureSync(ref));
