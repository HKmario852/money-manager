import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../../data/database.dart';
import 'capture_service.dart';
import 'parser.dart';

/// Google Takeout 匯入嘅來源 key（同 Gmail 收據唔同 key，所以兩邊報同一筆會當重複）。
const takeoutSourceKey = 'google-takeout';

/// 每個付款方法一個 key，咁樣 app 會分別記住 AlipayHK、信用卡等等對應邊個賬戶。Gmail 收據都用同一個 key。
String playSourceKey(String? paymentMethod) =>
    paymentMethod == null ? takeoutSourceKey : '$takeoutSourceKey:${paymentMethod.toLowerCase()}';

class TakeoutException implements Exception {
  const TakeoutException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Takeout「Google Play 商店」入面嘅一筆購買。
class PlayPurchase {
  const PlayPurchase({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.at,
    this.kind,
    this.paymentMethod,
  });

  /// 訂單編號（GPA.…）；冇就用時間同名合成
  final String id;
  final String title;

  /// 最小單位（仙）
  final int amount;
  final String currency;
  final DateTime at;

  /// Google 嘅 documentType，例如 In App Item、Subscription、Android Apps
  final String? kind;

  /// 付款方法，已經去走卡號同餘額，例如「AlipayHK」、「Mastercard」、「Google Play 餘額」
  final String? paymentMethod;
}

/// 讀 Takeout zip 或者單一 JSON 檔。檔名會因語言唔同，所以靠內容認：
/// `Order History.json`（有訂單編號，優先用）或者 `Purchase History.json`。
Future<List<PlayPurchase>> readTakeout(String path) async {
  if (path.toLowerCase().endsWith('.json')) {
    final found = parseTakeoutJson(await File(path).readAsString());
    if (found == null) throw const TakeoutException('呢個 JSON 唔係 Google Play 購買記錄');
    return found.purchases;
  }
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    ({bool hasOrderIds, List<PlayPurchase> purchases})? best;
    for (final f in archive.files) {
      // Play 記錄檔細，唔使解壓大嘅相片 / 影片
      if (!f.isFile || !f.name.toLowerCase().endsWith('.json') || f.size > 20 * 1024 * 1024) continue;
      final bytes = f.readBytes();
      if (bytes == null) continue;
      final found = parseTakeoutJson(utf8.decode(bytes, allowMalformed: true));
      if (found != null && (best == null || (found.hasOrderIds && !best.hasOrderIds))) best = found;
    }
    if (best == null) throw const TakeoutException('個 zip 入面搵唔到 Google Play 購買記錄，匯出時要揀「Google Play 商店」');
    return best.purchases;
  } on TakeoutException {
    rethrow;
  } on Exception catch (e) {
    throw TakeoutException('讀唔到個 zip：$e');
  } finally {
    await input.close();
  }
}

/// 唔係 Play 購買記錄返回 null。免費嘢（$0）同讀唔到金額嘅會略過。
({bool hasOrderIds, List<PlayPurchase> purchases})? parseTakeoutJson(String text) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (data is! List) return null;
  final items = data.whereType<Map<String, dynamic>>();
  final orders = items.map((e) => e['orderHistory']).whereType<Map<String, dynamic>>().toList();
  if (orders.isNotEmpty) {
    return (
      hasOrderIds: true,
      purchases: [
        for (final o in orders)
          ?_purchase(
            id: o['orderId'] as String?,
            title: _orderTitle(o),
            kind: _orderKind(o),
            method: (o['billingInstrument'] as Map?)?['displayName'] as String?,
            price: o['totalPrice'] as String?,
            refund: o['refundAmount'] as String?,
            time: o['creationTime'] as String?,
          ),
      ],
    );
  }
  final history = items.map((e) => e['purchaseHistory']).whereType<Map<String, dynamic>>().toList();
  if (history.isEmpty) return null;
  return (
    hasOrderIds: false,
    purchases: [
      for (final p in history)
        ?_purchase(
          id: null,
          title: (p['doc'] as Map?)?['title'] as String?,
          kind: (p['doc'] as Map?)?['documentType'] as String?,
          method: p['paymentMethodTitle'] as String?,
          price: p['invoicePrice'] as String?,
          time: p['purchaseTime'] as String?,
        ),
    ],
  );
}

