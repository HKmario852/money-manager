import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/database.dart';
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
