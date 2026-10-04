import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// 新版本由呢個 GitHub repo 嘅 Releases 發佈（CI 喺 main 自動出）。
const updateRepo = 'HKmario852/money-manager';

const _channel = MethodChannel('hk.mario.money_manager/update');

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一個已發佈嘅版本。
class AppRelease {
  const AppRelease({
    required this.build,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.size,
    this.sha256,
  });

  final int build;
  final String name;
  final String notes;
  final Uri apkUrl;
  final int size;

  /// GitHub 計好嘅 SHA-256（舊啲嘅 release 可能冇）
  final String? sha256;
}

/// 讀 GitHub `releases/latest` 嘅回覆。冇 APK 或者格式唔啱返回 null。
AppRelease? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'] as String? ?? '';
  final build = int.tryParse(RegExp(r'build-(\d+)$').firstMatch(tag)?.group(1) ?? '');
  if (build == null || json['draft'] == true || json['prerelease'] == true) return null;
  for (final a in (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final name = a['name'] as String? ?? '';
    final url = Uri.tryParse(a['browser_download_url'] as String? ?? '');
    if (!name.endsWith('.apk') || url == null || url.scheme != 'https' || url.host != 'github.com') continue;
    final digest = a['digest'] as String?;
    return AppRelease(
      build: build,
      name: (json['name'] as String?)?.trim().isNotEmpty == true ? (json['name'] as String).trim() : tag,
      notes: cleanReleaseNotes(json['body'] as String? ?? ''),
      apkUrl: url,
      size: (a['size'] as num?)?.toInt() ?? 0,
      sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
    );
  }
  return null;
}

/// GitHub 自動生成嘅更新內容有 Markdown 同連結，轉做一行行簡單文字。
String cleanReleaseNotes(String body) {
  final lines = <String>[];
  for (var line in const LineSplitter().convert(body)) {
    line = line
        .replaceAll(RegExp(r'<!--.*?-->'), '')
        .replaceAll(RegExp(r' by @\S+ in https://\S+'), '')
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'^\s*[*-]\s+'), '• ')
        .trim();
    if (line.isEmpty || line.startsWith('**Full Changelog**') || line == "What's Changed") continue;
    lines.add(line);
  }
  return lines.join('\n');
}

class Updater {
  Updater({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  bool get supported => Platform.isAndroid;

  /// 最新版本；冇或者讀唔到返回 null。
  Future<AppRelease?> latest() async {
    final uri = Uri.https('api.github.com', '/repos/$updateRepo/releases/latest');
    try {
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'money-manager-app');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return null; // 未有 release
      if (res.statusCode != 200) throw UpdateException('檢查更新失敗（${res.statusCode}）');
      return parseRelease(jsonDecode(text) as Map<String, dynamic>);
    } on UpdateException {
      rethrow;
    } on Exception catch (e) {
      throw UpdateException('連唔到 GitHub：$e');
    }
  }

  /// 下載去 cache/updates，核對大小同 SHA-256。
  Future<File> download(AppRelease r, Directory cacheDir, {void Function(double progress)? onProgress}) async {
    final dir = Directory('${cacheDir.path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}/money-manager-${r.build}.apk');
    try {
      final req = await _client.getUrl(r.apkUrl).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.userAgentHeader, 'money-manager-app');
      final res = await req.close();
      if (res.statusCode != 200) throw UpdateException('下載失敗（${res.statusCode}）');
      final total = r.size > 0 ? r.size : res.contentLength;
      final sink = file.openWrite();
      final hashOut = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(hashOut);
      var received = 0;
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      hasher.close();
      if (r.size > 0 && received != r.size) throw const UpdateException('下載唔完整，請再試');
      if (r.sha256 != null && hashOut.events.single.toString() != r.sha256) {
        throw const UpdateException('更新檔校驗唔啱，已經刪走，請再試');
      }
      return file;
    } catch (e) {
      if (file.existsSync()) file.deleteSync();
      if (e is UpdateException) rethrow;
      throw UpdateException('下載失敗：$e');
    }
  }

  /// 打開系統安裝畫面。返回 false = 要先喺系統設定允許安裝（已經幫用戶打開咗設定頁）。
  Future<bool> install(File apk) async {
    final r = await _channel.invokeMethod<String>('installApk', apk.path);
    return r == 'started';
  }

  void close() => _client.close(force: true);
}

/// `crypto` 嘅 chunked 轉換要一個 Sink 收結果。
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}
