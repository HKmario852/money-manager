import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/database.dart';
import 'capture_service.dart';
import 'parser.dart';

const _channel = MethodChannel('hk.mario.money_manager/capture');

/// 一個發過通知嘅 App。
class SeenApp {
  const SeenApp(this.package, this.label);
  final String package;
  final String? label;
  String get name => label ?? knownSources[package] ?? package;
}

/// Android 通知讀取（iOS 冇呢個功能，全部返回空）。
class NotificationBridge {
  const NotificationBridge();

  bool get supported => Platform.isAndroid;

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> isGranted() async => await _call<bool>('isNotificationAccessGranted') ?? false;
  Future<void> openSettings() => _call<void>('openNotificationAccessSettings');

  Future<List<SeenApp>> seenApps() async {
    final list = await _call<List<Object?>>('getSeenApps') ?? const [];
    return [
      for (final m in list.whereType<Map<Object?, Object?>>()) SeenApp(m['package'] as String, m['label'] as String?),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Set<String>> allowedApps() async =>
      (await _call<List<Object?>>('getAllowedApps') ?? const []).whereType<String>().toSet();

  Future<void> setAllowedApps(Set<String> packages) => _call<void>('setAllowedApps', packages.toList());

  /// 攞走隊列入面嘅通知（攞完就清）。
  Future<List<RawCapture>> drain() async {
    final list = await _call<List<Object?>>('drainNotifications') ?? const [];
    final out = <RawCapture>[];
    for (final m in list.whereType<Map<Object?, Object?>>()) {
      final pkg = m['package'] as String?;
      final text = m['text'] as String?;
      final title = m['title'] as String?;
      final time = m['postTime'];
      if (pkg == null || (text == null && title == null)) continue;
      out.add(
        RawCapture(
          source: EntrySource.notification,
          sourceKey: pkg,
          sourceLabel: (m['label'] as String?) ?? knownSources[pkg],
          externalId: 'n:${m['id']}',
          title: title,
          body: text ?? '',
          occurredAt: time is int ? DateTime.fromMillisecondsSinceEpoch(time) : DateTime.now(),
        ),
      );
    }
    return out;
  }

  Future<bool> hasNfc() async => await _call<bool>('hasNfc') ?? false;

  /// 拍八達通讀餘額，返回仙。用戶取消或者讀唔到會拋 [PlatformException]。
  Future<int> readOctopusBalance() async {
    final raw = await _channel.invokeMethod<int>('readOctopus');
    if (raw == null) throw PlatformException(code: 'read_failed', message: '讀唔到張卡');
    return octopusRawToMinor(raw);
  }

  Future<void> cancelOctopus() => _call<void>('cancelOctopus');
}

/// 八達通卡入面嘅數值以 0.1 港元為單位，再加咗 $50 偏移（俾負數餘額用）。
int octopusRawToMinor(int raw) => (raw - 500) * 10;

class GmailException implements Exception {
  const GmailException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 經用戶自己 Google 帳戶入面嘅 Apps Script 攞 Gmail 收據。
class GmailBridge {
  GmailBridge({required this.url, required this.token, HttpClient? client}) : _client = client ?? HttpClient();
  final String url;
  final String token;
  final HttpClient _client;

  Future<List<RawCapture>> fetch({DateTime? since}) async {
    final base = Uri.tryParse(url.trim());
    if (base == null || base.scheme != 'https' || !base.host.endsWith('google.com')) {
      throw const GmailException('Apps Script 網址唔啱，應該係 https://script.google.com/... 開頭');
    }
    final uri = base.replace(
      queryParameters: {
        ...base.queryParameters,
        'token': token,
        if (since != null) 'since': '${since.millisecondsSinceEpoch}',
      },
    );
    final String text;
    try {
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 20));
      final res = await req.close().timeout(const Duration(seconds: 40));
      text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw GmailException('Gmail 收據連線出錯（${res.statusCode}）');
    } on GmailException {
      rethrow;
    } on Exception catch (e) {
      throw GmailException('連唔到 Apps Script：$e');
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw const GmailException('Apps Script 冇回 JSON，請檢查部署設定（存取權要揀「任何人」）');
    }
    if (json is! Map) throw const GmailException('Apps Script 回覆格式唔啱');
    if (json['error'] != null) {
      throw GmailException(json['error'] == 'unauthorized' ? '密鑰唔啱，請將 App 入面嘅密鑰貼返入 Script' : '${json['error']}');
    }
    final out = <RawCapture>[];
    for (final m in (json['messages'] as List? ?? const []).whereType<Map<Object?, Object?>>()) {
      final id = m['id'] as String?;
      final date = m['date'];
      if (id == null || date is! num) continue;
      final from = (m['from'] as String? ?? '').toLowerCase();
      final address = RegExp(r'<([^>]+)>').firstMatch(from)?.group(1) ?? from;
      out.add(
        RawCapture(
          source: EntrySource.email,
          sourceKey: address,
          sourceLabel: knownSources[address],
          externalId: 'g:$id',
          title: m['subject'] as String?,
          body: m['body'] as String? ?? '',
          occurredAt: DateTime.fromMillisecondsSinceEpoch(date.toInt()),
        ),
      );
    }
    return out;
  }

  void close() => _client.close(force: true);
}

/// 貼入 Google Apps Script 嘅程式碼（已經填好密鑰）。
String gmailScriptSource(String token) =>
    '''
// 記錄課金：將 Gmail 收據交俾 App。只會讀符合 QUERY 嘅電郵。
const TOKEN = '$token';
const QUERY = 'from:googleplay-noreply@google.com';

function doGet(e) {
  const p = (e && e.parameter) || {};
  if (p.token !== TOKEN) return json_({ error: 'unauthorized' });
  const since = Number(p.since || 0) || Date.now() - 30 * 24 * 3600 * 1000;
  const threads = GmailApp.search(QUERY + ' after:' + Math.floor(since / 1000), 0, 50);
  const messages = [];
  threads.forEach(function (t) {
    t.getMessages().forEach(function (m) {
      const date = m.getDate().getTime();
      if (date <= since) return;
      messages.push({
        id: m.getId(),
        date: date,
        from: m.getFrom(),
        subject: m.getSubject(),
        body: m.getPlainBody().slice(0, 4000),
      });
    });
  });
  return json_({ messages: messages });
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}
''';
