import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';
import 'money.dart';

class LedgerException implements Exception {
  LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool isFund(AccountType t) => t == AccountType.asset || t == AccountType.liability;

/// 用戶喺記賬畫面填嘅嘢。錢由 [fromAccountId] 流去 [toAccountId]：
/// - 支出：from = 資金賬戶，to = 支出分類
/// - 收入：from = 收入分類，to = 資金賬戶
/// - 轉賬：from / to 都係資金賬戶
class EntryDraft {
  EntryDraft({
    required this.kind,
    required this.amount,
    required this.fromAccountId,
    required this.toAccountId,
    required this.occurredAt,
    this.note,
    this.merchant,
    this.tagIds = const [],
  });

  final EntryKind kind;
  final int amount;
  final String fromAccountId;
  final String toAccountId;
  final DateTime occurredAt;
  final String? note;
  final String? merchant;
  final List<String> tagIds;
}

/// 一筆交易嘅顯示用資料。
class TxView {
  TxView({
    required this.entry,
    required this.postings,
    required this.from,
    required this.to,
    required this.tags,
    required this.attachments,
  });

  final JournalEntry entry;
  final List<Posting> postings;
  final Account from;
  final Account to;
  final List<Tag> tags;
  final List<Attachment> attachments;

  /// 正數金額（借方合計）。
  int get amount => postings.where((p) => p.amount > 0).fold(0, (s, p) => s + p.amount);

  /// 呢筆交易對某個資金賬戶嘅影響（帶正負號）。
  int effectOn(String accountId) => postings.where((p) => p.accountId == accountId).fold(0, (s, p) => s + p.amount);

  Account get category => entry.kind == EntryKind.income ? from : to;
  Account get fund => entry.kind == EntryKind.income ? to : from;
}

class PeriodSummary {
  PeriodSummary(this.start, this.income, this.expense);
  final DateTime start;
  final int income;
  final int expense;
  int get net => income - expense;
}

/// 複式記賬引擎。所有寫入都經呢度，保證每張分錄借貸平衡。
class Ledger {
  Ledger(this.db);
  final AppDatabase db;

  // ---------------------------------------------------------------- 寫入

