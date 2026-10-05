import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/capture/capture_service.dart';
import 'package:money_manager/domain/capture/taobao.dart';
import 'package:money_manager/domain/ledger.dart';
import 'package:money_manager/domain/place_spending.dart';
import 'package:money_manager/providers.dart';
import 'package:money_manager/ui/place_spending_screen.dart';
import 'package:money_manager/ui/theme.dart';

// 假資料，唔係真訂單
final _export = jsonEncode({
  'format': 'money-expense-taobao',
  'version': 1,
  'orders': [
    {
      'id': '9',
      'time': '2026-09-01 10:00:00',
      'shop': '測試小店',
      'items': [
        {
          'title': '手機殼',
          'qty': 2,
          'price': '58.90',
          'sku': '黑色',
          'pic': '//img.alicdn.com/a.jpg',
          'url': 'https://item.taobao.com/item.htm?id=1',
        },
        {'title': '數據線', 'qty': 1, 'price': '10.00'},
      ],
      'paid': '68.90',
      'status': '交易成功',
    },
  ],
});

void main() {
  test('按地方分：淘寶按店、Google Play 按 App、其他按商戶', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ledger = Ledger(db);
    final wallet = await ledger.createFundAccount(name: '錢包', type: AccountType.asset, subtype: AccountSubtype.ewallet);
    final accounts = await db.select(db.accounts).get();
    String cat(String name) => accounts.firstWhere((a) => a.name == name && a.type == AccountType.expense).id;
    final pay = accounts.firstWhere((a) => a.name == '人工' && a.type == AccountType.income).id;

    Future<void> spend(int amount, String? merchant, int day, {String? externalId, String category = '購物'}) =>
        ledger.saveEntry(
          EntryDraft(
            kind: EntryKind.expense,
            amount: amount,
            fromAccountId: wallet,
            toAccountId: cat(category),
            occurredAt: DateTime(2026, 9, day),
            merchant: merchant,
          ),
          externalId: externalId,
        );
    await spend(3000, '測試小店', 1, externalId: 'taobao:1');
    await spend(2000, '另一間', 2, externalId: 'taobao:2');
    await spend(1000, '測試小店', 3, externalId: 'taobao:3');
    await spend(7800, '月卡 (明日方舟)', 4, externalId: 'takeout:a', category: '課金');
    await spend(450, '九巴', 5, category: '巴士');
    await spend(500, ' 九巴', 6, category: '巴士');
    await spend(100, null, 7, category: '午餐');
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.income,
        amount: 99999,
        fromAccountId: pay,
        toAccountId: wallet,
        occurredAt: DateTime(2026, 9, 8),
      ),
    );

    final places = groupByPlace(await ledger.transactions());
    expect(places.map((p) => p.name), ['Google Play', '淘寶', '九巴', unknownPlace]);
    final taobao = places[1];
    expect(taobao.total, 6000);
    expect(taobao.txs, hasLength(3));
    expect(taobao.last, DateTime(2026, 9, 3));
    expect(taobao.sortedParts.map((p) => (p.name, p.total)), [('測試小店', 4000), ('另一間', 2000)]);
    expect(places.first.sortedParts.single.name, '明日方舟');
    expect(places[2].total, 950);
    expect(places[2].parts, isEmpty);
  });

  test('淘寶單入帳之後讀得返買咗乜同相', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ledger = Ledger(db);
    final service = CaptureService(ledger);
    final wallet = await ledger.createFundAccount(name: '錢包', type: AccountType.asset, subtype: AccountSubtype.ewallet);
    final order = parseTaobaoExport(_export)!.single;
    await saveTaobaoItems(db, [order]);
    final (raw, p) = taobaoToCaptures([order], rate: 1.0).single;
    await service.ingestParsed(raw, p);
    final c = await (db.select(db.captures)..where((x) => x.externalId.equals('taobao:9'))).getSingle();
    final entryId = await service.confirm(c, fundId: wallet);

    final info = (await loadOrderInfo(db))[entryId]!;
    expect(info.orderId, '9');
    expect(info.summary, '手機殼 ×2、數據線');
    expect(info.original, '¥68.90 × 1.0000');
    expect(info.imageUrl, 'https://img.alicdn.com/a.jpg');
    expect(info.items.map((i) => (i.title, i.qty, i.price, i.sku, i.url)), [
      ('手機殼', 2, 5890, '黑色', 'https://item.taobao.com/item.htm?id=1'),
      ('數據線', 1, 1000, null, null),
    ]);

    // 再匯入：換新唔重複
    await saveTaobaoItems(db, [order]);
    expect(await db.select(db.purchaseItems).get(), hasLength(2));
  });

  testWidgets('邊度使錢：撳淘寶睇每間店，再撳店睇買咗乜', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    final tmp = Directory.systemTemp.createTempSync('mm');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.runAsync(() async {
      final ledger = Ledger(db);
      final service = CaptureService(ledger);
      final wallet = await ledger.createFundAccount(
        name: '錢包',
        type: AccountType.asset,
        subtype: AccountSubtype.ewallet,
      );
      final now = DateTime.now();
      final orders = [
        TaobaoOrder(
          id: '1',
          at: now,
          shop: '測試小店',
          lines: [const TaobaoItem('手機殼', priceFen: 3000)],
          paidFen: 3000,
          status: '交易成功',
        ),
        TaobaoOrder(id: '2', at: now, shop: '另一間', items: ['杯'], paidFen: 1000, status: '交易成功'),
      ];
      await saveTaobaoItems(db, orders);
      for (final (raw, p) in taobaoToCaptures(orders, rate: 1.0)) {
        await service.ingestParsed(raw, p);
      }
      for (final c in await db.select(db.captures).get()) {
        await service.confirm(c, fundId: wallet);
      }
    });

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appPathsProvider.overrideWithValue(AppPaths(tmp.path)), databaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: buildAppTheme(), home: const PlaceSpendingScreen()),
      ),
    );
    await settle();
    expect(find.text('淘寶'), findsOneWidget);
    await tester.tap(find.text('淘寶'));
    await settle();
    expect(find.text('店舖'), findsOneWidget);
    await tester.tap(find.text('測試小店').first);
    await settle();
    expect(find.text('手機殼'), findsOneWidget);
    expect(find.text('杯'), findsNothing);
    await tester.tap(find.text('手機殼'));
    await settle();
    expect(find.text('訂單號 1'), findsOneWidget);
    expect(find.text('×1 · ¥30.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
