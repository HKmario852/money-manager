import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/capture/capture_service.dart';
import 'package:money_manager/domain/capture/takeout.dart';
import 'package:money_manager/domain/ledger.dart';
import 'package:money_manager/providers.dart';
import 'package:money_manager/ui/capture_screens.dart';
import 'package:money_manager/ui/theme.dart';

void main() {
  testWidgets('一鍵全確認：未有賬戶嘅按付款方法揀一次，全部入帳', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    final tmp = Directory.systemTemp.createTempSync('mm');
    addTearDown(() => tmp.deleteSync(recursive: true));

    late String wallet;
    await tester.runAsync(() async {
      final ledger = Ledger(db);
      wallet = await ledger.createFundAccount(name: '錢包', type: AccountType.asset, subtype: AccountSubtype.ewallet);
      final service = CaptureService(ledger);
      PlayPurchase buy(String id, String method, int day) => PlayPurchase(
        id: id,
        title: '月卡 (明日方舟)',
        amount: 3000,
        currency: 'HKD',
        at: DateTime(2026, 9, day),
        paymentMethod: method,
      );
      for (final (raw, p) in takeoutToCaptures([
        buy('a', 'AlipayHK', 1),
        buy('b', 'AlipayHK', 2),
        buy('c', 'Mastercard', 3),
      ])) {
        await service.ingestParsed(raw, p, parsedBy: ParsedBy.rule);
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
        child: MaterialApp(theme: buildAppTheme(), home: const CaptureInboxScreen()),
      ),
    );
    await settle();

    await tester.tap(find.text('一鍵全確認（3 筆）'));
    await settle();
    expect(find.text('呢啲用邊個賬戶俾錢？'), findsOneWidget);
    expect(find.text('AlipayHK（2 筆）'), findsOneWidget);
    expect(find.text('Mastercard（1 筆）'), findsOneWidget);
    await tester.tap(find.text('繼續'));
    await settle();
    expect(find.text('全部入帳？'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('入帳')));
    await settle();

    final captures = await tester.runAsync(() => db.select(db.captures).get());
    expect(captures!.every((c) => c.status == CaptureStatus.confirmed), true);
    expect(captures.every((c) => c.fundAccountId == wallet), true);
    final rules = await tester.runAsync(() => db.select(db.captureRules).get());
    expect(rules!.map((r) => r.key), containsAll(['s:google-takeout:alipayhk', 's:google-takeout:mastercard']));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
