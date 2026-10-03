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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('首次啟動 → 記一筆支出 → 首頁同賬戶更新', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('歡迎使用記錄課金'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '銀包而家有幾多錢'), '500');
    await tester.tap(find.text('開始記賬'));
    await settle(tester);
    expect(find.text('最近交易'), findsOneWidget);
    expect(find.text('\$500.00'), findsWidgets); // 淨資產

    // 記一筆：餐飲 › 午餐 $45.5
    await tester.tap(find.byTooltip('記一筆'));
    await settle(tester);
    await tester.tap(find.text('餐飲'));
    await settle(tester);
    await tester.tap(find.text('午餐'));
    await settle(tester);
    for (final k in ['4', '5', '.', '5']) {
      await tester.tap(find.widgetWithText(FilledButton, k).last);
      await tester.pump();
    }
    expect(find.text('\$45.50'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check));
    await settle(tester);

    expect(find.text('餐飲 › 午餐'), findsOneWidget);
    expect(find.text('\$45.50'), findsWidgets);

    final cash = await (db.select(db.accounts)..where((a) => a.name.equals('現金'))).getSingle();
    final rows = await (db.select(db.postings)..where((p) => p.accountId.equals(cash.id))).get();
    expect(rows.fold(0, (s, p) => s + p.amount), 50000 - 4550);

    // 其他分頁可以打開
    await tester.tap(find.text('交易'));
    await settle(tester);
    await tester.tap(find.text('報表'));
    await settle(tester);
    expect(find.text('總支出'), findsOneWidget);
    await tester.tap(find.text('賬戶').last);
    await settle(tester);
    expect(find.text('\$454.50'), findsWidgets);
    await tester.tap(find.text('首頁'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);
    expect(find.text('私隱鎖'), findsOneWidget);
    await tester.tap(find.text('分類'));
    await settle(tester);
    expect(find.text('交通'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
