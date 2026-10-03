import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/database.dart';

/// Gemini REST client（generativelanguage.googleapis.com）。
/// API key 由用戶喺設定輸入，存喺 secure storage，唔會入 repo 亦唔會入備份。
class GeminiClient {
  GeminiClient(this.apiKey, {required this.model, HttpClient? client}) : _client = client ?? HttpClient();

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';
  final String apiKey;
  final String model;
  final HttpClient _client;

  /// 揀一個最新、穩定嘅 Flash 模型（快同平），俾第一次設定 key 時用，順便驗證 key 啱唔啱。
  static Future<String> pickFlashModel(String apiKey, {HttpClient? client}) async {
    final json = await _send(client ?? HttpClient(), 'GET', '$_base/models?pageSize=200', apiKey, null);
    final models = [
      for (final m in (json['models'] as List? ?? const []).cast<Map<String, dynamic>>())
        if ((m['supportedGenerationMethods'] as List? ?? const []).contains('generateContent'))
          '${m['name']}'.replaceFirst('models/', ''),
    ];
    final best = bestFlashModel(models);
    if (best == null) throw const GeminiException('呢條 key 用唔到任何 Gemini Flash 模型');
    return best;
  }

  /// 傳入內容（文字 / 圖片），要求按 [schema] 回 JSON。
  Future<Map<String, dynamic>> generateJson({
    required String prompt,
    List<(Uint8List bytes, String mimeType)> images = const [],
    required Map<String, dynamic> schema,
  }) async {
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            for (final (bytes, mime) in images)
              {
                'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)},
              },
          ],
        },
      ],
      'generationConfig': {'temperature': 0, 'responseMimeType': 'application/json', 'responseSchema': schema},
    };
    final json = await _send(_client, 'POST', '$_base/models/$model:generateContent', apiKey, body);
    final candidates = json['candidates'] as List?;
    final parts = (candidates?.firstOrNull as Map?)?['content']?['parts'] as List?;
    final text = parts?.map((p) => (p as Map)['text'] ?? '').join();
    if (text == null || text.isEmpty) {
      final reason = (candidates?.firstOrNull as Map?)?['finishReason'] ?? json['promptFeedback']?['blockReason'];
      throw GeminiException('Gemini 冇回應（$reason）');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _send(
    HttpClient client,
    String method,
    String url,
    String apiKey,
    Object? body,
  ) async {
    final req = await client.openUrl(method, Uri.parse(url));
    req.headers.set('x-goog-api-key', apiKey);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(const Duration(seconds: 90));
    final text = await res.transform(utf8.decoder).join();
    final json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (res.statusCode != HttpStatus.ok) {
      final msg = json['error']?['message'] ?? 'HTTP ${res.statusCode}';
      throw GeminiException(switch (res.statusCode) {
        400 when '$msg'.contains('API key') => 'Gemini API key 唔啱',
        403 => 'Gemini API key 冇權限（$msg）',
        429 => 'Gemini 用量到咗上限，遲啲再試',
        _ => 'Gemini 錯誤：$msg',
      });
    }
    return json;
  }
}

class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 喺模型列表揀版本號最高嘅正式版 Flash（唔要 lite / preview / exp / 圖片 / 語音等特別版）。
String? bestFlashModel(List<String> names) {
  final candidates = names.where((n) {
    final s = n.toLowerCase();
    return RegExp(r'^gemini-\d+(\.\d+)?-flash$').hasMatch(s) || RegExp(r'^gemini-\d+(\.\d+)?-flash-\d{3}$').hasMatch(s);
  }).toList();
  double version(String n) => double.tryParse(RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(n)!.group(1)!) ?? 0;
  candidates.sort((a, b) {
    final c = version(b).compareTo(version(a));
    return c != 0 ? c : a.length.compareTo(b.length); // 同版本揀冇日期後綴嗰個（自動跟最新）
  });
  return candidates.firstOrNull;
}

// ------------------------------------------------------------------ 抽取交易

/// Gemini 讀完一段通知 / 電郵 / 截圖之後嘅一筆交易。
class ExtractedTx {
  const ExtractedTx({
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.currency,
    this.merchant,
    this.categoryId,
    this.accountId,
    this.toAccountId,
    this.note,
    this.sourceIndex,
  });

  final EntryKind kind;

  /// 最小貨幣單位（仙），正數
  final int amount;
  final DateTime occurredAt;
  final String? currency;
  final String? merchant;
  final String? categoryId;

  /// 支出 / 收入嘅資金賬戶；轉賬嘅「由」
  final String? accountId;

  /// 轉賬嘅「去」
  final String? toAccountId;
  final String? note;

  /// 一次送幾段文字時，屬於第幾段（0 開始）
  final int? sourceIndex;
}

/// 俾 Gemini 揀分類 / 賬戶用嘅選項。
class LedgerChoices {
  const LedgerChoices({required this.funds, required this.expenseCategories, required this.incomeCategories});

  /// (id, 名稱, 類型描述)
  final List<(String id, String label)> funds;
  final List<(String id, String label)> expenseCategories;
  final List<(String id, String label)> incomeCategories;

  Set<String> get ids => {
    ...funds.map((e) => e.$1),
    ...expenseCategories.map((e) => e.$1),
    ...incomeCategories.map((e) => e.$1),
  };
}

