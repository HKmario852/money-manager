import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/capture/capture_service.dart';
import 'package:money_manager/domain/capture/parser.dart';
import 'package:money_manager/domain/capture/takeout.dart';
import 'package:money_manager/domain/ledger.dart';

// 假資料，格式照 Google Play 收據電郵（每行 \r\n 結尾）
String receipt({
  String order = 'GPA.3333-1234-5678-90123',
  String item = '半月青輝石組合包 (蔚藍檔案)',
  String price = r'HK$23.00',
  String intro = '你在 Google Play 向 Example Games 購買了商品。',
}) => [
  'Google Play',
  '',
  intro,
  '',
  '訂單編號：$order',
  '訂單日期：2026年9月12日 上午12:07:55 [HKT]',
  '商品 價格',
  '$item $price',
  '小計：$price',
  '總計：$price（含稅）',
  '付款方法：',
  'AlipayHK：852-12****34',
  '',
  '© 2026 Google | 新加坡某某大道 1 號',
].join('\r\n');

RawCapture email(String id, String body, DateTime at, {String subject = '你的 Google Play 訂單收據'}) => RawCapture(
  source: EntrySource.email,
  sourceKey: 'googleplay-noreply@google.com',
  sourceLabel: 'Google Play',
  externalId: 'g:$id',
  title: subject,
  body: body,
  occurredAt: at,
);

