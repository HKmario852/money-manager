// Renders README screenshots from made-up demo data into docs/screenshots/.
//
//   flutter test tool/screenshots --update-goldens
//
// Not part of the normal test run (CI only runs test/). Needs a font with Chinese glyphs:
// set SCREENSHOT_FONT to a .ttf/.otf, or install Noto Sans HK/TC (Windows) or Noto Sans CJK (Linux).
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/app.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/ledger.dart';
import 'package:money_manager/providers.dart';
import 'package:money_manager/ui/app_spending_screen.dart';
import 'package:money_manager/ui/capture_screens.dart';
import 'package:money_manager/ui/place_spending_screen.dart';

const _out = '../../docs/screenshots';

const _cjkFonts = [
  r'C:\Windows\Fonts\NotoSansHK-VF.ttf',
  r'C:\Windows\Fonts\NotoSansTC-VF.ttf',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
  '/System/Library/Fonts/PingFang.ttc',
];

Future<void> _loadFonts() async {
  final cjk =
      Platform.environment['SCREENSHOT_FONT'] ?? _cjkFonts.firstWhere((f) => File(f).existsSync(), orElse: () => '');
  if (cjk.isEmpty) fail('No Chinese font found. Set SCREENSHOT_FONT to a .ttf/.otf file.');
  final text = File(cjk).readAsBytes().then((b) => ByteData.sublistView(b));
  // The app's text theme uses Roboto; Noto/PingFang also cover Latin.
  // Text styles without a family fall back to the test font, so register it there too.
  await (FontLoader('Roboto')..addFont(text)).load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)))).load();
}

/// Theme styles that set no font family get the test font (boxes) in `flutter test`, unlike on a phone.
/// Give them the loaded font. Only used here; the app's theme is unchanged.
ThemeData _withFont(ThemeData t) {
  TextStyle? f(TextStyle? s) => s?.copyWith(fontFamily: s.fontFamily ?? 'Roboto');
  final filled = t.filledButtonTheme.style;
  return t.copyWith(
    appBarTheme: t.appBarTheme.copyWith(titleTextStyle: f(t.appBarTheme.titleTextStyle)),
    filledButtonTheme: FilledButtonThemeData(
      style: filled?.copyWith(textStyle: WidgetStateProperty.resolveWith((s) => f(filled.textStyle?.resolve(s)))),
    ),
    chipTheme: t.chipTheme.copyWith(
      labelStyle: f(t.chipTheme.labelStyle),
      secondaryLabelStyle: f(t.chipTheme.secondaryLabelStyle),
    ),
  );
}