String? _orderTitle(Map<String, dynamic> o) {
  final titles = [
    for (final li in (o['lineItem'] as List? ?? const []).whereType<Map<String, dynamic>>())
      if ((li['doc'] as Map?)?['title'] case final String t when t.trim().isNotEmpty) t.trim(),
  ];
  return titles.isEmpty ? null : titles.join('、');
}

String? _orderKind(Map<String, dynamic> o) => [
  for (final li in (o['lineItem'] as List? ?? const []).whereType<Map<String, dynamic>>())
    if ((li['doc'] as Map?)?['documentType'] case final String k) k,
].firstOrNull;

PlayPurchase? _purchase({
  String? id,
  String? title,
  String? kind,
  String? method,
  String? price,
  String? refund,
  String? time,
}) {
  final at = time == null ? null : DateTime.tryParse(time)?.toLocal();
  final money = price == null ? null : parsePlayPrice(price);
  if (at == null || money == null) return null;
  // 退咗款嘅減返；全數退款就唔當消費
  final amount = money.amount - (refund == null ? 0 : parsePlayPrice(refund)?.amount ?? 0);
  if (amount <= 0) return null;
  final name = (title == null || title.trim().isEmpty) ? 'Google Play' : title.trim();
  return PlayPurchase(
    id: (id != null && id.isNotEmpty) ? id : '${at.toUtc().toIso8601String()}:${merchantKey(name)}',
    title: name,
    amount: amount,
    currency: money.currency,
    at: at,
    kind: kind,
    paymentMethod: playPaymentMethod(method),
  );
}

const _currencySymbols = {
  r'HK$': 'HKD',
  r'US$': 'USD',
  r'NT$': 'TWD',
  r'A$': 'AUD',
  r'C$': 'CAD',
  r'S$': 'SGD',
  r'MOP$': 'MOP',
  'JP¥': 'JPY',
  'CN¥': 'CNY',
  'RMB': 'CNY',
  '€': 'EUR',
  '£': 'GBP',
  '¥': 'JPY',
  r'$': 'USD',
};

/// 「HK$8.00」、「HK$1,234.50」、「US$0.99」、「8.00 HKD」→ 仙同貨幣。
({int amount, String currency})? parsePlayPrice(String price) {
  final s = price.replaceAll(' ', ' ').trim();
  final number = RegExp(r'[0-9][0-9,]*(?:\.[0-9]+)?').firstMatch(s);
  if (number == null) return null;
  final raw = number.group(0)!;
  // 「2,49」咁嘅歐洲寫法：逗號後面啱啱兩個位係小數點
  final value = double.tryParse(
    RegExp(r'^\d+,\d{2}$').hasMatch(raw) ? raw.replaceAll(',', '.') : raw.replaceAll(',', ''),
  );
  if (value == null) return null;
  final code = RegExp(r'\b[A-Z]{3}\b').firstMatch(s)?.group(0);
  final rest = s.replaceFirst(raw, '').trim();
  final currency =
      (code != null && code != 'RMB' ? code : null) ??
      _currencySymbols.entries.where((e) => rest.contains(e.key)).firstOrNull?.value ??
      'HKD';
  return (amount: (value * 100).round(), currency: currency);
}

/// 轉做待確認嘅捕捉。[since] 之前嘅略過（Takeout 會包埋好多年前嘅記錄）。
List<(RawCapture, ParsedPayment)> takeoutToCaptures(List<PlayPurchase> purchases, {DateTime? since}) => [
  for (final p in purchases)
    if (since == null || !p.at.isBefore(since))
      (
        RawCapture(
          source: EntrySource.import,
          sourceKey: playSourceKey(p.paymentMethod),
          sourceLabel: p.paymentMethod ?? 'Google Play',
          externalId: 'takeout:${p.id}',
          title: 'Google Play 購買記錄',
          body: '${p.title} ${p.currency} ${(p.amount / 100).toStringAsFixed(2)}',
          occurredAt: p.at,
        ),
        ParsedPayment(
          amount: p.amount,
          currency: p.currency,
          merchant: p.title,
          categoryHint: switch (p.kind) {
            'Subscription' => '娛樂 › 訂閱',
            'Android Apps' => '娛樂 › 遊戲',
            _ => '娛樂 › 課金',
          },
        ),
      ),
];
