import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/capture/capture_service.dart';
import 'package:money_manager/domain/capture/takeout.dart';
import 'package:money_manager/domain/ledger.dart';

// 假資料，格式照 Takeout「Google Play 商店」
final orderHistory = jsonEncode([
  {
    'orderHistory': {
      'orderId': 'GPA.1111-2222-3333-44444',
      'creationTime': '2026-09-28T12:30:00.000Z',
      'totalPrice': r'HK$78.00',
      'lineItem': [
        {
          'doc': {'title': 'Genshin Impact: 300 創世結晶', 'documentType': 'In App Item'},
        },
      ],
    },
  },
  {
    'orderHistory': {
      'orderId': 'GPA.5555-6666-7777-88888',
      'creationTime': '2026-08-01T03:00:00.000Z',
      'totalPrice': r'HK$0.00',
      'lineItem': [
        {
          'doc': {'title': '免費 App'},
        },
      ],
    },
  },
  {
    'orderHistory': {
      'orderId': 'GPA.9999-0000-1111-22222',
      'creationTime': '2024-01-05T10:00:00.000Z',
      'totalPrice': r'US$4.99',
      'lineItem': [
        {
          'doc': {'title': 'Old Game'},
        },
      ],
    },
  },
]);

final purchaseHistory = jsonEncode([
  {
    'purchaseHistory': {
      'invoicePrice': r'HK$1,234.50',
      'purchaseTime': '2026-09-01T00:00:00.000Z',
      'doc': {'title': 'YouTube Premium'},
    },
  },
]);

void main() {
  test('價錢解析', () {
    expect(parsePlayPrice(r'HK$8.00'), (amount: 800, currency: 'HKD'));
    expect(parsePlayPrice(r'HK$1,234.50'), (amount: 123450, currency: 'HKD'));
    expect(parsePlayPrice(r'US$0.99'), (amount: 99, currency: 'USD'));
    expect(parsePlayPrice('8.00 HKD'), (amount: 800, currency: 'HKD'));
    expect(parsePlayPrice('2,49 €'), (amount: 249, currency: 'EUR'));
    expect(parsePlayPrice(r'HK$1,234'), (amount: 123400, currency: 'HKD'));
    expect(parsePlayPrice('free'), isNull);
  });

  test('Order History：讀訂單編號，略過免費', () {
    final r = parseTakeoutJson(orderHistory)!;
    expect(r.hasOrderIds, true);
    expect(r.purchases, hasLength(2));
    final p = r.purchases.first;
    expect(p.id, 'GPA.1111-2222-3333-44444');
    expect(p.title, 'Genshin Impact: 300 創世結晶');
    expect(p.amount, 7800);
    expect(p.at, DateTime.utc(2026, 9, 28, 12, 30).toLocal());
    expect(r.purchases.last.currency, 'USD');
  });

  test('Purchase History 同其他 JSON', () {
    final r = parseTakeoutJson(purchaseHistory)!;
    expect(r.hasOrderIds, false);
    expect(r.purchases.single.amount, 123450);
    expect(r.purchases.single.id, contains('youtubepremium'));
    expect(parseTakeoutJson('[{"installs":{}}]'), isNull);
    expect(parseTakeoutJson('{"orderHistory":{}}'), isNull);
    expect(parseTakeoutJson('not json'), isNull);
  });

  test('zip：唔理檔名，優先用 Order History', () async {
    final dir = await Directory.systemTemp.createTemp('takeout');
    addTearDown(() => dir.delete(recursive: true));
    final zip = '${dir.path}/takeout.zip';
    final encoder = ZipFileEncoder()..create(zip);
    encoder.addArchiveFile(ArchiveFile.string('Takeout/Google Play 商店/購買記錄.json', purchaseHistory));
    encoder.addArchiveFile(ArchiveFile.string('Takeout/Google Play 商店/訂單記錄.json', orderHistory));
    encoder.addArchiveFile(ArchiveFile.string('Takeout/Google Play 商店/裝置.json', '[{"device":{}}]'));
    await encoder.close();
    final purchases = await readTakeout(zip);
    expect(purchases.map((p) => p.id), contains('GPA.1111-2222-3333-44444'));

    final empty = '${dir.path}/empty.zip';
    final e = ZipFileEncoder()..create(empty);
    e.addArchiveFile(ArchiveFile.string('Takeout/Chrome/History.json', '{}'));
    await e.close();
    expect(readTakeout(empty), throwsA(isA<TakeoutException>()));
  });

  group('入待確認', () {
    late AppDatabase db;
    late CaptureService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final ledger = Ledger(db);
      service = CaptureService(ledger);
      await ledger.createFundAccount(name: '信用卡', type: AccountType.liability, subtype: AccountSubtype.creditCard);
    });

    tearDown(() => db.close());

    test('舊記錄可以略過；Gmail 收據記過嘅當重複；再匯入唔會重複', () async {
      final purchases = parseTakeoutJson(orderHistory)!.purchases;
      final items = takeoutToCaptures(purchases, since: DateTime(2025));
      expect(items, hasLength(1));
      final (raw, payment) = items.single;
      expect(payment.categoryHint, '娛樂 › 課金');

      // Gmail 收據遲幾分鐘到
      final email = RawCapture(
        source: EntrySource.email,
        sourceKey: 'googleplay-noreply@google.com',
        externalId: 'g:1',
        title: 'Google Play 訂單收據',
        body: r'總計：HK$78.00',
        occurredAt: raw.occurredAt.add(const Duration(minutes: 3)),
      );
      expect(await service.ingest(email), IngestOutcome.added);
      expect(await service.ingestParsed(raw, payment, parsedBy: ParsedBy.rule), IngestOutcome.duplicate);
      expect(await service.ingestParsed(raw, payment, parsedBy: ParsedBy.rule), IngestOutcome.alreadySeen);

      final all = takeoutToCaptures(purchases);
      expect(all, hasLength(2));
      expect(await service.ingestParsed(all.last.$1, all.last.$2, parsedBy: ParsedBy.rule), IngestOutcome.added);
    });
  });
}
