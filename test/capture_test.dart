import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/auto_capture.dart';
import 'package:money_manager/domain/capture.dart';
import 'package:money_manager/domain/gemini.dart';
import 'package:money_manager/domain/ledger.dart';

void main() {
  group('Gemini helpers', () {
    test('bestFlashModel picks the newest stable flash model', () {
      expect(
        bestFlashModel([
          'gemini-2.0-flash',
          'gemini-2.5-flash',
          'gemini-2.5-flash-lite',
          'gemini-2.5-flash-001',
          'gemini-3.0-flash-preview-09-2026',
          'gemini-2.5-pro',
          'gemini-2.5-flash-image',
        ]),
        'gemini-2.5-flash',
      );
      expect(bestFlashModel(['gemini-2.5-pro', 'text-embedding-004']), isNull);
    });

    test('looksLikePayment filters out non-payment notifications', () {
      expect(looksLikePayment('你已用信用卡 xxxx1234 於 759阿信屋 簽賬 HKD 26.80'), isTrue);
      expect(looksLikePayment('Payment of \$58.00 to Gong Cha'), isTrue);
      expect(looksLikePayment('你今晚得唔得閒？'), isFalse);
      expect(looksLikePayment('你有 3 個新訊息'), isFalse);
    });

    test('parseExtraction keeps valid rows and drops unknown ids', () {
      const choices = LedgerChoices(
        funds: [('cash', '現金 (cash)')],
        expenseCategories: [('food', '餐飲')],
        incomeCategories: [('salary', '人工')],
      );
      final txs = parseExtraction({
        'transactions': [
          {
            'source_index': 0,
            'kind': 'expense',
            'amount': 32.0,
            'currency': 'hkd',
            'merchant': '貢茶',
            'datetime': '2026-09-28T20:11:00',
            'category_id': 'food',
            'account_id': 'made-up-id',
          },
          {'kind': 'expense', 'amount': 0, 'currency': 'HKD', 'datetime': '2026-09-28T20:11:00'},
          {'kind': 'opening', 'amount': 10, 'currency': 'HKD', 'datetime': '2026-09-28T20:11:00'},
          {'kind': 'income', 'amount': 5, 'currency': 'HKD', 'datetime': 'yesterday'},
        ],
      }, choices: choices);
      expect(txs, hasLength(1));
      final t = txs.single;
      expect(t.amount, 3200);
      expect(t.currency, 'HKD');
      expect(t.categoryId, 'food');
      expect(t.accountId, isNull); // 唔喺清單嘅 id 唔用
      expect(t.occurredAt, DateTime(2026, 9, 28, 20, 11));
    });
  });

  group('CaptureService', () {
    late AppDatabase db;
    late Ledger ledger;
    late CaptureService capture;
    late String cash, octopus, drink, transport;

    Future<String> category(String name) async => (await (db.select(
      db.accounts,
    )..where((a) => a.name.equals(name) & a.type.equalsValue(AccountType.expense))).getSingle()).id;

    ExtractedTx tx(int amount, DateTime at, {String? cat, String? account, String? merchant}) => ExtractedTx(
      kind: EntryKind.expense,
      amount: amount,
      occurredAt: at,
      categoryId: cat,
      accountId: account,
      merchant: merchant,
    );

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ledger = Ledger(db);
      capture = CaptureService(ledger);
      cash = await ledger.createFundAccount(
        name: '現金',
        type: AccountType.asset,
        subtype: AccountSubtype.cash,
        openingBalance: 100000,
      );
      octopus = await ledger.createFundAccount(
        name: '八達通',
        type: AccountType.asset,
        subtype: AccountSubtype.ewallet,
        openingBalance: 30870,
      );
      drink = await category('飲品');
      transport = await category('交通');
    });

    tearDown(() => db.close());

    test('captured entries wait for confirmation and do not touch balances', () async {
      final r = await capture.ingest([
        CaptureCandidate(
          tx(3200, DateTime(2026, 9, 28, 20, 11), cat: drink, account: octopus, merchant: '貢茶'),
          externalId: 'img:a',
          source: EntrySource.import,
        ),
      ], autoPost: false);
      expect(r.added, 1);
      expect((await ledger.balances())[octopus], 30870);
      expect(await ledger.transactions(), isEmpty);

      final pending = await ledger.transactions(status: EntryStatus.pending);
      expect(pending.single.entry.merchant, '貢茶');
      await ledger.confirmEntry(pending.single.entry.id);
      expect((await ledger.balances())[octopus], 30870 - 3200);
      expect(await ledger.transactions(status: EntryStatus.pending), isEmpty);
    });

    test('auto mode posts straight away', () async {
      await capture.ingest(
        [
          CaptureCandidate(
            tx(930, DateTime(2026, 10, 2, 7, 28), cat: transport),
            externalId: 'n1',
            source: EntrySource.notification,
          ),
        ],
        autoPost: true,
        defaultFundId: octopus,
      );
      expect((await ledger.balances())[octopus], 30870 - 930);
    });

    test('same external id is never imported twice, even after the user dismissed it', () async {
      final c = CaptureCandidate(
        tx(490, DateTime(2026, 9, 28, 21, 19), cat: transport, account: octopus),
        externalId: 'img:row',
        source: EntrySource.import,
      );
      expect((await capture.ingest([c], autoPost: false)).added, 1);
      final id = (await ledger.transactions(status: EntryStatus.pending)).single.entry.id;
      await ledger.deleteEntry(id);
      final again = await capture.ingest([c], autoPost: false);
      expect(again.added, 0);
      expect(again.duplicates, 1);
    });

    test('a manual entry with the same amount and time blocks the capture', () async {
      await ledger.saveEntry(
        EntryDraft(
          kind: EntryKind.expense,
          amount: 3200,
          fromAccountId: octopus,
          toAccountId: drink,
          occurredAt: DateTime(2026, 9, 28, 20, 5),
        ),
      );
      final r = await capture.ingest([
        CaptureCandidate(
          tx(3200, DateTime(2026, 9, 28, 20, 11), cat: drink, account: octopus),
          externalId: 'img:b',
          source: EntrySource.import,
        ),
      ], autoPost: false);
      expect(r.duplicates, 1);
    });

    test('two identical fares from the same screenshot are both kept', () async {
      final r = await capture.ingest([
        CaptureCandidate(
          tx(930, DateTime(2026, 10, 2, 7, 28), cat: transport, account: octopus),
          externalId: 'img:1',
          source: EntrySource.import,
        ),
        CaptureCandidate(
          tx(930, DateTime(2026, 10, 2, 7, 35), cat: transport, account: octopus),
          externalId: 'img:2',
          source: EntrySource.import,
        ),
      ], autoPost: false);
      expect(r.added, 2);
    });

    test('missing category falls back to 其他 and missing account to the fallback', () async {
      await capture.ingest([
        CaptureCandidate(
          tx(2680, DateTime(2026, 9, 28, 20, 8), merchant: '759 阿信屋'),
          externalId: 'img:c',
          source: EntrySource.import,
          fallbackAccountId: octopus,
        ),
      ], autoPost: true);
      final t = (await ledger.transactions()).single;
      expect(t.fund.id, octopus);
      expect(t.category.name, '其他');
    });

    test('Octopus top-up becomes a transfer into the account', () async {
      await capture.ingest(
        [
          CaptureCandidate(
            ExtractedTx(
              kind: EntryKind.transfer,
              amount: 30000,
              occurredAt: DateTime(2026, 9, 28, 21, 17),
              merchant: '7-Eleven',
            ),
            externalId: 'img:topup',
            source: EntrySource.import,
            fallbackAccountId: octopus,
          ),
        ],
        autoPost: true,
        defaultFundId: cash,
      );
      final bal = await ledger.balances();
      expect(bal[octopus], 30870 + 30000);
      expect(bal[cash], 100000 - 30000);
    });

    test('screenshot row key ignores seconds so overlapping screenshots match', () {
      final a = tx(930, DateTime(2026, 10, 2, 7, 28, 0), merchant: '九巴');
      final b = tx(930, DateTime(2026, 10, 2, 7, 28, 59), merchant: '九巴');
      expect(screenshotRowKey(a), screenshotRowKey(b));
    });
  });
}