void main() {
  test('讀「商品 價格」下面嗰行，唔係「購買了商品。」', () {
    final r = readPlayReceipt(receipt());
    expect(r.item, '半月青輝石組合包 (蔚藍檔案)');
    expect(r.itemLine, r'半月青輝石組合包 (蔚藍檔案) HK$23.00');
    expect(r.orderId, 'GPA.3333-1234-5678-90123');
    expect(r.paymentMethod, 'AlipayHK');

    final rule = parseByRules(sourceKey: 'googleplay-noreply@google.com', title: '收據', body: receipt());
    expect(rule.payment!.merchant, '半月青輝石組合包 (蔚藍檔案)');
    expect(rule.payment!.amount, 2300);
    expect(rule.payment!.categoryHint, '娛樂 › 課金');
  });

  test('續訂收據：訂單編號有 ..N，分類係訂閱', () {
    final text = receipt(
      order: 'GPA.3333-1234-5678-90123..2',
      item: 'YouTube Premium (YouTube)',
      price: r'HK$78.00/月',
      intro: '你的訂閱已續訂，系統已向你收費。',
    );
    final r = readPlayReceipt(text);
    expect(r.item, 'YouTube Premium (YouTube)');
    expect(r.orderId, 'GPA.3333-1234-5678-90123..2');
    final rule = parseByRules(sourceKey: 'googleplay-noreply@google.com', body: text);
    expect(rule.payment!.merchant, 'YouTube Premium (YouTube)');
    expect(rule.payment!.categoryHint, '娛樂 › 訂閱');
  });

  test('付款方法同一行；冇表頭但有「商品：」', () {
    final r = readPlayReceipt('商品：月卡 (明日方舟)\n總計：HK\$38.00\n付款方法：Mastercard-1234');
    expect(r.item, '月卡 (明日方舟)');
    expect(r.paymentMethod, 'Mastercard');
    expect(readPlayReceipt('你購買了商品。\n總計：HK\$8.00').item, isNull);
  });

  test('冇金額嘅 Play 電郵唔係付款', () {
    final r = parseByRules(
      sourceKey: 'googleplay-noreply@google.com',
      title: '你的 Google One 訂閱將被取消',
      body: '你的 Google One 訂閱將於 2026年10月30日 取消。',
    );
    expect(r.isPayment, false);
  });

  test('續訂收據同 Takeout 差 24 小時都靠訂單編號認到', () {
    final text = receipt(order: 'SOP.3333-1234-5678-90123..1', item: 'Google One (Google One)', price: r'HK$40.00');
    expect(readPlayReceipt(text.replaceAll('訂單編號', '訂單號碼')).orderId, 'SOP.3333-1234-5678-90123..1');
  });

  group('入待確認', () {
    late AppDatabase db;
    late Ledger ledger;
    late CaptureService service;
    late String alipay;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ledger = Ledger(db);
      service = CaptureService(ledger);
      alipay = await ledger.createFundAccount(name: '支付寶', type: AccountType.asset, subtype: AccountSubtype.ewallet);
    });

    tearDown(() => db.close());

    Future<Capture> byExternal(String id) =>
        (db.select(db.captures)..where((c) => c.externalId.equals(id))).getSingle();

    test('收據同 Takeout 用同一個付款方法 key 同訂單編號', () async {
      // 之前揀過 Takeout AlipayHK 嘅賬戶
      await db
          .into(db.captureRules)
          .insert(CaptureRulesCompanion.insert(key: 's:${playSourceKey('AlipayHK')}', fundAccountId: Value(alipay)));
      final at = DateTime(2026, 9, 12, 0, 7);
      expect(await service.ingest(email('1', receipt(), at)), IngestOutcome.added);
      final c = await byExternal('takeout:GPA.3333-1234-5678-90123');
      expect(c.merchant, '半月青輝石組合包 (蔚藍檔案)');
      expect(c.sourceKey, 'google-takeout:alipayhk');
      expect(c.sourceLabel, 'AlipayHK');
      expect(c.body, r'半月青輝石組合包 (蔚藍檔案) HK$23.00');
      expect(c.fundAccountId, alipay);

      // 之後匯入 Takeout：同一張單唔會再入
      final (raw, p) = takeoutToCaptures([
        PlayPurchase(
          id: 'GPA.3333-1234-5678-90123',
          title: '半月青輝石組合包 (蔚藍檔案)',
          amount: 2300,
          currency: 'HKD',
          at: at,
          paymentMethod: 'AlipayHK',
        ),
      ]).single;
      expect(await service.ingestParsed(raw, p, parsedBy: ParsedBy.rule), IngestOutcome.alreadySeen);
      // 同一封電郵再攞多次都唔會重複
      expect(await service.ingest(email('1', receipt(), at)), IngestOutcome.alreadySeen);
    });

    test('修正舊版讀錯嘅收據；Takeout 有同一張單就用 Takeout 嗰筆', () async {
      final at = DateTime(2026, 9, 12, 0, 7);
      Future<void> oldStyle(String id, String body) => db
          .into(db.captures)
          .insert(
            CapturesCompanion.insert(
              source: EntrySource.email,
              sourceKey: 'googleplay-noreply@google.com',
              sourceLabel: const Value('Google Play'),
              externalId: 'g:$id',
              title: const Value('你的 Google Play 訂單收據'),
              body: body,
              occurredAt: at,
              amount: const Value(2300),
              currency: const Value('HKD'),
              merchant: const Value('。'),
            ),
          );
      await oldStyle('1', receipt());
      await oldStyle('2', receipt(order: 'GPA.9999-1234-5678-90123', item: '月卡 (明日方舟)', price: r'HK$38.00'));
      // 第二張單 Takeout 都有，但當咗重複
      final (raw, p) = takeoutToCaptures([
        PlayPurchase(
          id: 'GPA.9999-1234-5678-90123',
          title: '月卡 (明日方舟)',
          amount: 3800,
          currency: 'HKD',
          at: at,
          paymentMethod: 'AlipayHK',
        ),
      ]).single;
      await service.ingestParsed(raw, p, parsedBy: ParsedBy.rule);
      await (db.update(db.captures)..where((c) => c.externalId.equals('takeout:GPA.9999-1234-5678-90123'))).write(
        const CapturesCompanion(status: Value(CaptureStatus.duplicate)),
      );

      expect(await service.repairPlayReceipts(), 2);
      final first = await byExternal('takeout:GPA.3333-1234-5678-90123');
      expect(first.merchant, '半月青輝石組合包 (蔚藍檔案)');
      expect(first.sourceKey, 'google-takeout:alipayhk');
      expect(first.status, CaptureStatus.pending);
      expect((await byExternal('g:2')).status, CaptureStatus.duplicate);
      expect((await byExternal('takeout:GPA.9999-1234-5678-90123')).status, CaptureStatus.pending);

      // 舊版本入咗嘅取消訂閱通知
      await db
          .into(db.captures)
          .insert(
            CapturesCompanion.insert(
              source: EntrySource.email,
              sourceKey: 'googleplay-noreply@google.com',
              externalId: 'g:3',
              title: const Value('你的 Google One 訂閱將被取消'),
              body: '你的 Google One 訂閱將於 2026年10月30日 取消。',
              occurredAt: at,
            ),
          );
      expect(await service.repairPlayReceipts(), 1);
      expect((await byExternal('g:3')).status, CaptureStatus.dismissed);

      // 再跑一次冇嘢要改
      expect(await service.repairPlayReceipts(), 0);
    });
  });
}
