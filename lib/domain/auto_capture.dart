import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'capture.dart';
import 'gemini.dart';

/// 自動記賬：收集付款通知 / 截圖 → Gemini 抽交易 → 入「待確認」。
class AutoCapture {
  AutoCapture(this.db, this.capture, {required this.dataDir, FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  static const _channel = MethodChannel('hk.mario.money_manager/capture');
  static const _keyName = 'gemini_api_key';

  final AppDatabase db;
  final CaptureService capture;
  final String dataDir;
  final FlutterSecureStorage _secure;

  /// 由原生佇列拎出嚟、但未成功交俾 Gemini 嘅通知（失敗唔會唔見）
  File get _backlog => File(p.join(dataDir, 'notification_backlog.json'));

  // ------------------------------------------------------------ 設定

  Future<String?> apiKey() => _secure.read(key: _keyName);

  /// 驗證 key 並揀模型；成功先儲存。
  Future<String> saveApiKey(String key) async {
    final model = await GeminiClient.pickFlashModel(key.trim());
    await _secure.write(key: _keyName, value: key.trim());
    await db.setSetting(SettingKeys.geminiModel, model);
    return model;
  }

  Future<void> clearApiKey() => _secure.delete(key: _keyName);

  Future<bool> autoPost() async => await db.getSetting(SettingKeys.captureMode) == 'auto';

  Future<GeminiClient?> _client() async {
    final key = await apiKey();
    if (key == null || key.isEmpty) return null;
    final model = await db.getSetting(SettingKeys.geminiModel) ?? await GeminiClient.pickFlashModel(key);
    return GeminiClient(key, model: model);
  }

  // ------------------------------------------------------------ 通知

  Future<bool> notificationAccessGranted() async => await _channel.invokeMethod<bool>('isAccessGranted') ?? false;

  Future<void> openNotificationAccessSettings() => _channel.invokeMethod('openAccessSettings');

  Future<List<String>> allowedPackages() async =>
      (await _channel.invokeListMethod<String>('getAllowedPackages')) ?? const [];

  Future<void> setAllowedPackages(List<String> packages) =>
      _channel.invokeMethod('setAllowedPackages', {'packages': packages});

  Future<List<({String package, String label})>> launchableApps() async {
    final list = await _channel.invokeListMethod<Map>('launchableApps') ?? const [];
    return [for (final m in list) (package: '${m['package']}', label: '${m['label']}')];
  }

  /// 處理所有排緊隊嘅通知。冇 API key 就留喺佇列等下次。
  Future<IngestResult?> processNotifications() async {
    final client = await _client();
    if (client == null) return null;

    final drained = jsonDecode(await _channel.invokeMethod<String>('drain') ?? '[]') as List;
    final backlog = [
      ...await _readBacklog(),
      ...drained.cast<Map<String, dynamic>>(),
    ].where((n) => looksLikePayment('${n['text']}')).toList();
    await _writeBacklog(backlog);
    final relevant = List.of(backlog);

    var total = const IngestResult(added: 0, duplicates: 0, skipped: 0);
    final choices = await capture.choices();
    final autoPost = await this.autoPost();
    const batchSize = 15;
    for (var i = 0; i < relevant.length; i += batchSize) {
      final batch = relevant.skip(i).take(batchSize).toList();
      final sources = [
        for (final n in batch)
          'App: ${n['app']} (${n['package']})\n'
              'Received: ${DateTime.fromMillisecondsSinceEpoch(n['postedAt'] as int).toIso8601String()}\n'
              '${n['text']}',
      ];
      final json = await client.generateJson(
        prompt: buildExtractionPrompt(choices: choices, now: DateTime.now(), sources: sources),
        schema: extractionSchema,
      );
      final txs = parseExtraction(json, choices: choices);
      final candidates = <CaptureCandidate>[];
      final perSource = <int, int>{};
      for (final t in txs) {
        final idx = t.sourceIndex;
        if (idx == null || idx < 0 || idx >= batch.length) continue;
        final n = perSource[idx] = (perSource[idx] ?? 0) + 1; // 一個通知可能有幾筆
        candidates.add(
          CaptureCandidate(t, externalId: 'notif:${batch[idx]['key']}#$n', source: EntrySource.notification),
        );
      }
      final r = await capture.ingest(
        candidates,
        autoPost: autoPost,
        defaultFundId: await db.getSetting(SettingKeys.captureDefaultFund),
      );
      total = IngestResult(
        added: total.added + r.added,
        duplicates: total.duplicates + r.duplicates,
        skipped: total.skipped + r.skipped,
      );
      // 呢批搞掂先喺 backlog 刪走
      final done = batch.map((n) => n['key']).toSet();
      backlog.removeWhere((n) => done.contains(n['key']));
      await _writeBacklog(backlog);
    }
    return total;
  }

  Future<List<Map<String, dynamic>>> _readBacklog() async {
    try {
      return (jsonDecode(await _backlog.readAsString()) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeBacklog(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) {
      if (await _backlog.exists()) await _backlog.delete();
    } else {
      await _backlog.writeAsString(jsonEncode(items));
    }
  }

  // ------------------------------------------------------------ 截圖

  /// 讀交易紀錄截圖（八達通 App、銀行 App…）。[accountId] 係呢啲紀錄所屬嘅賬戶。
  Future<IngestResult> importScreenshots(
    List<(Uint8List bytes, String mimeType)> images, {
    required String accountId,
  }) async {
    final client = await _client();
    if (client == null) throw const GeminiException('未設定 Gemini API key');
    final choices = await capture.choices();
    final json = await client.generateJson(
      prompt: buildExtractionPrompt(
        choices: choices,
        now: DateTime.now(),
        fixedAccountId: accountId,
        imageContext:
            'The image(s) are screenshots of a transaction history list (for example the Octopus app\'s '
            '交易紀錄, a bank app or a wallet app). Negative amounts are spending; positive "+" amounts on an '
            'Octopus / wallet list are top-ups (增值) into that account. Skip summary totals and headers.',
      ),
      images: images,
      schema: extractionSchema,
    );
    final txs = parseExtraction(json, choices: choices);
    return capture.ingest(
      [
        for (final t in txs)
          CaptureCandidate(
            t,
            // 同一行喺幾張截圖重複出現都只會入一次
            externalId: 'img:$accountId:${screenshotRowKey(t)}',
            source: EntrySource.import,
            fallbackAccountId: accountId,
          ),
      ],
      autoPost: await autoPost(),
      defaultFundId: await db.getSetting(SettingKeys.captureDefaultFund),
    );
  }
}

/// 截圖入面一行交易嘅身份（時間到分鐘 + 金額 + 商戶）。
String screenshotRowKey(ExtractedTx t) {
  final at = t.occurredAt;
  final minute = DateTime(at.year, at.month, at.day, at.hour, at.minute).toIso8601String();
  return '$minute|${t.kind.name}|${t.amount}|${t.merchant ?? ''}';
}

/// 粗略過濾：有數字同貨幣 / 付款字眼先值得交俾 Gemini（慳用量，亦少啲送私人訊息出去）。
bool looksLikePayment(String text) {
  if (!RegExp(r'\d').hasMatch(text)) return false;
  return RegExp(
    r'(HK\$|HKD|\$|港幣|港元|元|RMB|CNY|USD|US\$|¥|€|£|付款|支付|消費|簽賬|簽帳|扣賬|扣款|交易|轉賬|轉帳|入賬|存入|增值|退款|'
    r'paid|payment|purchase|spent|charged|debited|credited|transaction|transfer|refund|top.?up|receipt|order)',
    caseSensitive: false,
  ).hasMatch(text);
}
