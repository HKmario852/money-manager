import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/ledger.dart';
import 'package:money_manager/domain/money.dart';

void main() {
  late AppDatabase db;
  late Ledger ledger;
  late String cash, bank, card, food, salary, lunch;

  Future<String> categoryNamed(String name, AccountType type) async {
    final a = await (db.select(db.accounts)..where((a) => a.name.equals(name) & a.type.equalsValue(type))).getSingle();
    return a.id;
  }

  /// 所有分錄行加埋一定係 0（資產負債表平衡）。
  Future<void> expectBalanced() async {
    final total = (await ledger.balances()).values.fold(0, (s, v) => s + v);
    expect(total, 0);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = Ledger(db);
    cash = await ledger.createFundAccount(
      name: '現金',
      type: AccountType.asset,
      subtype: AccountSubtype.cash,
      openingBalance: 100000,
    );
    bank = await ledger.createFundAccount(
      name: '銀行',
      type: AccountType.asset,
      subtype: AccountSubtype.bank,
      openingBalance: 1000000,
    );
    card = await ledger.createFundAccount(
      name: '信用卡',
      type: AccountType.liability,
      subtype: AccountSubtype.creditCard,
      creditLimit: 5000000,
      openingBalance: 20000,
    );
    food = await categoryNamed('餐飲', AccountType.expense);
    lunch = await categoryNamed('午餐', AccountType.expense);
    salary = await categoryNamed('人工', AccountType.income);
  });

  tearDown(() => db.close());

  test('seed 有預設分類同系統賬戶', () async {
    final all = await db.select(db.accounts).get();
    expect(all.where((a) => a.isSystem), hasLength(2));
    expect(all.where((a) => a.type == AccountType.expense && a.parentId == null).length, 9);
  });

  test('期初結餘：資產正數，負債負數', () async {
    final bal = await ledger.balances();
    expect(bal[cash], 100000);
    expect(bal[card], -20000);
    expect(await ledger.netWorth(), 100000 + 1000000 - 20000);
    await expectBalanced();
  });

  test('支出、收入、轉賬寫成平衡分錄', () async {
    final now = DateTime(2026, 10, 3, 12);
    await ledger.saveEntry(
      EntryDraft(kind: EntryKind.expense, amount: 4500, fromAccountId: cash, toAccountId: lunch, occurredAt: now),
    );
    await ledger.saveEntry(
      EntryDraft(kind: EntryKind.expense, amount: 30000, fromAccountId: card, toAccountId: food, occurredAt: now),
    );
    await ledger.saveEntry(
      EntryDraft(kind: EntryKind.income, amount: 2000000, fromAccountId: salary, toAccountId: bank, occurredAt: now),
    );
    await ledger.saveEntry(
      EntryDraft(kind: EntryKind.transfer, amount: 50000, fromAccountId: bank, toAccountId: cash, occurredAt: now),
    );
    // 用銀行找卡數
    await ledger.saveEntry(
      EntryDraft(kind: EntryKind.transfer, amount: 50000, fromAccountId: bank, toAccountId: card, occurredAt: now),
    );

    final bal = await ledger.balances();
    expect(bal[cash], 100000 - 4500 + 50000);
    expect(bal[bank], 1000000 + 2000000 - 50000 - 50000);
    expect(bal[card], -20000 - 30000 + 50000);
    expect(bal[lunch], 4500);
    expect(bal[salary], -2000000);
    await expectBalanced();

    final s = await ledger.summary(DateTime(2026, 10), DateTime(2026, 11));
    expect(s.expense, 34500);
    expect(s.income, 2000000);
    // 轉賬唔計入收支
    expect(s.net, 2000000 - 34500);
  });

  test('拒絕類型唔夾嘅交易', () async {
    final now = DateTime.now();
    expect(
      () => ledger.saveEntry(
        EntryDraft(kind: EntryKind.expense, amount: 100, fromAccountId: salary, toAccountId: food, occurredAt: now),
      ),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => ledger.saveEntry(
        EntryDraft(kind: EntryKind.transfer, amount: 100, fromAccountId: cash, toAccountId: food, occurredAt: now),
      ),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => ledger.saveEntry(
        EntryDraft(kind: EntryKind.expense, amount: 0, fromAccountId: cash, toAccountId: food, occurredAt: now),
      ),
      throwsA(isA<LedgerException>()),
    );
  });

  test('唔平衡嘅分錄寫唔入', () async {
    expect(() => ledger.postLines(EntryKind.adjustment, [(cash, 100), (bank, -99)]), throwsA(isA<LedgerException>()));
    expect(() => ledger.postLines(EntryKind.adjustment, [(cash, 0)]), throwsA(isA<LedgerException>()));
    expect(await db.journalEntries.count().getSingle(), 3); // 只有三筆期初
  });

  test('編輯同刪除交易', () async {
    final now = DateTime(2026, 10, 3);
    final tag = await ledger.createTag('#去旅行');
    final id = await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: 1000,
        fromAccountId: cash,
        toAccountId: lunch,
        occurredAt: now,
        tagIds: [tag],
      ),
    );
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: 2500,
        fromAccountId: bank,
        toAccountId: lunch,
        occurredAt: now,
        note: '改咗',
      ),
      entryId: id,
    );
    var bal = await ledger.balances();
    expect(bal[cash], 100000);
    expect(bal[bank], 1000000 - 2500);
    final tx = await ledger.transaction(id);
    expect(tx!.amount, 2500);
    expect(tx.entry.note, '改咗');
    expect(tx.tags, isEmpty);

    await ledger.deleteEntry(id);
    bal = await ledger.balances();
    expect(bal[bank], 1000000);
    expect(await ledger.transaction(id), isNull);
    await expectBalanced();
  });

  test('交易篩選：主分類包埋子分類、Tag、賬戶', () async {
    final now = DateTime(2026, 10, 3);
    final trip = await ledger.createTag('去旅行');
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: 1000,
        fromAccountId: cash,
        toAccountId: lunch,
        occurredAt: now,
        tagIds: [trip],
      ),
    );
    await ledger.saveEntry(
      EntryDraft(kind: EntryKind.expense, amount: 2000, fromAccountId: bank, toAccountId: food, occurredAt: now),
    );
    expect(await ledger.transactions(categoryId: food), hasLength(2));
    expect(await ledger.transactions(tagId: trip), hasLength(1));
    expect(await ledger.transactions(accountId: bank), hasLength(1));
    // 預設唔顯示期初結餘
    expect(await ledger.transactions(), hasLength(2));
  });

  test('結餘調整', () async {
    await ledger.adjustBalance(cash, 80000);
    await ledger.adjustBalance(card, 25000);
    final bal = await ledger.balances();
    expect(bal[cash], 80000);
    expect(bal[card], -25000);
    await expectBalanced();
  });

  test('有交易嘅賬戶只會封存', () async {
    final empty = await ledger.createFundAccount(name: '八達通', type: AccountType.asset, subtype: AccountSubtype.ewallet);
    expect(await ledger.archiveOrDelete(empty), isTrue);
    expect(await ledger.archiveOrDelete(cash), isFalse);
    final c = await (db.select(db.accounts)..where((a) => a.id.equals(cash))).getSingle();
    expect(c.isArchived, isTrue);
  });

  test('分類最多兩層', () async {
    expect(
      () => ledger.createCategory(name: 'x', type: AccountType.expense, parentId: lunch),
      throwsA(isA<LedgerException>()),
    );
    final id = await ledger.createCategory(name: '宵夜', type: AccountType.expense, parentId: food);
    expect(id, isNotEmpty);
  });

  test('模板一撳記賬', () async {
    await ledger.saveTemplate(
      '午餐',
      EntryDraft(
        kind: EntryKind.expense,
        amount: 6000,
        fromAccountId: cash,
        toAccountId: lunch,
        occurredAt: DateTime.now(),
      ),
    );
    final t = await db.select(db.templates).getSingle();
    await ledger.useTemplate(t);
    expect((await ledger.balances())[cash], 100000 - 6000);
  });

  test('Tag 改名撞名會合併', () async {
    final a = await ledger.createTag('旅行');
    final b = await ledger.createTag('去旅行');
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: 100,
        fromAccountId: cash,
        toAccountId: lunch,
        occurredAt: DateTime.now(),
        tagIds: [a],
      ),
    );
    await ledger.renameTag(a, '去旅行');
    expect(await db.select(db.tags).get(), hasLength(1));
    expect(await ledger.transactions(tagId: b), hasLength(1));
  });

  test('近幾個月收支', () async {
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: 1000,
        fromAccountId: cash,
        toAccountId: lunch,
        occurredAt: DateTime(2026, 9, 15),
      ),
    );
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: 3000,
        fromAccountId: cash,
        toAccountId: lunch,
        occurredAt: DateTime(2026, 10, 2),
      ),
    );
    final periods = await ledger.recentPeriods(3, 1, now: DateTime(2026, 10, 3));
    expect(periods.map((p) => p.start.month), [8, 9, 10]);
    expect(periods.map((p) => p.expense), [0, 1000, 3000]);
  });

  group('money', () {
    test('計數機輸入', () {
      expect(evaluateAmount('12.5+30-3'), 3950);
      expect(evaluateAmount('0.05'), 5);
      expect(evaluateAmount('1.234'), isNull);
      expect(evaluateAmount(''), isNull);
      expect(parseMinor('12.'), 1200);
      expect(minorToInput(1250), '12.5');
      expect(minorToInput(1205), '12.05');
      expect(formatMoney(123456), '\$1,234.56');
      expect(formatMoney(-500), '-\$5.00');
    });

    test('每月起始日', () {
      final (s, e) = periodRange(DateTime(2026, 10, 3), 25);
      expect(s, DateTime(2026, 9, 25));
      expect(e, DateTime(2026, 10, 25));
      final (s2, _) = periodRange(DateTime(2026, 1, 3), 1);
      expect(s2, DateTime(2026, 1, 1));
    });
  });
}
