import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'theme.dart';

/// 圖示用字串 key 存喺 DB，唔好存 codepoint（release build 會 tree-shake 走）。
const kIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'breakfast': Icons.free_breakfast,
  'lunch': Icons.lunch_dining,
  'dinner': Icons.dinner_dining,
  'delivery': Icons.delivery_dining,
  'drink': Icons.local_cafe,
  'snack': Icons.icecream,
  'transport': Icons.directions_transit,
  'train': Icons.train,
  'bus': Icons.directions_bus,
  'taxi': Icons.local_taxi,
  'fuel': Icons.local_gas_station,
  'parking': Icons.local_parking,
  'shopping': Icons.shopping_bag,
  'basket': Icons.shopping_basket,
  'clothes': Icons.checkroom,
  'devices': Icons.devices,
  'home': Icons.home,
  'building': Icons.apartment,
  'bolt': Icons.bolt,
  'wifi': Icons.wifi,
  'game': Icons.sports_esports,
  'movie': Icons.movie,
  'diamond': Icons.diamond,
  'subscription': Icons.subscriptions,
  'medical': Icons.medical_services,
  'pill': Icons.medication,
  'school': Icons.school,
  'book': Icons.menu_book,
  'people': Icons.people,
  'gift': Icons.card_giftcard,
  'more': Icons.more_horiz,
  'work': Icons.work,
  'star': Icons.star,
  'percent': Icons.percent,
  'trending': Icons.trending_up,
  'undo': Icons.undo,
  'cash': Icons.payments,
  'bank': Icons.account_balance,
  'card': Icons.credit_card,
  'wallet': Icons.account_balance_wallet,
  'octopus': Icons.contactless,
  'savings': Icons.savings,
  'pets': Icons.pets,
  'flight': Icons.flight,
  'hotel': Icons.hotel,
  'sport': Icons.fitness_center,
  'beauty': Icons.spa,
  'baby': Icons.child_friendly,
  'phone': Icons.phone_android,
  'insurance': Icons.health_and_safety,
  'tax': Icons.receipt_long,
};

const kPalette = <int>[
  0xFFEF6C00,
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF5E35B1,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF00ACC1,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFFDD835,
  0xFFFB8C00,
  0xFF6D4C41,
  0xFF757575,
  0xFF546E7A,
];

IconData iconFor(Account a) =>
    kIcons[a.icon] ??
    switch (a.subtype) {
      AccountSubtype.cash => Icons.payments,
      AccountSubtype.bank => Icons.account_balance,
      AccountSubtype.creditCard => Icons.credit_card,
      AccountSubtype.ewallet => Icons.contactless,
      _ => a.type == AccountType.liability ? Icons.money_off : Icons.category,
    };

Color colorFor(Account a, BuildContext context) => a.color != null ? Color(a.color!) : AppColors.muted;

/// 支出用黑字、收入用藍字（跟設計圖）。
const expenseColor = AppColors.ink;
const incomeColor = AppColors.blue;

