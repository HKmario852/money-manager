import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/app.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/providers.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    tmp = Directory.systemTemp.createTempSync('mm');
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
    overrides: [appPathsProvider.overrideWithValue(AppPaths(tmp.path)), databaseProvider.overrideWithValue(db)],
    child: const MoneyApp(),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('首次啟動 → 記一筆支出 → 首頁同賬戶更新', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('歡迎使用 Money Expense'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '銀包而家有幾多錢'), '500');
    await tester.tap(find.text('開始記賬'));
    await settle(tester);
    expect(find.text('最近交易'), findsOneWidget);
    expect(find.text('HK\$500.00'), findsWidgets); // 淨資產

    // 記一筆：餐飲 › 午餐 $45.5
    await tester.tap(find.byTooltip('記一筆'));
    await settle(tester);
    await tester.tap(find.text('餐飲'));
    await settle(tester);
    await tester.tap(find.text('午餐'));
    await settle(tester);
    for (final k in ['4', '5', '.', '5']) {
      await tester.tap(find.byKey(ValueKey('key-$k')));
      await tester.pump();
    }
    expect(find.text('-HK\$ 45.5'), findsOneWidget);
    expect(find.text('餐飲 › 午餐 · 現金'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('key-done')));
    await settle(tester);

    expect(find.text('餐飲 › 午餐'), findsOneWidget);
    expect(find.text('-HK\$45.50'), findsWidgets);

    final cash = await (db.select(db.accounts)..where((a) => a.name.equals('現金'))).getSingle();
    final rows = await (db.select(db.postings)..where((p) => p.accountId.equals(cash.id))).get();
    expect(rows.fold(0, (s, p) => s + p.amount), 50000 - 4550);

    // 再記一筆：存完留喺記賬畫面，金額清零，可以直接關閉
    await tester.tap(find.byTooltip('記一筆'));
    await settle(tester);
    await tester.tap(find.text('餐飲'));
    await settle(tester);
    await tester.tap(find.text('午餐'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('key-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('key-again')));
    await settle(tester);
    expect(find.text('-HK\$ 0'), findsOneWidget);
    expect(find.textContaining('已記低'), findsOneWidget);
    await tester.tap(find.byTooltip('關閉'));
    await settle(tester);
    expect(find.text('唔儲存就離開？'), findsNothing);
    final afterAgain = await (db.select(db.postings)..where((p) => p.accountId.equals(cash.id))).get();
    expect(afterAgain.fold(0, (s, p) => s + p.amount), 50000 - 4550 - 300);

    // 全部交易
    await tester.tap(find.text('查看全部'));
    await settle(tester);
    expect(find.text('餐飲 › 午餐'), findsNWidgets(2));
    await tester.binding.handlePopRoute();
    await settle(tester);

    // 其他分頁可以打開
    await tester.tap(find.text('統計'));
    await settle(tester);
    expect(find.text('總支出'), findsOneWidget);
    expect(find.text('支出趨勢'), findsOneWidget);
    await tester.tap(find.text('預算').last);
    await settle(tester);
    expect(find.text('未設預算'), findsOneWidget);
    await tester.tap(find.text('帳戶').last);
    await settle(tester);
    expect(find.text('我的帳戶'), findsOneWidget);
    expect(find.text('HK\$451.50'), findsWidgets);
    await tester.tap(find.text('首頁'));
    await settle(tester);
    await tester.tap(find.byTooltip('設定'));
    await settle(tester);
    expect(find.text('私隱鎖'), findsOneWidget);
    await tester.tap(find.text('分類'));
    await settle(tester);
    expect(find.text('交通'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('記賬畫面有輸入就返回會先問', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await db.setSetting(SettingKeys.onboarded, 'true');
    await tester.pumpWidget(app());
    await settle(tester);

    // 冇改過：返回即走
    await tester.tap(find.byTooltip('記一筆'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('最近交易'), findsOneWidget);

    // 輸入咗金額：要確認
    await tester.tap(find.byTooltip('記一筆'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('key-7')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('唔儲存就離開？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.text('-HK\$ 7'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tester.tap(find.text('離開'));
    await settle(tester);
    expect(find.text('最近交易'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('只記支出：唔顯示淨資產同帳戶結餘', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await db.setSetting(SettingKeys.onboarded, 'true');
    await db.setSetting(SettingKeys.spendingOnly, 'true');
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('淨資產'), findsNothing);

    await tester.tap(find.text('帳戶').last);
    await settle(tester);
    expect(find.text('我的帳戶'), findsOneWidget);
    expect(find.textContaining('HK\$'), findsNothing);

    // 新增帳戶淨係要名
    await tester.tap(find.byTooltip('新增帳戶'));
    await settle(tester);
    expect(find.text('而家結餘'), findsNothing);
    await tester.binding.handlePopRoute();
    await settle(tester);

    // 記賬冇轉帳
    await tester.tap(find.text('首頁'));
    await settle(tester);
    await tester.tap(find.byTooltip('記一筆'));
    await settle(tester);
    expect(find.text('支出'), findsWidgets);
    expect(find.text('轉帳'), findsNothing);
    await tester.binding.handlePopRoute();
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
