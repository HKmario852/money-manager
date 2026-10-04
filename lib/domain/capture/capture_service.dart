import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../ledger.dart';
import '../money.dart';
import 'gemini.dart';
import 'parser.dart';

/// 通知或者電郵嘅原始內容。
class RawCapture {
  const RawCapture({
    required this.source,
    required this.sourceKey,
    required this.externalId,
    required this.body,
    required this.occurredAt,
    this.sourceLabel,
    this.title,
  });

  final EntrySource source;
  final String sourceKey;
  final String? sourceLabel;
  final String externalId;
  final String? title;
  final String body;
  final DateTime occurredAt;
}

enum IngestOutcome { added, autoConfirmed, duplicate, notPayment, alreadySeen, needsGemini }

/// 唔同來源報同一筆錢（例如 AlipayHK 通知 + Play 收據電郵），喺呢個時間內當重複。
const duplicateWindow = Duration(minutes: 30);

/// 自動捕捉：解析、去重、建議分類同賬戶、確認入帳、記住用戶嘅選擇。
class CaptureService {
  CaptureService(this.ledger);
  final Ledger ledger;
  AppDatabase get db => ledger.db;

  /// 處理一個通知或者電郵。[gemini] 係 null 就只用規則。
  Future<IngestOutcome> ingest(RawCapture raw, {GeminiParser? gemini, bool autoConfirm = false}) async {
    final seen = await (db.select(db.captures)..where((c) => c.externalId.equals(raw.externalId))).getSingleOrNull();
    if (seen != null) return IngestOutcome.alreadySeen;

    final accounts = await (db.select(db.accounts)..where((a) => a.deletedAt.isNull())).get();
    var parsedBy = ParsedBy.rule;
    final rules = parseByRules(sourceKey: raw.sourceKey, title: raw.title, body: raw.body);
    ParsedPayment? payment = rules.payment;
    if (rules.isPayment == false) return IngestOutcome.notPayment;
    if (payment == null) {
      if (gemini == null) {
        // 冇 Gemini：留低俾用戶自己睇，金額留空
        await _insert(raw, null, ParsedBy.none, null, null);
        return IngestOutcome.needsGemini;
      }
      payment = await gemini.parse(
        source: raw.sourceLabel ?? raw.sourceKey,
        title: raw.title,
        body: raw.body,
        categories: categoryPaths(accounts),
      );
      if (payment == null) return IngestOutcome.notPayment;
      parsedBy = ParsedBy.gemini;
    }

    return _store(raw, payment, parsedBy, accounts, autoConfirm: autoConfirm);
  }

  /// 已經解析好嘅記錄（例如 Gemini 讀八達通截圖）。
  Future<IngestOutcome> ingestParsed(
    RawCapture raw,
    ParsedPayment payment, {
    ParsedBy parsedBy = ParsedBy.gemini,
    bool autoConfirm = false,
  }) async {
    final seen = await (db.select(db.captures)..where((c) => c.externalId.equals(raw.externalId))).getSingleOrNull();
    if (seen != null) return IngestOutcome.alreadySeen;
    final accounts = await (db.select(db.accounts)..where((a) => a.deletedAt.isNull())).get();
    return _store(raw, payment, parsedBy, accounts, autoConfirm: autoConfirm);
  }

  Future<IngestOutcome> _store(
    RawCapture raw,
    ParsedPayment payment,
    ParsedBy parsedBy,
    List<Account> accounts, {
    required bool autoConfirm,
  }) async {
    final fundId = await _suggestFund(raw, accounts);
    final categoryId = payment.isTransfer
        ? await _suggestTopUpSource(payment, accounts, fundId)
        : await _suggestCategory(payment, accounts);
    final id = await _insert(raw, payment, parsedBy, categoryId, fundId);

    if (await _isDuplicate(id, raw, payment)) {
      await (db.update(
        db.captures,
      )..where((c) => c.id.equals(id))).write(const CapturesCompanion(status: Value(CaptureStatus.duplicate)));
      return IngestOutcome.duplicate;
    }
    if (autoConfirm && categoryId != null && fundId != null && payment.currency == 'HKD') {
      final capture = await (db.select(db.captures)..where((c) => c.id.equals(id))).getSingle();
      await confirm(capture);
      return IngestOutcome.autoConfirmed;
    }
    return IngestOutcome.added;
  }

