import 'dart:convert';
import 'dart:io';

import '../money.dart';
import 'parser.dart';

const defaultGeminiModel = 'gemini-2.5-flash';
const fallbackGeminiModel = 'gemini-2.5-flash-lite';

class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gemini 讀唔到規則處理唔到嘅通知 / 電郵。只會傳送嗰一段文字，唔會傳其他帳目資料。
class GeminiParser {
  GeminiParser({
    required this.apiKey,
    this.model = defaultGeminiModel,
    HttpClient? client,
    this.baseUrl = 'https://generativelanguage.googleapis.com',
    this.retryDelay = const Duration(seconds: 2),
  }) : _client = client ?? HttpClient();

  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration retryDelay;
  final HttpClient _client;

  static const _schema = {
    'type': 'OBJECT',
    'properties': {
      'is_payment': {'type': 'BOOLEAN'},
      'direction': {
        'type': 'STRING',
        'enum': ['expense', 'income'],
      },
      'amount': {'type': 'NUMBER'},
      'currency': {'type': 'STRING'},
      'merchant': {'type': 'STRING'},
      'category': {'type': 'STRING'},
    },
    'required': ['is_payment'],
  };

  /// 返回 null = 唔係一筆已完成嘅付款或者收款。
  Future<ParsedPayment?> parse({
    required String source,
    String? title,
    required String body,
    required List<String> categories,
  }) async {
    final prompt =
        '''
You read one phone notification or email and decide whether it records a completed payment or money received.
Promotions, offers, reminders, failed or pending payments and balance-only messages are NOT payments.
Return JSON only. amount is the amount actually paid or received (not a balance, not an original price).
category must be exactly one of these names, or empty if unsure:
${categories.join('\n')}

Source: $source
Title: ${title ?? ''}
Text:
${body.length > 3000 ? body.substring(0, 3000) : body}
''';
    final out = await _generate([
      {'text': prompt},
    ], _schema);
    return out == null ? null : decodeGeminiAnswer(out);
  }

  static const _octopusSchema = {
    'type': 'OBJECT',
    'properties': {
      'is_octopus_history': {'type': 'BOOLEAN'},
      'rows': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'datetime': {'type': 'STRING'},
            'merchant': {'type': 'STRING'},
            'amount': {'type': 'NUMBER'},
            'direction': {
              'type': 'STRING',
              'enum': ['spend', 'topup', 'refund'],
            },
            'category': {'type': 'STRING'},
          },
          'required': ['datetime', 'merchant', 'amount', 'direction'],
        },
      },
    },
    'required': ['is_octopus_history', 'rows'],
  };

  /// 讀八達通 App「交易紀錄」截圖，返回每一行。唔係八達通紀錄截圖就拋 [GeminiException]。
  Future<List<OctopusRow>> parseOctopusScreenshot(
    List<int> image, {
    String mimeType = 'image/jpeg',
    required List<String> categories,
  }) async {
    final prompt =
        '''
This is a screenshot of the Hong Kong Octopus app transaction history (交易紀錄).
Read every visible transaction row. Skip rows that are cut off so the amount or time is unreadable.
datetime: exactly as shown, format YYYY-MM-DD HH:mm.
merchant: the name shown on the row, exactly as written.
amount: positive number, without the sign.
direction: "spend" for a minus amount, "topup" for a plus amount that adds value (增值, 7-Eleven top-up, AAVS),
"refund" for any other plus amount.
category: for spend rows, exactly one of these names, or empty if unsure:
${categories.join('\n')}
If the image is not an Octopus transaction list, set is_octopus_history to false and rows to [].
''';
    final out = await _generate([
      {
        'inline_data': {'mime_type': mimeType, 'data': base64Encode(image)},
      },
      {'text': prompt},
    ], _octopusSchema);
    final rows = out == null ? null : decodeOctopusRows(out);
    if (rows == null) throw const GeminiException('Gemini 認唔出呢張係八達通交易紀錄截圖');
    return rows;
  }

  Future<String?> _generate(List<Map<String, Object>> parts, Map<String, Object> schema) async {
    final body = utf8.encode(
      jsonEncode({
        'contents': [
          {'parts': parts},
        ],
        'generationConfig': {'responseMimeType': 'application/json', 'responseSchema': schema, 'temperature': 0},
      }),
    );
    // Google 繁忙（500/503）好常見：等一陣再試一次，再唔得就轉用較輕嘅後備模型
    final attempts = [model, model, if (model == defaultGeminiModel) fallbackGeminiModel];
    (int, String)? busy;
    for (var i = 0; i < attempts.length; i++) {
      if (i > 0) await Future<void>.delayed(retryDelay * i);
      final (status, text) = await _post(attempts[i], body);
      if (status == 200) {
        final json = jsonDecode(text) as Map<String, dynamic>;
        final candParts = (json['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?;
        return candParts?.firstOrNull?['text'] as String?;
      }
      if (status == 500 || status == 503) {
        busy = (status, text);
        continue;
      }
      // 後備模型唔存在就照報原本嘅繁忙錯誤
      if (busy != null && attempts[i] != model) break;
      throw GeminiException(geminiErrorMessage(status, text, attempts[i]));
    }
    throw GeminiException(geminiErrorMessage(busy!.$1, busy.$2, model));
  }

  Future<(int, String)> _post(String model, List<int> body) async {
    final uri = Uri.parse('$baseUrl/v1beta/models/$model:generateContent');
    try {
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.contentType = ContentType.json;
      req.headers.set('x-goog-api-key', apiKey);
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 60));
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } on Exception catch (e) {
      throw GeminiException('連唔到 Gemini：$e');
    }
  }

  void close() => _client.close(force: true);
}

