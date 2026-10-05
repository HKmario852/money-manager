import 'package:drift/drift.dart';

import 'database.dart';

typedef _Cat = (String name, String icon, int color, List<(String, String)> children);

const _expense = <_Cat>[
  (
    '餐飲',
    'restaurant',
    0xFFEF6C00,
    [('早餐', 'breakfast'), ('午餐', 'lunch'), ('晚餐', 'dinner'), ('外賣', 'delivery'), ('飲品', 'drink'), ('零食', 'snack')],
  ),
  ('交通', 'transport', 0xFF1E88E5, [('港鐵', 'train'), ('巴士', 'bus'), ('的士', 'taxi'), ('加油', 'fuel'), ('泊車', 'parking')]),
  ('購物', 'shopping', 0xFFD81B60, [('日用品', 'basket'), ('衫褲鞋襪', 'clothes'), ('電子產品', 'devices'), ('淘寶', 'shopping')]),
  ('住屋', 'home', 0xFF6D4C41, [('租金', 'home'), ('管理費', 'building'), ('水電煤', 'bolt'), ('上網', 'wifi')]),
  ('娛樂', 'game', 0xFF8E24AA, [('電影', 'movie'), ('遊戲', 'game'), ('課金', 'diamond'), ('訂閱', 'subscription')]),
  ('醫療', 'medical', 0xFFE53935, [('睇醫生', 'medical'), ('藥物', 'pill')]),
  ('學習', 'school', 0xFF3949AB, [('書', 'book'), ('課程', 'school')]),
  ('社交', 'people', 0xFF00897B, [('送禮', 'gift'), ('請食飯', 'restaurant')]),
  ('其他', 'more', 0xFF757575, []),
];

const _income = <_Cat>[
  ('人工', 'work', 0xFF43A047, []),
  ('花紅', 'star', 0xFF7CB342, []),
  ('利息', 'percent', 0xFF00ACC1, []),
  ('投資收益', 'trending', 0xFF5E35B1, []),
  ('退款', 'undo', 0xFFFB8C00, []),
  ('其他', 'more', 0xFF757575, []),
];

Future<void> seedDefaults(AppDatabase db) async {
  await db.batch((b) {
    b.insertAll(db.accounts, [
      AccountsCompanion.insert(
        id: const Value(SystemAccounts.openingBalance),
        name: '期初結餘',
        type: AccountType.equity,
        isSystem: const Value(true),
      ),
      AccountsCompanion.insert(
        id: const Value(SystemAccounts.adjustment),
        name: '結餘調整',
        type: AccountType.equity,
        isSystem: const Value(true),
      ),
    ]);
    for (final (type, cats) in [(AccountType.expense, _expense), (AccountType.income, _income)]) {
      var order = 0;
      for (final (name, icon, color, children) in cats) {
        final parentId = newId();
        b.insert(
          db.accounts,
          AccountsCompanion.insert(
            id: Value(parentId),
            name: name,
            type: type,
            icon: Value(icon),
            color: Value(color),
            sortOrder: Value(order++),
          ),
        );
        var childOrder = 0;
        for (final (childName, childIcon) in children) {
          b.insert(
            db.accounts,
            AccountsCompanion.insert(
              name: childName,
              type: type,
              parentId: Value(parentId),
              icon: Value(childIcon),
              color: Value(color),
              sortOrder: Value(childOrder++),
            ),
          );
        }
      }
    }
    b.insertAll(db.settings, [
      SettingsCompanion.insert(key: SettingKeys.baseCurrency, value: 'HKD'),
      SettingsCompanion.insert(key: SettingKeys.monthStartDay, value: '1'),
      SettingsCompanion.insert(key: SettingKeys.biometricLock, value: 'false'),
    ]);
  });
}
