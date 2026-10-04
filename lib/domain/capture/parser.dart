import '../money.dart';

/// 由通知或者電郵讀出嚟嘅付款資料。
class ParsedPayment {
  const ParsedPayment({
    required this.amount,
    this.currency = 'HKD',
    this.merchant,
    this.isIncome = false,
    this.isTransfer = false,
    this.categoryHint,
  });

  /// 最小單位（仙）
  final int amount;
  final String currency;
  final String? merchant;
  final bool isIncome;

  /// 增值 / 轉賬（例如 7-Eleven 現金增值八達通），唔係支出
  final bool isTransfer;

  /// 分類提示，例如「娛樂 › 課金」或者「交通」
  final String? categoryHint;
}

/// 規則解析嘅結果：[payment] 係 null 而 [isPayment] 係 false = 肯定唔係付款通知。
/// 兩個都係 null = 規則唔肯定，可以交俾 Gemini。
class RuleResult {
  const RuleResult.payment(ParsedPayment this.payment) : isPayment = true;
  const RuleResult.notPayment() : payment = null, isPayment = false;
  const RuleResult.unsure() : payment = null, isPayment = null;

  final ParsedPayment? payment;
  final bool? isPayment;
}

/// 常見來源嘅顯示名。
const knownSources = <String, String>{
  'hk.alipay.wallet': 'AlipayHK',
  'com.android.vending': 'Google Play',
  'com.google.android.apps.walletnfcrel': 'Google Wallet',
  'com.octopuscards.nfc_reader': '八達通',
  'com.tencent.mm': 'WeChat Pay',
  'com.hsbc.hsbchkmobilebanking': 'HSBC',
  'googleplay-noreply@google.com': 'Google Play',
  octopusScreenshotKey: '八達通',
};

/// 八達通 App 截圖匯入嘅來源 key。
const octopusScreenshotKey = 'octopus-screenshot';