  Future<String> saveEntry(
    EntryDraft d, {
    String? entryId,
    EntrySource source = EntrySource.manual,
    String? externalId,
  }) async {
    if (d.amount <= 0) throw LedgerException('金額要大過 0');
    if (d.fromAccountId == d.toAccountId) throw LedgerException('兩個賬戶唔可以一樣');
    final from = await _account(d.fromAccountId);
    final to = await _account(d.toAccountId);
    _checkKind(d.kind, from, to);

    return db.transaction(() async {
      final id = entryId ?? newId();
      final now = DateTime.now();
      if (entryId == null) {
        await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: Value(id),
                kind: d.kind,
                occurredAt: d.occurredAt,
                note: Value(_blankToNull(d.note)),
                merchant: Value(_blankToNull(d.merchant)),
                source: Value(source),
                externalId: Value(externalId),
              ),
            );
      } else {
        await (db.update(db.journalEntries)..where((e) => e.id.equals(id))).write(
          JournalEntriesCompanion(
            kind: Value(d.kind),
            occurredAt: Value(d.occurredAt),
            note: Value(_blankToNull(d.note)),
            merchant: Value(_blankToNull(d.merchant)),
            updatedAt: Value(now),
          ),
        );
        await (db.delete(db.postings)..where((p) => p.entryId.equals(id))).go();
        await (db.delete(db.entryTags)..where((t) => t.entryId.equals(id))).go();
      }
      await _insertPostings(id, [(d.toAccountId, d.amount), (d.fromAccountId, -d.amount)]);
      for (final tagId in d.tagIds.toSet()) {
        await db.into(db.entryTags).insert(EntryTagsCompanion.insert(entryId: id, tagId: tagId));
      }
      return id;
    });
  }

  /// 寫入任意分錄行。檢查：至少兩行、加埋 = 0。
  Future<String> postLines(
    EntryKind kind,
    List<(String accountId, int amount)> lines, {
    DateTime? occurredAt,
    String? note,
  }) {
    return db.transaction(() async {
      final id = newId();
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: Value(id),
              kind: kind,
              occurredAt: occurredAt ?? DateTime.now(),
              note: Value(note),
            ),
          );
      await _insertPostings(id, lines);
      return id;
    });
  }

  Future<void> _insertPostings(String entryId, List<(String, int)> lines) async {
    if (lines.length < 2) throw LedgerException('分錄最少要兩行');
    final sum = lines.fold(0, (s, l) => s + l.$2);
    if (sum != 0) throw LedgerException('借貸唔平衡（差 $sum）');
    for (final (accountId, amount) in lines) {
      await db
          .into(db.postings)
          .insert(
            PostingsCompanion.insert(entryId: entryId, accountId: accountId, amount: amount, baseAmount: Value(amount)),
          );
    }
  }

  void _checkKind(EntryKind kind, Account from, Account to) {
    final ok = switch (kind) {
      EntryKind.expense => isFund(from.type) && to.type == AccountType.expense,
      EntryKind.income => from.type == AccountType.income && isFund(to.type),
      EntryKind.transfer => isFund(from.type) && isFund(to.type),
      EntryKind.opening || EntryKind.adjustment => true,
    };
    if (!ok) throw LedgerException('賬戶類型同交易類型唔夾');
  }

  Future<void> deleteEntry(String id) async {
    await (db.update(db.journalEntries)..where((e) => e.id.equals(id))).write(
      JournalEntriesCompanion(deletedAt: Value(DateTime.now()), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> addAttachment(String entryId, String relativePath, {String? mimeType}) => db
      .into(db.attachments)
      .insert(AttachmentsCompanion.insert(entryId: entryId, filePath: relativePath, mimeType: Value(mimeType)));

  Future<void> removeAttachment(String id) => (db.delete(db.attachments)..where((a) => a.id.equals(id))).go();

  /// 新增資金賬戶。[openingBalance] 用「顯示值」：資產係結餘，負債係欠款（正數）。
  Future<String> createFundAccount({
    required String name,
    required AccountType type,
    required AccountSubtype subtype,
    String? icon,
    int? color,
    int? creditLimit,
    int openingBalance = 0,
  }) async {
    if (!isFund(type)) throw LedgerException('只可以新增資產或負債賬戶');
    return db.transaction(() async {
      final id = newId();
      final order = await _nextOrder(type, null);
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: Value(id),
              name: name,
              type: type,
              subtype: Value(subtype),
              icon: Value(icon),
              color: Value(color),
              creditLimit: Value(creditLimit),
              sortOrder: Value(order),
            ),
          );
      if (openingBalance != 0) {
        final signed = toSigned(type, openingBalance);
        await postLines(EntryKind.opening, [(id, signed), (SystemAccounts.openingBalance, -signed)], note: '期初結餘');
      }
      return id;
    });
  }

  Future<String> createCategory({
    required String name,
    required AccountType type,
    String? parentId,
    String? icon,
    int? color,
  }) async {
    if (type != AccountType.expense && type != AccountType.income) {
      throw LedgerException('分類只可以係收入或支出');
    }
    if (parentId != null) {
      final parent = await _account(parentId);
      if (parent.parentId != null) throw LedgerException('分類最多兩層');
      if (parent.type != type) throw LedgerException('子分類類型要同主分類一樣');
    }
    final id = newId();
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: Value(id),
            name: name,
            type: type,
            parentId: Value(parentId),
            icon: Value(icon),
            color: Value(color),
            sortOrder: Value(await _nextOrder(type, parentId)),
          ),
        );
    return id;
  }

  Future<void> updateAccount(String id, AccountsCompanion changes) =>
      (db.update(db.accounts)..where((a) => a.id.equals(id))).write(changes.copyWith(updatedAt: Value(DateTime.now())));

  /// 有交易嘅賬戶只可以封存；冇交易就真係刪除。返回 true = 已刪除。
  Future<bool> archiveOrDelete(String id) async {
    final used =
        await (db.select(db.postings)
              ..where((p) => p.accountId.equals(id))
              ..limit(1))
            .get();
    final children = await (db.select(db.accounts)..where((a) => a.parentId.equals(id))).get();
    final usedByTemplate = await (db.select(
      db.templates,
    )..where((t) => t.fromAccountId.equals(id) | t.toAccountId.equals(id))).get();
    if (used.isEmpty && children.isEmpty && usedByTemplate.isEmpty) {
      await (db.delete(db.budgets)..where((b) => b.accountId.equals(id))).go();
      await (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();
      return true;
    }
    await updateAccount(id, const AccountsCompanion(isArchived: Value(true)));
    for (final c in children) {
      await updateAccount(c.id, const AccountsCompanion(isArchived: Value(true)));
    }
    return false;
  }

  /// 將賬戶結餘調整到 [targetDisplay]（顯示值），差額記入「結餘調整」。
  Future<void> adjustBalance(String accountId, int targetDisplay) async {
    final account = await _account(accountId);
    final current = (await balances())[accountId] ?? 0;
    final diff = toSigned(account.type, targetDisplay) - current;
    if (diff == 0) return;
    await postLines(EntryKind.adjustment, [(accountId, diff), (SystemAccounts.adjustment, -diff)], note: '結餘調整');
  }

  Future<void> reorder(List<String> ids) => db.transaction(() async {
    for (var i = 0; i < ids.length; i++) {
      await updateAccount(ids[i], AccountsCompanion(sortOrder: Value(i)));
    }
  });

  // ---------------------------------------------------------------- Tag

  Future<String> createTag(String name) async {
    final clean = name.trim().replaceFirst(RegExp(r'^#'), '');
    if (clean.isEmpty) throw LedgerException('Tag 名唔可以空白');
    final existing = await (db.select(db.tags)..where((t) => t.name.equals(clean))).getSingleOrNull();
    if (existing != null) {
      if (existing.deletedAt != null) {
        await (db.update(
          db.tags,
        )..where((t) => t.id.equals(existing.id))).write(const TagsCompanion(deletedAt: Value(null)));
      }
      return existing.id;
    }
    final id = newId();
    await db.into(db.tags).insert(TagsCompanion.insert(id: Value(id), name: clean));
    return id;
  }

  Future<void> renameTag(String id, String name) async {
    final clean = name.trim().replaceFirst(RegExp(r'^#'), '');
    final existing = await (db.select(db.tags)..where((t) => t.name.equals(clean))).getSingleOrNull();
    if (existing != null && existing.id != id) {
      await mergeTags(from: id, into: existing.id);
      return;
    }
    await (db.update(
      db.tags,
    )..where((t) => t.id.equals(id))).write(TagsCompanion(name: Value(clean), updatedAt: Value(DateTime.now())));
  }

  Future<void> mergeTags({required String from, required String into}) => db.transaction(() async {
    await db.customStatement(
      'INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) SELECT entry_id, ? FROM entry_tags WHERE tag_id = ?',
      [into, from],
    );
    await (db.delete(db.tags)..where((t) => t.id.equals(from))).go();
  });

  Future<void> deleteTag(String id) => (db.delete(db.tags)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------- 模板

  Future<void> saveTemplate(String name, EntryDraft d, {String? id}) async {
    final companion = TemplatesCompanion(
      name: Value(name),
      kind: Value(d.kind),
      amount: Value(d.amount),
      fromAccountId: Value(d.fromAccountId),
      toAccountId: Value(d.toAccountId),
      note: Value(_blankToNull(d.note)),
      tagIds: Value(jsonEncode(d.tagIds)),
      updatedAt: Value(DateTime.now()),
    );
    if (id == null) {
      final count = await db.templates.count().getSingle();
      await db.into(db.templates).insert(companion.copyWith(id: Value(newId()), sortOrder: Value(count)));
    } else {
      await (db.update(db.templates)..where((t) => t.id.equals(id))).write(companion);
    }
  }

  EntryDraft draftFromTemplate(Template t, {DateTime? at}) => EntryDraft(
    kind: t.kind,
    amount: t.amount,
    fromAccountId: t.fromAccountId,
    toAccountId: t.toAccountId,
    occurredAt: at ?? DateTime.now(),
    note: t.note,
    tagIds: (jsonDecode(t.tagIds) as List).cast<String>(),
  );

  Future<String> useTemplate(Template t) => saveEntry(draftFromTemplate(t), source: EntrySource.template);

  Future<void> deleteTemplate(String id) => (db.delete(db.templates)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------- 預算

  Future<void> saveBudget({String? id, String? categoryId, required int amount}) async {
    if (amount <= 0) throw LedgerException('預算要大過 0');
    if (id == null) {
      final existing =
          await (db.select(db.budgets)
                ..where((b) => categoryId == null ? b.accountId.isNull() : b.accountId.equals(categoryId))
                ..where((b) => b.deletedAt.isNull()))
              .getSingleOrNull();
      id = existing?.id;
    }
    if (id == null) {
      await db.into(db.budgets).insert(BudgetsCompanion.insert(accountId: Value(categoryId), amount: amount));
    } else {
      await (db.update(db.budgets)..where((b) => b.id.equals(id!))).write(
        BudgetsCompanion(amount: Value(amount), updatedAt: Value(DateTime.now())),
      );
    }
  }

  Future<void> deleteBudget(String id) => (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();

  // ---------------------------------------------------------------- 查詢

  /// 每個賬戶嘅帶號結餘（只計已確認、未刪除嘅分錄）。
  Future<Map<String, int>> balances({DateTime? asOf}) => _sumByAccount(before: asOf);

  Future<Map<String, int>> _sumByAccount({DateTime? from, DateTime? before, List<AccountType>? types}) async {
    final p = db.postings, e = db.journalEntries, a = db.accounts;
    final total = p.amount.sum();
    final q =
        db.selectOnly(p).join([
            innerJoin(e, e.id.equalsExp(p.entryId), useColumns: false),
            innerJoin(a, a.id.equalsExp(p.accountId), useColumns: false),
          ])
          ..addColumns([p.accountId, total])
          ..where(e.deletedAt.isNull() & e.status.equalsValue(EntryStatus.posted))
          ..groupBy([p.accountId]);
    if (from != null) q.where(e.occurredAt.isBiggerOrEqualValue(from));
    if (before != null) q.where(e.occurredAt.isSmallerThanValue(before));
    if (types != null) q.where(a.type.isIn(types.map((t) => t.name)));
    final rows = await q.get();
    return {for (final r in rows) r.read(p.accountId)!: r.read(total) ?? 0};
  }

  Future<int> netWorth({DateTime? asOf}) async {
    final accounts = await db.select(db.accounts).get();
    final bal = await balances(asOf: asOf);
    return accounts.where((a) => isFund(a.type)).fold<int>(0, (s, a) => s + (bal[a.id] ?? 0));
  }

  /// 期間內每個收入/支出分類嘅帶號合計（支出正數，收入負數）。
  Future<Map<String, int>> categoryTotals(DateTime from, DateTime to) =>
      _sumByAccount(from: from, before: to, types: const [AccountType.expense, AccountType.income]);

  Future<PeriodSummary> summary(DateTime from, DateTime to) async {
    final accounts = {for (final a in await db.select(db.accounts).get()) a.id: a};
    final totals = await categoryTotals(from, to);
    var income = 0, expense = 0;
    totals.forEach((id, total) {
      if (accounts[id]?.type == AccountType.expense) expense += total;
      if (accounts[id]?.type == AccountType.income) income -= total;
    });
    return PeriodSummary(from, income, expense);
  }

  Future<List<PeriodSummary>> summaries(List<(DateTime, DateTime)> ranges) async => [
    for (final (from, to) in ranges) await summary(from, to),
  ];

  Future<List<PeriodSummary>> recentPeriods(int count, int startDay, {DateTime? now}) async {
    final result = <PeriodSummary>[];
    var (start, end) = periodRange(now ?? DateTime.now(), startDay);
    for (var i = 0; i < count; i++) {
      result.insert(0, await summary(start, end));
      end = start;
      start = periodRange(start.subtract(const Duration(days: 1)), startDay).$1;
    }
    return result;
  }

  Future<List<TxView>> transactions({
    DateTime? from,
    DateTime? to,
    String? accountId,
    String? categoryId,
    String? tagId,
    EntryKind? kind,
    String? search,
    List<String>? entryIds,
    int? limit,
    bool includeSystem = false,
  }) async {
    final accounts = {for (final a in await db.select(db.accounts).get()) a.id: a};
    final q = db.select(db.journalEntries)
      ..where((e) => e.deletedAt.isNull())
      ..orderBy([(e) => OrderingTerm.desc(e.occurredAt), (e) => OrderingTerm.desc(e.createdAt)]);
    if (from != null) q.where((e) => e.occurredAt.isBiggerOrEqualValue(from));
    if (to != null) q.where((e) => e.occurredAt.isSmallerThanValue(to));
    if (kind != null) q.where((e) => e.kind.equalsValue(kind));
    if (entryIds != null) q.where((e) => e.id.isIn(entryIds));
    if (!includeSystem && kind == null && entryIds == null) {
      q.where((e) => e.kind.isInValues([EntryKind.expense, EntryKind.income, EntryKind.transfer]));
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((e) => e.note.like(s) | e.merchant.like(s));
    }
    if (accountId != null || categoryId != null) {
      final ids = <String>{
        ?accountId,
        if (categoryId != null) ...[
          categoryId,
          ...accounts.values.where((a) => a.parentId == categoryId).map((a) => a.id),
        ],
      };
      q.where(
        (e) => existsQuery(db.select(db.postings)..where((p) => p.entryId.equalsExp(e.id) & p.accountId.isIn(ids))),
      );
    }
    if (tagId != null) {
      q.where(
        (e) => existsQuery(db.select(db.entryTags)..where((t) => t.entryId.equalsExp(e.id) & t.tagId.equals(tagId))),
      );
    }
    if (limit != null) q.limit(limit);
    final entries = await q.get();
    if (entries.isEmpty) return [];

    final ids = entries.map((e) => e.id).toList();
    final postings = await (db.select(db.postings)..where((p) => p.entryId.isIn(ids))).get();
    final tagRows = await (db.select(db.entryTags).join([
      innerJoin(db.tags, db.tags.id.equalsExp(db.entryTags.tagId)),
    ])..where(db.entryTags.entryId.isIn(ids))).get();
    final atts = await (db.select(db.attachments)..where((a) => a.entryId.isIn(ids))).get();

    final byEntry = <String, List<Posting>>{};
    for (final p in postings) {
      byEntry.putIfAbsent(p.entryId, () => []).add(p);
    }
    final tagsByEntry = <String, List<Tag>>{};
    for (final r in tagRows) {
      tagsByEntry.putIfAbsent(r.readTable(db.entryTags).entryId, () => []).add(r.readTable(db.tags));
    }
    return [
      for (final e in entries)
        if (byEntry[e.id] case final ps? when ps.length >= 2)
          TxView(
            entry: e,
            postings: ps,
            from: accounts[ps.firstWhere((p) => p.amount < 0, orElse: () => ps.first).accountId]!,
            to: accounts[ps.firstWhere((p) => p.amount > 0, orElse: () => ps.last).accountId]!,
            tags: tagsByEntry[e.id] ?? const [],
            attachments: atts.where((a) => a.entryId == e.id).toList(),
          ),
    ];
  }

  Future<TxView?> transaction(String id) async => (await transactions(entryIds: [id])).firstOrNull;

  // ---------------------------------------------------------------- helpers

  Future<Account> _account(String id) async {
    final a = await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
    if (a == null) throw LedgerException('搵唔到賬戶');
    return a;
  }

  Future<int> _nextOrder(AccountType type, String? parentId) async {
    final rows =
        await (db.select(db.accounts)
              ..where((a) => a.type.equalsValue(type))
              ..where((a) => parentId == null ? a.parentId.isNull() : a.parentId.equals(parentId)))
            .get();
    return rows.length;
  }

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

/// 顯示值 -> 帶號值。負債同收入嘅正常結餘係貸方（負數）。
int toSigned(AccountType type, int display) =>
    type == AccountType.liability || type == AccountType.income || type == AccountType.equity ? -display : display;

/// 帶號值 -> 顯示值。
int toDisplay(AccountType type, int signed) => toSigned(type, signed);