/// Six months of fictional spending. No real people, shops or orders.
Future<void> _seedDemo(AppDatabase db) async {
  final ledger = Ledger(db);
  final now = DateTime.now();
  final rnd = Random(7);

  final cash = await ledger.createFundAccount(
    name: '現金',
    type: AccountType.asset,
    subtype: AccountSubtype.cash,
    openingBalance: 80000,
  );
  final ewallet = await ledger.createFundAccount(
    name: '電子錢包',
    type: AccountType.asset,
    subtype: AccountSubtype.ewallet,
    openingBalance: 300000,
  );
  final card = await ledger.createFundAccount(
    name: '信用卡',
    type: AccountType.liability,
    subtype: AccountSubtype.creditCard,
  );
  final bank = await ledger.createFundAccount(
    name: '銀行',
    type: AccountType.asset,
    subtype: AccountSubtype.bank,
    openingBalance: 2500000,
  );

  final accounts = await db.select(db.accounts).get();
  String cat(String name, [AccountType type = AccountType.expense]) =>
      accounts.firstWhere((a) => a.name == name && a.type == type).id;

  Future<void> spend(DateTime at, int cents, String category, String fund, {String? merchant, String? ext}) =>
      ledger.saveEntry(
        EntryDraft(
          kind: EntryKind.expense,
          amount: cents,
          fromAccountId: fund,
          toAccountId: cat(category),
          occurredAt: at,
          merchant: merchant,
        ),
        externalId: ext,
      );

  final start = DateTime(now.year, now.month - 5, 1);
  var n = 0;
  for (var d = start; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
    DateTime at(int h, int m) => DateTime(d.year, d.month, d.day, h, m);
    await spend(at(8, 10), 2800 + rnd.nextInt(1500), '早餐', cash, merchant: '街角茶餐廳');
    await spend(at(12, 45), 4800 + rnd.nextInt(3000), '午餐', ewallet, merchant: rnd.nextBool() ? '快餐店' : '麵家');
    if (rnd.nextInt(3) == 0) await spend(at(19, 30), 6000 + rnd.nextInt(9000), '晚餐', card, merchant: '小炒館');
    final train = rnd.nextBool();
    await spend(at(9, 0), 900 + rnd.nextInt(800), train ? '港鐵' : '巴士', ewallet, merchant: train ? '港鐵' : '巴士');
    if (rnd.nextInt(4) == 0) await spend(at(15, 20), 2200 + rnd.nextInt(2500), '飲品', ewallet, merchant: '咖啡店');
    if (rnd.nextInt(6) == 0) {
      await spend(
        at(22, 5),
        3000 + rnd.nextInt(30000),
        '淘寶',
        ewallet,
        merchant: ['示範家居店', '示範數碼店', '示範服飾店'][rnd.nextInt(3)],
        ext: 'taobao:demo${n++}',
      );
    }
    if (rnd.nextInt(9) == 0) {
      await spend(
        at(21, 40),
        [800, 3900, 7800][rnd.nextInt(3)],
        '課金',
        card,
        merchant: ['星光農場', '像素冒險'][rnd.nextInt(2)],
        ext: 'takeout:demo${n++}',
      );
    }
    if (rnd.nextInt(7) == 0) await spend(at(18, 0), 4000 + rnd.nextInt(12000), '日用品', card, merchant: '超級市場');
    if (d.day == 1) {
      await spend(at(10, 0), 19800, '上網', bank, merchant: '寬頻公司');
      await spend(at(10, 5), 3800, '訂閱', card, merchant: '影音串流', ext: 'takeout:demo${n++}');
      await ledger.saveEntry(
        EntryDraft(
          kind: EntryKind.income,
          amount: 2800000,
          fromAccountId: cat('人工', AccountType.income),
          toAccountId: bank,
          occurredAt: at(9, 30),
        ),
      );
    }
    if (d.day == 15) await spend(at(20, 0), 39800, '水電煤', bank, merchant: '電力公司');
  }

  await ledger.saveBudget(amount: 900000);
  await ledger.saveBudget(categoryId: cat('餐飲'), amount: 450000);
  await ledger.saveBudget(categoryId: cat('購物'), amount: 150000);
  await ledger.saveBudget(categoryId: cat('娛樂'), amount: 50000);

  // Two payments waiting in 待確認
  final pending = [('hk.alipay.wallet', '電子錢包', '示範便利店', 3650), ('com.android.vending', 'Google Play', '星光農場', 3900)];
  for (final (i, (key, label, merchant, amount)) in pending.indexed) {
    await db
        .into(db.captures)
        .insert(
          CapturesCompanion.insert(
            source: EntrySource.notification,
            sourceKey: key,
            sourceLabel: Value(label),
            externalId: 'demo-capture-$i',
            title: Value(label),
            body: '你已付款 HK\$${(amount / 100).toStringAsFixed(2)} 予 $merchant',
            occurredAt: now.subtract(Duration(hours: i + 1)),
            amount: Value(amount),
            currency: const Value('HKD'),
            merchant: Value(merchant),
          ),
        );
  }

  await db.setSetting(SettingKeys.onboarded, 'true');
  await db.setSetting(SettingKeys.spendingOnly, 'true');
  await db.setSetting(SettingKeys.updateLastCheck, now.toIso8601String());
}

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUpAll(_loadFonts);

  setUp(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    tmp = Directory.systemTemp.createTempSync('mm-shots');
    await _seedDemo(db);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('README screenshots', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appPathsProvider.overrideWithValue(AppPaths(tmp.path)), databaseProvider.overrideWithValue(db)],
        child: const MoneyApp(),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      await expectLater(find.byType(MoneyApp), matchesGoldenFile('$_out/$name.png'));
    }

    Future<void> open(Widget screen) async {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute(
              builder: (context) => Theme(data: _withFont(Theme.of(context)), child: screen),
            ),
          );
      await settle();
    }

    void back() => tester.state<NavigatorState>(find.byType(Navigator).first).pop();

    await shot('home');

    await tester.tap(find.text('統計'));
    await shot('stats');

    await tester.tap(find.text('預算').last);
    await shot('budgets');

    await tester.tap(find.text('首頁'));
    await open(const PlaceSpendingScreen());
    await shot('places');
    back();

    await open(const AppSpendingScreen());
    await shot('app-spending');
    back();

    await open(const CaptureInboxScreen());
    await shot('inbox');
    back();
    await settle();

    await tester.tap(find.byTooltip('記一筆'));
    await settle();
    await tester.tap(find.text('餐飲'));
    await settle();
    await tester.tap(find.text('午餐'));
    await settle();
    for (final k in ['4', '8', '.', '5']) {
      await tester.tap(find.byKey(ValueKey('key-$k')));
      await tester.pump();
    }
    await shot('add');
  });
}
