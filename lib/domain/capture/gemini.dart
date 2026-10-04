import 'dart:convert';
import 'dart:io';

import '../money.dart';
import 'parser.dart';

const defaultGeminiModel = 'gemini-2.5-flash';

class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gemini 讀唔到規則處理唔到嘅通知 / 電郵。只會傳送嗰一段文字，唔會傳其他帳目資料。
class GeminiParser {
  GeminiParser({required this.apiKey, this.model = defaultGeminiModel, HttpClient? client})
    : _client = client ?? HttpClient();

  final String apiKey;
  final String model;
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
    final uri = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent');
    final Map<String, dynamic> json;
    try {
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.contentType = ContentType.json;
      req.headers.set('x-goog-api-key', apiKey);
      req.add(
        utf8.encode(
          jsonEncode({
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {'responseMimeType': 'application/json', 'responseSchema': schema, 'temperature': 0},
          }),
        ),
      );
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw GeminiException(switch (res.statusCode) {
          400 || 403 => 'Gemini API key 唔啱或者冇權限',
          404 => '搵唔到 Gemini 模型「$model」，請喺設定改模型名',
          429 => 'Gemini 用量到咗上限，遲啲再試',
          _ => 'Gemini 出錯（${res.statusCode}）',
        });
      }
      json = jsonDecode(text) as Map<String, dynamic>;
    } on GeminiException {
      rethrow;
    } on Exception catch (e) {
      throw GeminiException('連唔到 Gemini：$e');
    }
    final candParts = (json['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?;
    return candParts?.firstOrNull?['text'] as String?;
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
