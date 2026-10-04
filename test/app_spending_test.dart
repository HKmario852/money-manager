import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/data/database.dart';
import 'package:money_manager/domain/app_spending.dart';
import 'package:money_manager/domain/ledger.dart';

void main() {
  test('由項目名攞 App 名', () {
    expect(appNameFromTitle('月卡 (明日方舟)'), '明日方舟');
    expect(appNameFromTitle('每月青輝石組合包（蔚藍檔案）'), '蔚藍檔案');
    expect(appNameFromTitle('Few Gems (Pixel Gun 3D (Pocket Edition))'), 'Pixel Gun 3D (Pocket Edition)');
    expect(appNameFromTitle('Google Play Pass'), 'Google Play Pass');
    expect(appNameFromTitle('(冇 App 名)'), '(冇 App 名)');
    expect(appNameFromTitle('Plague Inc. '), 'Plague Inc.');
  });

  test('按 App 分組，只計課金 / 訂閱 / 遊戲', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ledger = Ledger(db);
    final card = await ledger.createFundAccount(name: '卡', type: AccountType.asset, subtype: AccountSubtype.bank);
    final accounts = await db.select(db.accounts).get();
    String cat(String name) => accounts.firstWhere((a) => a.name == name && a.type == AccountType.expense).id;

    Future<void> spend(int amount, String category, String? merchant, int day) => ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: amount,
        fromAccountId: card,
        toAccountId: cat(category),
        occurredAt: DateTime(2026, 9, day),
        merchant: merchant,
      ),
    );
    await spend(7800, '課金', '月卡 (明日方舟)', 1);
    await spend(3000, '課金', '調用憑證組合包 (明日方舟)', 5);
    await spend(2300, '訂閱', 'Google One', 3);
    await spend(500, '課金', null, 4);
    await spend(4500, '午餐', '大家樂', 2);

    final apps = groupByApp(await ledger.transactions(), appCategoryIds(accounts));
    expect(apps.map((a) => a.name), ['明日方舟', 'Google One', '未註明 App']);
    expect(apps.first.total, 10800);
    expect(apps.first.purchases, hasLength(2));
    expect(apps.first.last, DateTime(2026, 9, 5));
  });
}
