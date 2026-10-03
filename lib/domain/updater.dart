import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// App 內更新：CI 每次 merge 入 main 都會出一個 GitHub release（tag `build-<versionCode>`，
/// 附 `money-manager.apk`）。App 用自己嘅 versionCode 同最新 release 比較。
const kReleasesApi = 'https://api.github.com/repos/HKmario852/money-manager/releases/latest';
const kApkAssetName = 'money-manager.apk';

class ReleaseInfo {
  const ReleaseInfo({
    required this.build,
    required this.title,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  final int build;
  final String title;
  final String notes;
  final String apkUrl;
  final int apkSize;

  /// 解析 GitHub `releases/latest` 回應；唔係我哋 CI 出嘅 release（冇 build 號或者冇 APK）就回 null。
  static ReleaseInfo? fromGitHub(Map<String, dynamic> json) {
    final build = int.tryParse(RegExp(r'^build-(\d+)$').firstMatch('${json['tag_name']}')?.group(1) ?? '');
    final assets = (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final apk = assets.where((a) => a['name'] == kApkAssetName).firstOrNull;
    if (build == null || apk == null) return null;
    return ReleaseInfo(
      build: build,
      title: '${json['name'] ?? 'build-$build'}',
      notes: '${json['body'] ?? ''}'.trim(),
      apkUrl: '${apk['browser_download_url']}',
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class InstalledVersion {
  const InstalledVersion(this.name, this.build);
  final String name;
  final int build;

  @override
  String toString() => 'v$name ($build)';
}

class Updater {
  Updater({HttpClient? client}) : _client = client ?? HttpClient();

  static const _channel = MethodChannel('hk.mario.money_manager/updater');
  final HttpClient _client;

  Future<InstalledVersion> installedVersion() async {
    final m = await _channel.invokeMapMethod<String, Object?>('versionInfo');
    return InstalledVersion('${m?['name'] ?? '?'}', (m?['code'] as num?)?.toInt() ?? 0);
  }

  /// 有比而家新嘅版本就回 release，否則 null。
  Future<ReleaseInfo?> checkForUpdate() async {
    final installed = await installedVersion();
    final req = await _client.getUrl(Uri.parse(kReleasesApi));
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == HttpStatus.notFound) return null; // 仲未有 release
    if (res.statusCode != HttpStatus.ok) throw HttpException('GitHub ${res.statusCode}');
    final release = ReleaseInfo.fromGitHub(jsonDecode(body) as Map<String, dynamic>);
    return release != null && release.build > installed.build ? release : null;
  }

  /// 下載 APK 去 cache/updates（FileProvider 只開放呢個資料夾）。
  Future<String> download(ReleaseInfo release, {required String cacheDir, void Function(double)? onProgress}) async {
    final dir = Directory(p.join(cacheDir, 'updates'));
    if (dir.existsSync()) dir.deleteSync(recursive: true); // 清走舊嘅下載
    dir.createSync(recursive: true);
    final file = File(p.join(dir.path, 'money-manager-${release.build}.apk'));

    final req = await _client.getUrl(Uri.parse(release.apkUrl));
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok) throw HttpException('下載失敗 ${res.statusCode}');
    final total = res.contentLength > 0 ? res.contentLength : release.apkSize;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && received != total) throw const HttpException('下載唔完整，請再試');
    return file.path;
  }

  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  Future<void> openInstallSettings() => _channel.invokeMethod('openInstallSettings');

  Future<void> install(String apkPath) => _channel.invokeMethod('installApk', {'path': apkPath});
}
