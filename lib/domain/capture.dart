import 'package:drift/drift.dart';

import '../data/database.dart';
import 'gemini.dart';
import 'ledger.dart';

/// 一筆準備入賬嘅自動記錄。
class CaptureCandidate {
  const CaptureCandidate(this.tx, {required this.externalId, required this.source, this.fallbackAccountId});
  final ExtractedTx tx;

  /// 用嚟防止同一個來源重複入賬（通知 key、電郵 id、截圖行內容）
  final String externalId;
  final EntrySource source;

  /// Gemini 揀唔到賬戶時用（例如截圖匯入時用戶揀咗嘅八達通）
  final String? fallbackAccountId;
}

class IngestResult {
  const IngestResult({required this.added, required this.duplicates, required this.skipped});
  final int added;
  final int duplicates;
  final int skipped;
}

/// 將 Gemini 抽出嚟嘅交易寫入賬簿：揀返合理嘅賬戶 / 分類、去重、預設做「待確認」。
class CaptureService {
  CaptureService(this.ledger);
  final Ledger ledger;
  AppDatabase get db => ledger.db;

  /// 兩個來源（例如通知同截圖）記低同一筆嘅容許時間差。
  static const duplicateWindow = Duration(minutes: 15);

  Future<LedgerChoices> choices() async {
    final all = await (db.select(db.accounts)..where((a) => a.deletedAt.isNull() & a.isArchived.equals(false))).get();
    final byId = {for (final a in all) a.id: a};
    String path(Account a) =>
        a.parentId != null && byId[a.parentId] != null ? '${byId[a.parentId]!.name} › ${a.name}' : a.name;
    String fundLabel(Account a) => '${a.name} (${a.subtype?.name ?? a.type.name})';
    return LedgerChoices(
      funds: [for (final a in all.where((a) => isFund(a.type))) (a.id, fundLabel(a))],
      expenseCategories: [
        for (final a in all.where((a) => a.type == AccountType.expense && !a.isSystem)) (a.id, path(a)),
      ],
      incomeCategories: [
        for (final a in all.where((a) => a.type == AccountType.income && !a.isSystem)) (a.id, path(a)),
      ],
    );
  }

  Future<IngestResult> ingest(List<CaptureCandidate> items, {required bool autoPost, String? defaultFundId}) async {
    final accounts = {
      for (final a in await (db.select(db.accounts)..where((a) => a.deletedAt.isNull())).get()) a.id: a,
    };
    final funds = accounts.values.where((a) => isFund(a.type) && !a.isArchived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    String? fallbackCategory(AccountType type) {
      final top = accounts.values.where((a) => a.type == type && a.parentId == null && !a.isArchived && !a.isSystem);
      return (top.where((a) => a.name == '其他').firstOrNull ?? top.lastOrNull)?.id;
    }

    final defaultFund = accounts[defaultFundId]?.id ?? funds.firstOrNull?.id;
    var added = 0, duplicates = 0, skipped = 0;
    for (final c in items) {
      final t = c.tx;
      if (await _seen(c.externalId)) {
        duplicates++;
        continue;
      }
      final String? from, to;
      switch (t.kind) {
        case EntryKind.expense:
          from = t.accountId ?? c.fallbackAccountId ?? defaultFund;
          to = t.categoryId ?? fallbackCategory(AccountType.expense);
        case EntryKind.income:
          from = t.categoryId ?? fallbackCategory(AccountType.income);
          to = t.accountId ?? c.fallbackAccountId ?? defaultFund;
        default:
          to = t.toAccountId ?? c.fallbackAccountId;
          from = t.accountId ?? (to == defaultFund ? null : defaultFund);
      }
      if (from == null || to == null || from == to || !_kindFits(t.kind, accounts[from], accounts[to])) {
        skipped++;
        continue;
      }
      final fund = t.kind == EntryKind.income ? to : from;
      if (await _similarExists(t, fund, c.source)) {
        duplicates++;
        continue;
      }
      await ledger.saveEntry(
        EntryDraft(
          kind: t.kind,
          amount: t.amount,
          fromAccountId: from,
          toAccountId: to,
          occurredAt: t.occurredAt,
          merchant: t.merchant,
          note: [if (t.currency != null && t.currency != 'HKD') '原幣 ${t.currency}', ?t.note].join(' · '),
        ),
        source: c.source,
        status: autoPost ? EntryStatus.posted : EntryStatus.pending,
        externalId: c.externalId,
      );
      added++;
    }
    return IngestResult(added: added, duplicates: duplicates, skipped: skipped);
  }

  bool _kindFits(EntryKind kind, Account? from, Account? to) {
    if (from == null || to == null) return false;
    return switch (kind) {
      EntryKind.expense => isFund(from.type) && to.type == AccountType.expense,
      EntryKind.income => from.type == AccountType.income && isFund(to.type),
      _ => isFund(from.type) && isFund(to.type),
    };
  }

  /// 刪咗（用戶撳咗唔要）嘅都計，咁先唔會再彈返出嚟。
  Future<bool> _seen(String externalId) async {
    final q = db.selectOnly(db.journalEntries)
      ..addColumns([db.journalEntries.id])
      ..where(db.journalEntries.externalId.equals(externalId))
      ..limit(1);
    return (await q.get()).isNotEmpty;
  }

  /// 另一個來源（手動、通知、截圖…）已經有同一個資金賬戶、同金額、時間相近嘅交易。
  /// 同一來源唔比：例如八達通截圖入面連續兩程 \$9.3 車費係兩筆真交易，靠 externalId 分。
  Future<bool> _similarExists(ExtractedTx t, String fundId, EntrySource source) async {
    final e = db.journalEntries, p = db.postings;
    final q = db.selectOnly(e).join([innerJoin(p, p.entryId.equalsExp(e.id), useColumns: false)])
      ..addColumns([e.id])
      ..where(
        e.deletedAt.isNull() &
            e.source.equalsValue(source).not() &
            e.kind.equalsValue(t.kind) &
            p.accountId.equals(fundId) &
            p.amount.abs().equals(t.amount) &
            e.occurredAt.isBetweenValues(t.occurredAt.subtract(duplicateWindow), t.occurredAt.add(duplicateWindow)),
      )
      ..limit(1);
    return (await q.get()).isNotEmpty;
  }
}