  Future<String> _insert(
    RawCapture raw,
    ParsedPayment? p,
    ParsedBy parsedBy,
    String? categoryId,
    String? fundId,
  ) async {
    final id = newId();
    await db
        .into(db.captures)
        .insert(
          CapturesCompanion.insert(
            id: Value(id),
            source: raw.source,
            sourceKey: raw.sourceKey,
            sourceLabel: Value(raw.sourceLabel ?? knownSources[raw.sourceKey]),
            externalId: raw.externalId,
            title: Value(raw.title),
            body: raw.body,
            occurredAt: raw.occurredAt,
            amount: Value(p?.amount),
            currency: Value(p?.currency),
            merchant: Value(p?.merchant),
            isIncome: Value(p?.isIncome ?? false),
            isTransfer: Value(p?.isTransfer ?? false),
            categoryId: Value(categoryId),
            fundAccountId: Value(fundId),
            parsedBy: Value(parsedBy),
          ),
        );
    return id;
  }

  /// 唔同來源、同樣金額、時間好近 = 同一筆；或者用戶已經手動記咗。
  Future<bool> _isDuplicate(String id, RawCapture raw, ParsedPayment p) async {
    final from = raw.occurredAt.subtract(duplicateWindow);
    final to = raw.occurredAt.add(duplicateWindow);
    final others =
        await (db.select(db.captures)..where(
              (c) =>
                  c.id.equals(id).not() &
                  c.sourceKey.equals(raw.sourceKey).not() &
                  c.amount.equals(p.amount) &
                  c.status.isIn([CaptureStatus.pending.name, CaptureStatus.confirmed.name]) &
                  c.occurredAt.isBetweenValues(from, to),
            ))
            .get();
    if (others.isNotEmpty) return true;
    final kind = _kindOf(p.isIncome, p.isTransfer);
    final manual = await ledger.transactions(from: from, to: to, kind: kind);
    return manual.any(
      (t) =>
          t.amount == p.amount &&
          !const {EntrySource.notification, EntrySource.email, EntrySource.import}.contains(t.entry.source),
    );
  }

  Future<String?> _suggestCategory(ParsedPayment p, List<Account> accounts) async {
    final type = p.isIncome ? AccountType.income : AccountType.expense;
    if (p.merchant != null) {
      final rule = await _rule('m:${merchantKey(p.merchant!)}');
      final id = rule?.categoryId;
      if (id != null && accounts.any((a) => a.id == id && a.type == type && !a.isArchived)) return id;
    }
    final hint = p.categoryHint;
    if (hint == null) return null;
    return categoryByPath(hint, accounts, type)?.id;
  }

  /// 增值嘅錢由邊個資金賬戶嚟：記住咗就用返，否則揀現金。
  Future<String?> _suggestTopUpSource(ParsedPayment p, List<Account> accounts, String? toFundId) async {
    final funds = accounts.where((a) => isFund(a.type) && !a.isArchived && a.id != toFundId).toList();
    if (p.merchant != null) {
      final id = (await _rule('t:${merchantKey(p.merchant!)}'))?.categoryId;
      if (id != null && funds.any((a) => a.id == id)) return id;
    }
    return funds.where((a) => a.subtype == AccountSubtype.cash).firstOrNull?.id;
  }