final _amountRe = RegExp(
  r'(?:HK\$|HKD\s?|港幣\s?|＄|\$)\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)|([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s?(?:HKD|港元|元)',
  caseSensitive: false,
);
final _balanceRe = RegExp(
  r'(?:可用)?(?:餘額|结余|結餘|balance|available)[^0-9$＄]{0,12}(?:HK\$|HKD\s?|＄|\$)?\s?[0-9][0-9,]*(?:\.[0-9]{1,2})?',
  caseSensitive: false,
);
final _totalRe = RegExp(
  r'(?:total|總計|合計|總額|總金額|金額|amount)[^0-9$＄]{0,12}(?:HK\$|HKD\s?|＄|\$)\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);
final _payRe = RegExp(
  r'付款|支付|消費|扣款|扣賬|簽賬|交易|購買|購物|訂單|收據|已付|paid|payment|purchase|spent|charged|receipt|order|transaction',
  caseSensitive: false,
);
final _incomeRe = RegExp(r'收款|收到|退款|入賬|入帳|存入|received|refund|credited', caseSensitive: false);
final _promoRe = RegExp(r'優惠|折扣|賞|推廣|立即|限時|coupon|offer|promo|discount|cashback|%\s*off', caseSensitive: false);
final _merchantRe = RegExp(
  r'(?:\bat\b|\bto\b|於|喺|在|向|商戶[:：]?|merchant[:：]?)\s*([^\s,，。.:：\n]{2,30})',
  caseSensitive: false,
);

int? _toMinor(String s) => parseMinor(s.replaceAll(',', ''));

/// 用固定規則讀付款資料。[sourceKey] 係套件名或者寄件人。
RuleResult parseByRules({required String sourceKey, String? title, required String body}) {
  // 電郵每行係 \r\n 結尾
  final text = '${title ?? ''}\n$body'.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Google Play 收據電郵：搵「總計 / Total」
  if (sourceKey.contains('googleplay') || (sourceKey == 'com.android.vending' && _payRe.hasMatch(text))) {
    final total = _totalRe.firstMatch(text);
    final m = total ?? _amountRe.firstMatch(text.replaceAll(_balanceRe, ''));
    final raw = total?.group(1) ?? m?.group(1) ?? m?.group(2);
    final amount = raw != null ? _toMinor(raw) : null;
    if (amount == null || amount <= 0) return const RuleResult.unsure();
    return RuleResult.payment(
      ParsedPayment(
        amount: amount,
        merchant: readPlayReceipt(text).item ?? 'Google Play',
        categoryHint: RegExp(r'續訂|訂閱|subscription|renew', caseSensitive: false).hasMatch(text) ? '娛樂 › 訂閱' : '娛樂 › 課金',
      ),
    );
  }

  // 推廣通知唔當付款
  if (_promoRe.hasMatch(text) && !RegExp(r'已付|成功|paid|charged', caseSensitive: false).hasMatch(text)) {
    return const RuleResult.notPayment();
  }

  final cleaned = text.replaceAll(_balanceRe, ' ');
  final amounts = _amountRe.allMatches(cleaned).toList();
  if (amounts.isEmpty) return const RuleResult.notPayment();
  if (!_payRe.hasMatch(text) && !_incomeRe.hasMatch(text)) return const RuleResult.unsure();
  // 多過一個金額（例如原價同折後價）就交俾 Gemini 判斷
  final distinct = amounts.map((m) => _toMinor(m.group(1) ?? m.group(2) ?? '')).toSet();
  if (distinct.length > 1) return const RuleResult.unsure();
  final amount = distinct.first;
  if (amount == null || amount <= 0) return const RuleResult.unsure();

  final merchant = _merchantRe.firstMatch(cleaned)?.group(1);
  return RuleResult.payment(
    ParsedPayment(
      amount: amount,
      merchant: merchant,
      isIncome: _incomeRe.hasMatch(text) && !_payRe.hasMatch(text.replaceAll(_incomeRe, '')),
      categoryHint: categoryHintFor(sourceKey, text),
    ),
  );
}

/// Play 收據入面嘅資料：項目名（例如「月卡 (明日方舟)」）、訂單編號、付款方法。
({String? item, String? itemLine, String? orderId, String? paymentMethod}) readPlayReceipt(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // 「商品 價格」表頭下面嗰行先係項目；前面「…購買了商品。」嗰句唔係
  String? itemLine;
  final header = lines.indexWhere(_playHeaderRe.hasMatch);
  if (header >= 0 && header + 1 < lines.length) {
    itemLine = lines[header + 1];
  } else {
    itemLine = lines.map((l) => _playItemFieldRe.firstMatch(l)?.group(1)?.trim()).nonNulls.firstOrNull;
  }
  var item = itemLine?.replaceFirst(_trailingPriceRe, '').trim();
  if (item != null && !RegExp(r'\p{L}', unicode: true).hasMatch(item)) item = null;

  String? method;
  final m = lines.indexWhere((l) => _playMethodRe.hasMatch(l));
  if (m >= 0) {
    final rest = lines[m].replaceFirst(_playMethodRe, '').trim();
    method = playPaymentMethod(rest.isNotEmpty ? rest : (m + 1 < lines.length ? lines[m + 1] : null));
  }

  return (
    item: (item == null || item.isEmpty) ? null : item,
    itemLine: item == null ? null : itemLine,
    orderId: _playOrderRe.firstMatch(text)?.group(0),
    paymentMethod: method,
  );
}

final _playHeaderRe = RegExp(r'^(?:商品|項目|Item)(?:\s*(?:數量|價格|價錢|金額|Qty|Quantity|Price))*$', caseSensitive: false);
final _playItemFieldRe = RegExp(r'^(?:商品|項目|Item)\s*[:：]\s*(.+)$', caseSensitive: false);
final _trailingPriceRe = RegExp(
  r'\s*(?:[A-Z]{0,3}\$|＄|€|£|¥|HKD|USD)\s?[0-9][0-9,.]*.*$|\s+[0-9][0-9,.]*\s?(?:HKD|USD)\b.*$',
);
final _playMethodRe = RegExp(r'^(?:付款方法|付款方式|Payment method)\s*[:：]?', caseSensitive: false);
final _playOrderRe = RegExp(r'\b[A-Z]{3}\.[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{5}(?:\.\.[0-9]+)?');

/// 「AlipayHK：852-12****34」→「AlipayHK」；「MasterCard-1234」→「Mastercard」。卡號同餘額唔留。
String? playPaymentMethod(String? displayName) {
  final name = displayName?.split(RegExp(r'[：:]|-\s*\d')).first.trim();
  if (name == null || name.isEmpty) return null;
  return name.toLowerCase() == 'mastercard' ? 'Mastercard' : name;
}

/// 由商戶名 / 內容估分類。
String? categoryHintFor(String sourceKey, String text) {
  if (RegExp(r'MTR|港鐵|地鐵|輕鐵').hasMatch(text)) return '交通 › 港鐵';
  if (RegExp(r'KMB|九巴|龍運|城巴|新巴|Citybus|巴士|小巴|渡輪|天星', caseSensitive: false).hasMatch(text)) {
    return '交通 › 巴士';
  }
  if (RegExp(r'Uber|的士|Taxi', caseSensitive: false).hasMatch(text)) return '交通 › 的士';
  if (RegExp(r'Foodpanda|Deliveroo|Keeta|外賣', caseSensitive: false).hasMatch(text)) return '餐飲 › 外賣';
  if (RegExp(r'Netflix|Spotify|Disney|YouTube Premium|訂閱', caseSensitive: false).hasMatch(text)) {
    return '娛樂 › 訂閱';
  }
  if (RegExp(r'貢茶|奶茶|咖啡|Coffee|Starbucks|星巴克|Pacific', caseSensitive: false).hasMatch(text)) return '餐飲 › 飲品';
  if (RegExp(r'麥當勞|McDonald|大家樂|美心|大快活|吉野家|KFC|肯德基', caseSensitive: false).hasMatch(text)) return '餐飲';
  if (RegExp(
    r'7-Eleven|7-11|OK便利|Circle K|惠康|百佳|Wellcome|ParknShop|759|阿信屋|萬寧|屈臣氏',
    caseSensitive: false,
  ).hasMatch(text)) {
    return '購物 › 日用品';
  }
  if (sourceKey == 'com.android.vending') return '娛樂 › 課金';
  return null;
}

/// 商戶名正規化，用嚟記住「呢個商戶 = 呢個分類」。
String merchantKey(String merchant) => merchant.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), '');
