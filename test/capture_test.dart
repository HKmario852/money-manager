import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/capture/capture_service.dart';
import 'package:money_manager/domain/capture/gemini.dart';
import 'package:money_manager/domain/capture/parser.dart';
import 'package:money_manager/domain/capture/sources.dart';
import 'package:money_manager/domain/ledger.dart';

void main() {
  group('規則解析', () {
    test('Google Play 收據讀總計同項目', () {
      final r = parseByRules(
        sourceKey: 'googleplay-noreply@google.com',
        title: '您的 Google Play 訂單收據',
        body: '項目\nGenshin Impact: 60 創世結晶\n價格 HK\$8.00\n總計：HK\$8.00 /month',
      );
      expect(r.isPayment, true);
      expect(r.payment!.amount, 800);
      expect(r.payment!.merchant, 'Genshin Impact: 60 創世結晶');
      expect(r.payment!.categoryHint, '娛樂 › 課金');
    });

    test('推廣通知唔當付款', () {
      final r = parseByRules(sourceKey: 'hk.alipay.wallet', body: '限時優惠！消費滿 \$100 即減 \$20');
      expect(r.isPayment, false);
    });

    test('付款通知去咗餘額先讀金額', () {
      final r = parseByRules(
        sourceKey: 'hk.alipay.wallet',
        title: '付款成功',
        body: '你已於 MTR 付款 HK\$12.50，可用餘額 HK\$1,234.00',
      );
      expect(r.isPayment, true);
      expect(r.payment!.amount, 1250);
      expect(r.payment!.merchant, 'MTR');
      expect(r.payment!.categoryHint, '交通 › 港鐵');
    });

    test('多過一個金額交俾 Gemini', () {
      final r = parseByRules(sourceKey: 'hk.alipay.wallet', body: '付款 HK\$50.00（原價 HK\$80.00）');
      expect(r.isPayment, isNull);
    });

    test('冇金額 = 唔係付款；有金額冇付款字眼 = 唔肯定', () {
      expect(parseByRules(sourceKey: 'x', body: '你有一個新訊息').isPayment, false);
      expect(parseByRules(sourceKey: 'x', body: 'HK\$30.00 九巴').isPayment, isNull);
    });
  });

  test('Gemini 答案轉換', () {
    final p = decodeGeminiAnswer(
      '{"is_payment":true,"direction":"expense","amount":45.5,"currency":"hkd","merchant":"大家樂","category":"餐飲 › 午餐"}',
    )!;
    expect(p.amount, 4550);
    expect(p.currency, 'HKD');
    expect(p.merchant, '大家樂');
    expect(p.categoryHint, '餐飲 › 午餐');
    expect(decodeGeminiAnswer('{"is_payment":false}'), isNull);
    expect(decodeGeminiAnswer('not json'), isNull);
  });

  test('八達通截圖 JSON 轉換', () {
    final rows = decodeOctopusRows('''
{"is_octopus_history":true,"rows":[
 {"datetime":"2026-10-02 11:43","merchant":"九巴 / 龍運","amount":0.1,"direction":"spend","category":""},
 {"datetime":"2026-09-28 21:17","merchant":"7-Eleven","amount":300,"direction":"topup"},
 {"datetime":"2026-09-28 20:11","merchant":"貢茶","amount":32.0,"direction":"spend","category":""},
 {"datetime":"bad","merchant":"x","amount":1,"direction":"spend"}
]}''')!;
    expect(rows, hasLength(3));
    expect(rows[0].occurredAt, DateTime(2026, 10, 2, 11, 43));
    expect(rows[0].payment.amount, 10);
    expect(rows[0].payment.categoryHint, '交通 › 巴士');
    expect(rows[1].payment.isTransfer, true);
    expect(rows[1].payment.amount, 30000);
    expect(rows[2].payment.categoryHint, '餐飲 › 飲品');
    expect(decodeOctopusRows('{"is_octopus_history":false,"rows":[]}'), isNull);
  });

  test('八達通卡內數值轉港幣', () {
    expect(octopusRawToMinor(3587), 30870); // $308.7
    expect(octopusRawToMinor(500), 0);
    expect(octopusRawToMinor(450), -500);
  });

  group('CaptureService', () {
    late AppDatabase db;
    late Ledger ledger;
    late CaptureService service;
    late String cash, alipay, octopus;

    Future<String> category(String name) async =>
        (await (db.select(db.accounts)..where((a) => a.name.equals(name))).getSingle()).id;

    RawCapture notification(String id, String body, DateTime at, {String pkg = 'hk.alipay.wallet'}) => RawCapture(
      source: EntrySource.notification,
      sourceKey: pkg,
      sourceLabel: knownSources[pkg],
      externalId: 'n:$id',
      body: body,
      occurredAt: at,
    );

    Future<Capture> capture(String externalId) =>
        (db.select(db.captures)..where((c) => c.externalId.equals(externalId))).getSingle();

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ledger = Ledger(db);
      service = CaptureService(ledger);
      cash = await ledger.createFundAccount(name: '現金', type: AccountType.asset, subtype: AccountSubtype.cash);
      alipay = await ledger.createFundAccount(
        name: 'AlipayHK',
        type: AccountType.asset,
        subtype: AccountSubtype.ewallet,
        openingBalance: 50000,
      );
      octopus = await ledger.createFundAccount(
        name: '我張卡',
        type: AccountType.asset,
        subtype: AccountSubtype.ewallet,
        icon: 'octopus',
        openingBalance: 10000,
      );
    });

    tearDown(() => db.close());

    test('通知 → 待確認，建議分類同賬戶；確認後入帳同記住', () async {
      final at = DateTime(2026, 10, 3, 9);
      final out = await service.ingest(notification('1', '你已於 MTR 付款 HK\$12.50', at));
      expect(out, IngestOutcome.added);
      final c = await capture('n:1');
      expect(c.status, CaptureStatus.pending);
      expect(c.amount, 1250);
      expect(c.categoryId, await category('港鐵'));
      expect(c.fundAccountId, alipay);

      // 用戶改去「巴士」再入帳
      final bus = await category('巴士');
      await service.update(c.id, categoryId: bus);
      final entryId = await service.confirm(await capture('n:1'));
      final tx = (await ledger.transaction(entryId))!;
      expect(tx.amount, 1250);
      expect(tx.from.id, alipay);
      expect(tx.to.id, bus);
      expect(tx.entry.source, EntrySource.notification);
      expect((await capture('n:1')).status, CaptureStatus.confirmed);

      // 同一個商戶下次用返巴士
      await service.ingest(notification('2', '你已於 MTR 付款 HK\$9.00', at.add(const Duration(hours: 3))));
      expect((await capture('n:2')).categoryId, bus);
    });

    test('同一個通知唔會入兩次', () async {
      final raw = notification('1', '你已於 MTR 付款 HK\$12.50', DateTime(2026, 10, 3, 9));
      expect(await service.ingest(raw), IngestOutcome.added);
      expect(await service.ingest(raw), IngestOutcome.alreadySeen);
    });

    test('唔同來源同一筆錢當重複；手動記咗都當重複', () async {
      final at = DateTime(2026, 10, 3, 20);
      await service.ingest(notification('1', '付款成功 HK\$8.00 Google Play', at, pkg: 'com.android.vending'));
      final email = RawCapture(
        source: EntrySource.email,
        sourceKey: 'googleplay-noreply@google.com',
        externalId: 'g:abc',
        title: 'Google Play 訂單收據',
        body: '總計：HK\$8.00',
        occurredAt: at.add(const Duration(minutes: 2)),
      );
      expect(await service.ingest(email), IngestOutcome.duplicate);

      final lunch = await category('午餐');
      await ledger.saveEntry(
        EntryDraft(kind: EntryKind.expense, amount: 4500, fromAccountId: cash, toAccountId: lunch, occurredAt: at),
      );
      final out = await service.ingest(notification('2', '你已於 大家樂 付款 HK\$45.00', at.add(const Duration(minutes: 5))));
      expect(out, IngestOutcome.duplicate);
    });

    test('自動入帳：分類同賬戶都有先會直接入帳', () async {
      final at = DateTime(2026, 10, 3, 9);
      expect(
        await service.ingest(notification('1', '你已於 MTR 付款 HK\$12.50', at), autoConfirm: true),
        IngestOutcome.autoConfirmed,
      );
      // 未知商戶冇分類 → 留喺待確認
      expect(
        await service.ingest(notification('2', '你已於 某商店 付款 HK\$30.00', at), autoConfirm: true),
        IngestOutcome.added,
      );
    });

    test('冇 Gemini 時唔肯定嘅通知留低等用戶睇', () async {
      final out = await service.ingest(notification('1', 'HK\$30.00 九巴', DateTime(2026, 10, 3)));
      expect(out, IngestOutcome.needsGemini);
      expect((await capture('n:1')).amount, isNull);
    });

    test('八達通截圖：消費入八達通，增值係由現金轉入，重複匯入會略過', () async {
      final rows = decodeOctopusRows('''
{"is_octopus_history":true,"rows":[
 {"datetime":"2026-09-28 21:17","merchant":"7-Eleven","amount":300,"direction":"topup"},
 {"datetime":"2026-10-02 07:28","merchant":"九巴 / 龍運","amount":9.3,"direction":"spend"},
 {"datetime":"2026-10-02 07:28","merchant":"九巴 / 龍運","amount":9.3,"direction":"spend"}
]}''')!;
      final items = octopusRowsToCaptures(rows);
      expect(items.map((e) => e.$1.externalId).toSet(), hasLength(3));
      for (final (raw, p) in items) {
        expect(await service.ingestParsed(raw, p), IngestOutcome.added);
      }
      final pending = await (db.select(db.captures)..where((c) => c.sourceKey.equals(octopusScreenshotKey))).get();
      final topUp = pending.firstWhere((c) => c.isTransfer);
      expect(topUp.fundAccountId, octopus);
      expect(topUp.categoryId, cash);
      final bus = pending.firstWhere((c) => !c.isTransfer);
      expect(bus.fundAccountId, octopus);
      expect(bus.categoryId, await category('巴士'));

      final id = await service.confirm(topUp);
      final tx = (await ledger.transaction(id))!;
      expect(tx.entry.kind, EntryKind.transfer);
      expect(tx.from.id, cash);
      expect(tx.to.id, octopus);
      expect((await ledger.balances())[octopus], 10000 + 30000);

      // 同一張截圖再匯入
      for (final (raw, p) in octopusRowsToCaptures(rows)) {
        expect(await service.ingestParsed(raw, p), IngestOutcome.alreadySeen);
      }
    });
  });
}