  Future<String?> _suggestFund(RawCapture raw, List<Account> accounts) async {
    final funds = accounts.where((a) => isFund(a.type) && !a.isArchived).toList();
    final rule = await _rule('s:${raw.sourceKey}');
    if (rule?.fundAccountId != null && funds.any((a) => a.id == rule!.fundAccountId)) return rule!.fundAccountId;
    if (raw.sourceKey == octopusScreenshotKey) {
      final octopus = funds.where((a) => a.icon == 'octopus').firstOrNull;
      if (octopus != null) return octopus.id;
    }
    final label = (raw.sourceLabel ?? knownSources[raw.sourceKey])?.toLowerCase();
    if (label == null) return null;
    for (final a in funds) {
      final name = a.name.toLowerCase();
      if (name.contains(label) || label.contains(name)) return a.id;
    }
    return null;
  }

  Future<CaptureRule?> _rule(String key) =>
      (db.select(db.captureRules)..where((r) => r.key.equals(key))).getSingleOrNull();

  /// 確認入帳。可以覆蓋建議嘅金額、分類、賬戶。返回新交易 id。
  Future<String> confirm(Capture c, {int? amount, String? categoryId, String? fundId, DateTime? occurredAt}) async {
    final amt = amount ?? c.amount;
    final cat = categoryId ?? c.categoryId;
    final fund = fundId ?? c.fundAccountId;
    if (amt == null || amt <= 0) throw LedgerException('未有金額');
    if (cat == null) throw LedgerException(c.isTransfer ? '請揀由邊個賬戶增值' : '請揀分類');
    if (fund == null) throw LedgerException('請揀賬戶');
    final note = [
      if (c.currency != null && c.currency != 'HKD') '原幣 ${c.currency}',
      if (c.merchant == null) c.title,
    ].whereType<String>().join(' ');
    final draft = EntryDraft(
      kind: _kindOf(c.isIncome, c.isTransfer),
      amount: amt,
      // 增值：由 cat（轉出賬戶）去 fund；收入：由分類去 fund；支出：由 fund 去分類
      fromAccountId: c.isIncome || c.isTransfer ? cat : fund,
      toAccountId: c.isIncome || c.isTransfer ? fund : cat,
      occurredAt: occurredAt ?? c.occurredAt,
      merchant: c.merchant,
      note: note.isEmpty ? null : note,
    );
    final entryId = await ledger.saveEntry(draft, source: c.source, externalId: c.externalId);
    await markConfirmed(c, entryId: entryId, categoryId: cat, fundId: fund);
    return entryId;
  }

  /// 用戶喺記賬畫面自己改好再存咗：標記已確認，同埋學返分類同賬戶。
  Future<void> markConfirmed(Capture c, {required String entryId, String? categoryId, String? fundId}) async {
    await (db.update(db.captures)..where((x) => x.id.equals(c.id))).write(
      CapturesCompanion(
        status: const Value(CaptureStatus.confirmed),
        entryId: Value(entryId),
        categoryId: Value(categoryId ?? c.categoryId),
        fundAccountId: Value(fundId ?? c.fundAccountId),
      ),
    );
    if (c.merchant != null && categoryId != null) {
      final prefix = c.isTransfer ? 't' : 'm';
      await db
          .into(db.captureRules)
          .insertOnConflictUpdate(
            CaptureRulesCompanion.insert(key: '$prefix:${merchantKey(c.merchant!)}', categoryId: Value(categoryId)),
          );
    }
    if (fundId != null) {
      await db
          .into(db.captureRules)
          .insertOnConflictUpdate(CaptureRulesCompanion.insert(key: 's:${c.sourceKey}', fundAccountId: Value(fundId)));
    }
  }

  Future<void> dismiss(String captureId) => (db.update(
    db.captures,
  )..where((c) => c.id.equals(captureId))).write(const CapturesCompanion(status: Value(CaptureStatus.dismissed)));

