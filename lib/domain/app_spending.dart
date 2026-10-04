import '../data/database.dart';
import 'capture/parser.dart';
import 'ledger.dart';

/// 呢幾個分類（娛樂下面）嘅支出會按 App 分組。
const appCategoryNames = {'課金', '訂閱', '遊戲'};

/// 由 Google Play 嘅項目名攞 App 名：「月卡 (明日方舟)」→「明日方舟」，
/// 「Few Gems (Pixel Gun 3D (Pocket Edition))」→「Pixel Gun 3D (Pocket Edition)」。
/// 冇括號（例如買 App、訂閱）就成個名當 App 名。
String appNameFromTitle(String title) {
  final t = title.trim();
  if (t.endsWith(')') || t.endsWith('）')) {
    var depth = 0;
    for (var i = t.length - 1; i >= 0; i--) {
      final c = t[i];
      if (c == ')' || c == '）') depth++;
      if (c == '(' || c == '（') depth--;
      if (depth == 0) {
        final inner = t.substring(i + 1, t.length - 1).trim();
        // 成個名都喺括號入面，或者括號前面冇嘢 = 唔係「項目 (App)」格式
        if (inner.isNotEmpty && i > 0) return inner;
        break;
      }
    }
  }
  return t;
}

class AppSpend {
  AppSpend(this.name);
  final String name;
  final List<TxView> purchases = [];
  int total = 0;
  DateTime? last;
}

/// 將課金 / 訂閱 / 遊戲嘅支出按 App 分組，多到少排。
List<AppSpend> groupByApp(Iterable<TxView> txs, Set<String> appCategoryIds) {
  final byKey = <String, AppSpend>{};
  for (final t in txs) {
    if (t.entry.kind != EntryKind.expense || !appCategoryIds.contains(t.to.id)) continue;
    final title = t.entry.merchant ?? t.entry.note;
    final name = (title == null || title.trim().isEmpty) ? '未註明 App' : appNameFromTitle(title);
    final app = byKey.putIfAbsent(merchantKey(name), () => AppSpend(name));
    app.purchases.add(t);
    app.total += t.amount;
    if (app.last == null || t.entry.occurredAt.isAfter(app.last!)) app.last = t.entry.occurredAt;
  }
  final list = byKey.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  for (final a in list) {
    a.purchases.sort((x, y) => y.entry.occurredAt.compareTo(x.entry.occurredAt));
  }
  return list;
}

/// 課金、訂閱、遊戲同佢哋嘅子分類。
Set<String> appCategoryIds(Iterable<Account> accounts) {
  final all = accounts.where((a) => a.type == AccountType.expense && a.deletedAt == null).toList();
  final ids = {
    for (final a in all)
      if (appCategoryNames.contains(a.name)) a.id,
  };
  var grew = true;
  while (grew) {
    grew = false;
    for (final a in all) {
      if (a.parentId != null && ids.contains(a.parentId) && ids.add(a.id)) grew = true;
    }
  }
  return ids;
}