/// 將 Gemini 回覆嘅 JSON 轉做 [ParsedPayment]。分開出嚟方便測試。
ParsedPayment? decodeGeminiAnswer(String raw) {
  final Map<String, dynamic> a;
  try {
    a = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  if (a['is_payment'] != true) return null;
  final amount = a['amount'];
  final minor = amount is num ? parseMinor(amount.toStringAsFixed(2)) : null;
  if (minor == null || minor <= 0) return null;
  String? clean(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  return ParsedPayment(
    amount: minor,
    currency: (clean(a['currency']) ?? 'HKD').toUpperCase(),
    merchant: clean(a['merchant']),
    isIncome: a['direction'] == 'income',
    categoryHint: clean(a['category']),
  );
}

/// 八達通截圖入面嘅一行。
class OctopusRow {
  const OctopusRow({required this.occurredAt, required this.merchant, required this.payment});
  final DateTime occurredAt;
  final String merchant;
  final ParsedPayment payment;
}

/// 將 Gemini 讀截圖嘅 JSON 轉做 [OctopusRow]。null = 唔係八達通紀錄。
List<OctopusRow>? decodeOctopusRows(String raw) {
  final Map<String, dynamic> a;
  try {
    a = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  if (a['is_octopus_history'] != true) return null;
  final out = <OctopusRow>[];
  for (final r in (a['rows'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})').firstMatch('${r['datetime']}');
    final amount = r['amount'];
    final minor = amount is num ? parseMinor(amount.abs().toStringAsFixed(2)) : null;
    final merchant = '${r['merchant'] ?? ''}'.trim();
    if (m == null || minor == null || minor <= 0 || merchant.isEmpty) continue;
    final at = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
    final direction = r['direction'];
    final category = r['category'];
    out.add(
      OctopusRow(
        occurredAt: at,
        merchant: merchant,
        payment: ParsedPayment(
          amount: minor,
          merchant: merchant,
          isIncome: direction == 'refund',
          isTransfer: direction == 'topup',
          categoryHint: direction == 'spend'
              ? (category is String && category.trim().isNotEmpty
                    ? category.trim()
                    : categoryHintFor(octopusScreenshotKey, merchant))
              : null,
        ),
      ),
    );
  }
  return out;
}

/// 將 Gemini 嘅錯誤回應轉做用戶睇得明嘅原因（400/403 有好多種，唔一定係 key 錯）。
String geminiErrorMessage(int status, String body, String model) {
  String message = '';
  final reasons = <String>{};
  try {
    final error = (jsonDecode(body) as Map<String, dynamic>)['error'] as Map<String, dynamic>;
    message = error['message'] as String? ?? '';
    for (final d in (error['details'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      if (d['reason'] is String) reasons.add(d['reason'] as String);
    }
  } catch (_) {}
  final lower = message.toLowerCase();
  if (reasons.contains('API_KEY_INVALID') || lower.contains('api key not valid')) {
    return 'Gemini API key 唔啱，請喺 Google AI Studio 重新複製成條 key';
  }
  if (lower.contains('location is not supported') || lower.contains('not available in your country')) {
    return 'Google 話你而家嘅地區用唔到 Gemini API（香港唔喺支援地區）';
  }
  if (reasons.contains('SERVICE_DISABLED')) {
    return '呢條 key 嘅 Google Cloud 項目未開 Generative Language API';
  }
  if (reasons.any((r) => r.startsWith('API_KEY_') && r.endsWith('_BLOCKED'))) {
    return '呢條 key 設咗限制，唔准用 Gemini API，請喺 Google Cloud 改 key 嘅限制';
  }
  final detail = message.isEmpty ? '' : '：${message.length > 160 ? '${message.substring(0, 160)}…' : message}';
  return switch (status) {
    404 => '搵唔到 Gemini 模型「$model」，請喺設定改模型名',
    429 => 'Gemini 用量到咗上限，遲啲再試',
    500 || 503 => 'Google 嘅 Gemini 而家太多人用（$status），你條 key 冇問題，遲啲再試',
    400 || 403 => 'Gemini 拒絕咗個請求（$status）$detail',
    _ => 'Gemini 出錯（$status）$detail',
  };
}