const extractionSchema = {
  'type': 'OBJECT',
  'properties': {
    'transactions': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'source_index': {'type': 'INTEGER'},
          'kind': {
            'type': 'STRING',
            'enum': ['expense', 'income', 'transfer'],
          },
          'amount': {'type': 'NUMBER'},
          'currency': {'type': 'STRING'},
          'merchant': {'type': 'STRING', 'nullable': true},
          'datetime': {'type': 'STRING', 'description': 'Local Hong Kong time, ISO 8601 without offset'},
          'category_id': {'type': 'STRING', 'nullable': true},
          'account_id': {'type': 'STRING', 'nullable': true},
          'to_account_id': {'type': 'STRING', 'nullable': true},
          'note': {'type': 'STRING', 'nullable': true},
        },
        'required': ['kind', 'amount', 'currency', 'datetime'],
      },
    },
  },
  'required': ['transactions'],
};

String _choiceList(List<(String, String)> items) => items.map((e) => '- ${e.$1}: ${e.$2}').join('\n');

/// 建立抽取交易嘅 prompt。[sources] 每段係一個通知 / 電郵；截圖就用 [imageContext] 描述。
String buildExtractionPrompt({
  required LedgerChoices choices,
  required DateTime now,
  List<String> sources = const [],
  String? imageContext,
  String? fixedAccountId,
}) {
  final buf = StringBuffer()
    ..writeln('You extract personal-finance transactions for a Hong Kong user\'s expense tracker.')
    ..writeln('Current local time (Hong Kong): ${now.toIso8601String()}')
    ..writeln()
    ..writeln('Rules:')
    ..writeln(
      '- Only real, completed money movements. Return nothing for OTP / verification codes, '
      'promotions, ads, login alerts, declined or failed payments, pending authorisations that say they are not charged, '
      'statement-ready notices, balance-only notices, and chat messages.',
    )
    ..writeln('- amount is a positive number in the currency shown. Prefer the HKD amount when both are shown.')
    ..writeln(
      '- datetime: use the time in the content; if it only has a date, use 12:00; '
      'if it has none, use the time the notification/email was received.',
    )
    ..writeln(
      '- Spending (card purchase, mobile payment, Octopus payment, app store purchase, subscription) → kind "expense".',
    )
    ..writeln('- Money received (salary, refund, transfer in from another person, interest) → kind "income".')
    ..writeln(
      '- Moving money between the user\'s own accounts (credit card repayment, Octopus / e-wallet top-up, '
      'bank to bank) → kind "transfer" with account_id = source and to_account_id = destination.',
    )
    ..writeln(
      '- category_id / account_id / to_account_id must be one of the ids listed below, or null if unsure. '
      'Match accounts by bank / card name or last digits when mentioned.',
    )
    ..writeln(
      '- merchant: the shop / payee as written (keep Chinese names as-is). note: very short extra info or null.',
    )
    ..writeln()
    ..writeln('User\'s accounts:')
    ..writeln(_choiceList(choices.funds))
    ..writeln()
    ..writeln('Expense categories:')
    ..writeln(_choiceList(choices.expenseCategories))
    ..writeln()
    ..writeln('Income categories:')
    ..writeln(_choiceList(choices.incomeCategories));
  if (fixedAccountId != null) {
    buf
      ..writeln()
      ..writeln(
        'All rows belong to account $fixedAccountId: use it as account_id for expenses / income, '
        'and as to_account_id for top-ups (add value, 增值), leaving account_id null for those.',
      );
  }
  if (imageContext != null) {
    buf
      ..writeln()
      ..writeln(imageContext)
      ..writeln('Return one transaction per row visible in the image(s). Use source_index 0.');
  }
  if (sources.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Sources (set source_index to the number in brackets):');
    for (var i = 0; i < sources.length; i++) {
      buf
        ..writeln('[$i]')
        ..writeln(sources[i])
        ..writeln();
    }
  }
  return buf.toString();
}

/// 解析 Gemini 回應，丟走金額 / 日期唔合理嘅項目，同埋唔喺清單入面嘅 id。
List<ExtractedTx> parseExtraction(Map<String, dynamic> json, {required LedgerChoices choices}) {
  final valid = choices.ids;
  String? id(Object? v) => v is String && valid.contains(v) ? v : null;
  String? text(Object? v) => v is String && v.trim().isNotEmpty && v.trim().toLowerCase() != 'null' ? v.trim() : null;
  final result = <ExtractedTx>[];
  for (final raw in (json['transactions'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final kind = EntryKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    final amount = raw['amount'] is num ? ((raw['amount'] as num) * 100).round().abs() : null;
    final at = DateTime.tryParse('${raw['datetime']}');
    if (kind == null || !const [EntryKind.expense, EntryKind.income, EntryKind.transfer].contains(kind)) continue;
    if (amount == null || amount <= 0 || at == null) continue;
    result.add(
      ExtractedTx(
        kind: kind,
        amount: amount,
        occurredAt: at.isUtc ? at.toLocal() : at,
        currency: text(raw['currency'])?.toUpperCase(),
        merchant: text(raw['merchant']),
        categoryId: id(raw['category_id']),
        accountId: id(raw['account_id']),
        toAccountId: id(raw['to_account_id']),
        note: text(raw['note']),
        sourceIndex: raw['source_index'] is int ? raw['source_index'] as int : null,
      ),
    );
  }
  return result;
}