  /// 用戶喺待確認改分類 / 賬戶（未入帳）。
  /// 揀咗付款賬戶：同一個來源（例如 Takeout 嘅 AlipayHK）未揀賬戶嘅待確認都一齊用，並記住。
  /// 返回另外更新咗幾多筆。
  Future<int> setFund(Capture capture, String fundId) => db.transaction(() async {
    await update(capture.id, fundId: fundId);
    await db
        .into(db.captureRules)
        .insertOnConflictUpdate(
          CaptureRulesCompanion.insert(key: 's:${capture.sourceKey}', fundAccountId: Value(fundId)),
        );
    return (db.update(db.captures)..where(
          (c) =>
              c.id.equals(capture.id).not() &
              c.sourceKey.equals(capture.sourceKey) &
              c.status.equalsValue(CaptureStatus.pending) &
              c.fundAccountId.isNull(),
        ))
        .write(CapturesCompanion(fundAccountId: Value(fundId)));
  });

  Future<void> update(String captureId, {String? categoryId, String? fundId, int? amount}) =>
      (db.update(db.captures)..where((c) => c.id.equals(captureId))).write(
        CapturesCompanion(
          categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
          fundAccountId: fundId != null ? Value(fundId) : const Value.absent(),
          amount: amount != null ? Value(amount) : const Value.absent(),
        ),
      );
}

EntryKind _kindOf(bool isIncome, bool isTransfer) =>
    isTransfer ? EntryKind.transfer : (isIncome ? EntryKind.income : EntryKind.expense);

/// 所有可揀嘅分類路徑，例如「娛樂 › 課金」，俾 Gemini 揀。
List<String> categoryPaths(List<Account> accounts) {
  final byId = {for (final a in accounts) a.id: a};
  final out = <String>[];
  for (final a in accounts) {
    if (a.isArchived || (a.type != AccountType.expense && a.type != AccountType.income)) continue;
    final parent = a.parentId != null ? byId[a.parentId] : null;
    final prefix = a.type == AccountType.income ? '收入: ' : '';
    out.add(parent != null ? '$prefix${parent.name} › ${a.name}' : '$prefix${a.name}');
  }
  return out;
}

/// 「娛樂 › 課金」→ 對應分類；搵唔到子分類就用主分類。
Account? categoryByPath(String path, List<Account> accounts, AccountType type) {
  final parts = path.replaceFirst(RegExp(r'^收入:\s*'), '').split(RegExp(r'\s*[›>/]\s*'));
  final candidates = accounts.where((a) => a.type == type && !a.isArchived).toList();
  final top = candidates.where((a) => a.parentId == null && a.name == parts.first).firstOrNull;
  if (top == null) {
    // 可能只係子分類名
    return candidates.where((a) => a.name == parts.last).firstOrNull;
  }
  if (parts.length > 1) {
    final child = candidates.where((a) => a.parentId == top.id && a.name == parts[1]).firstOrNull;
    if (child != null) return child;
  }
  return top;
}

/// 八達通截圖每行變做待確認記錄。externalId 用時間、金額、商戶；同一分鐘有兩行一樣（例如幫朋友拍卡）就加序號。
List<(RawCapture, ParsedPayment)> octopusRowsToCaptures(List<OctopusRow> rows) {
  final counts = <String, int>{};
  return [
    for (final r in rows)
      () {
        final t = r.occurredAt;
        String two(int v) => v.toString().padLeft(2, '0');
        final base =
            'o:${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}:'
            '${r.payment.isTransfer ? 't' : (r.payment.isIncome ? 'i' : 'e')}${r.payment.amount}:${merchantKey(r.merchant)}';
        final n = counts[base] = (counts[base] ?? 0) + 1;
        final sign = r.payment.isTransfer || r.payment.isIncome ? '+' : '-';
        return (
          RawCapture(
            source: EntrySource.import,
            sourceKey: octopusScreenshotKey,
            sourceLabel: '八達通',
            externalId: n == 1 ? base : '$base#$n',
            title: r.payment.isTransfer ? '八達通增值' : null,
            body: '${r.merchant} $sign${minorToInput(r.payment.amount)}',
            occurredAt: r.occurredAt,
          ),
          r.payment,
        );
      }(),
  ];
}