/// 分類：淡色圓角方塊 + 分類名第一個字（餐、交、購…）。
/// 賬戶：灰色圓角方塊 + 圖示；信用卡用淺橙。
class AccountAvatar extends StatelessWidget {
  const AccountAvatar(this.account, {super.key, this.radius = 20});
  final Account account;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final Color bg, fg;
    final Widget child;
    if (isFund(account.type)) {
      final card = account.subtype == AccountSubtype.creditCard || account.type == AccountType.liability;
      bg = card ? AppColors.peach : AppColors.chip;
      fg = card ? AppColors.orange : AppColors.ink;
      child = Icon(iconFor(account), color: fg, size: radius * 1.05);
    } else {
      final c = colorFor(account, context);
      bg = Color.lerp(Colors.white, c, 0.2)!;
      fg = Color.lerp(c, Colors.black, 0.3)!;
      child = Text(
        account.name.isEmpty ? '?' : account.name.characters.first,
        style: TextStyle(color: fg, fontSize: radius * 0.9, fontWeight: FontWeight.w700, height: 1),
      );
    }
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius * 0.6)),
        child: child,
      ),
    );
  }
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String formatDate(DateTime d, {bool withYear = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final rel = switch (today.difference(day).inDays) {
    0 => '今日 ',
    1 => '尋日 ',
    _ => '',
  };
  final y = withYear || d.year != now.year ? '${d.year}年' : '';
  return '$rel$y${d.month}月${d.day}日（${_weekdays[d.weekday - 1]}）';
}

String formatTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String subtypeLabel(AccountType type, AccountSubtype? s) => switch (s) {
  AccountSubtype.cash => '現金',
  AccountSubtype.bank => '銀行',
  AccountSubtype.creditCard => '信用卡',
  AccountSubtype.ewallet => '八達通 / 電子錢包',
  _ => type == AccountType.liability ? '其他負債' : '其他資產',
};

String kindLabel(EntryKind k) => switch (k) {
  EntryKind.expense => '支出',
  EntryKind.income => '收入',
  EntryKind.transfer => '轉賬',
  EntryKind.opening => '期初結餘',
  EntryKind.adjustment => '結餘調整',
};

/// 分類全名，例如「餐飲 › 外賣」
String categoryPath(Account a, Map<String, Account> all) {
  final parent = a.parentId != null ? all[a.parentId] : null;
  return parent != null ? '${parent.name} › ${a.name}' : a.name;
}

List<Account> fundAccounts(Iterable<Account> all, {bool includeArchived = false}) =>
    all.where((a) => isFund(a.type) && (includeArchived || !a.isArchived)).toList();

List<Account> topCategories(Iterable<Account> all, AccountType type) =>
    all.where((a) => a.type == type && a.parentId == null && !a.isArchived).toList();

List<Account> childrenOf(Iterable<Account> all, String parentId) =>
    all.where((a) => a.parentId == parentId && !a.isArchived).toList();

/// 交易對用戶嚟講嘅「金額」：支出負、收入正、轉賬按睇緊嘅賬戶。
int displayAmount(TxView tx, {String? forAccount}) {
  if (forAccount != null) {
    final a = tx.from.id == forAccount || tx.to.id == forAccount;
    if (a) {
      final effect = tx.effectOn(forAccount);
      return isFund(tx.from.id == forAccount ? tx.from.type : tx.to.type) ? effect : -effect;
    }
  }
  return switch (tx.entry.kind) {
    EntryKind.expense => -tx.amount,
    EntryKind.income => tx.amount,
    _ => tx.amount,
  };
}

class AmountText extends StatelessWidget {
  const AmountText(this.amount, {super.key, this.style, this.neutral = false, this.showPlus = false});
  final int amount;
  final TextStyle? style;
  final bool neutral;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    final color = neutral || amount == 0 ? null : (amount < 0 ? expenseColor : incomeColor);
    return Text(
      formatMoney(amount, showPlus: showPlus),
      style: (style ?? const TextStyle()).copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class PeriodSwitcher extends ConsumerWidget {
  const PeriodSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (start, end) = ref.watch(currentPeriodProvider);
    final startDay = ref.watch(monthStartDayProvider);
    final label = startDay == 1
        ? periodLabel(start)
        : '${start.month}/${start.day} – ${end.subtract(const Duration(days: 1)).month}/${end.subtract(const Duration(days: 1)).day}';
    final notifier = ref.read(periodAnchorProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: '上個月', icon: const Icon(Icons.chevron_left), onPressed: () => notifier.shift(-1)),
        Flexible(
          child: GestureDetector(
            onTap: notifier.reset,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
        ),
        IconButton(tooltip: '下個月', icon: const Icon(Icons.chevron_right), onPressed: () => notifier.shift(1)),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: c),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: c),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Widget asyncBody<T>(AsyncValue<T> value, Widget Function(T data) builder) => value.when(
  data: builder,
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => Center(
    child: Padding(padding: const EdgeInsets.all(16), child: Text('出錯：$e')),
  ),
);

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
}

Future<bool> confirm(BuildContext context, String title, {String? message, String ok = '確定'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message != null ? Text(message) : null,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(
  BuildContext context,
  String title, {
  String initial = '',
  String? hint,
  TextInputType? keyboard,
  bool obscure = false,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboard,
        obscureText: obscure,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('確定')),
      ],
    ),
  );
}

/// 揀賬戶 / 分類嘅 bottom sheet。
Future<Account?> pickAccount(
  BuildContext context,
  List<Account> options, {
  String title = '揀賬戶',
  Map<String, int>? balances,
}) {
  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in options)
                    ListTile(
                      leading: AccountAvatar(a),
                      title: Text(a.name),
                      trailing: balances != null
                          ? AmountText(toDisplay(a.type, balances[a.id] ?? 0), neutral: true)
                          : null,
                      onTap: () => Navigator.pop(c, a),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
