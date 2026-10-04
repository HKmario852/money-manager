import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'capture/parser.dart';

/// 網上搵到嘅 App 圖示。
class IconCandidate {
  const IconCandidate({required this.title, required this.iconUrl, required this.store});
  final String title;
  final String iconUrl;

  /// App Store / Google Play
  final String store;
}

/// 用 App 名上網搵圖示：先 App Store（有正式 API），再 Google Play（讀網頁嘅 og:image）。
/// Takeout 冇套件名，所以淨係可以靠名搵，要用戶確認先會用。
class AppIconLookup {
  AppIconLookup({
    HttpClient? client,
    this.appleBase = 'https://itunes.apple.com',
    this.playBase = 'https://play.google.com',
  }) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final HttpClient _client;
  final String appleBase;
  final String playBase;

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 15; SM-A556E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';

  /// 最多 5 個，名最似嘅排先。搵唔到或者冇網就返回空。
  Future<List<IconCandidate>> search(String name) async {
    final found = <IconCandidate>[];
    try {
      found.addAll(await _apple(name));
    } catch (_) {}
    try {
      found.addAll(await _play(name));
    } catch (_) {}
    final seen = <String>{};
    final unique = [
      for (final c in found)
        if (seen.add(merchantKey(c.title))) c,
    ];
    unique.sort((a, b) => _score(name, b.title).compareTo(_score(name, a.title)));
    return unique.take(5).toList();
  }

  Future<List<IconCandidate>> _apple(String name) async {
    final uri = Uri.parse('$appleBase/search')
        .replace(queryParameters: {'term': name, 'country': 'hk', 'entity': 'software', 'limit': '3'});
    final text = await _get(uri);
    return text == null ? const [] : parseAppleSearch(text);
  }

  Future<List<IconCandidate>> _play(String name) async {
    final search = Uri.parse('$playBase/store/search')
        .replace(queryParameters: {'q': name, 'c': 'apps', 'hl': 'zh_HK', 'gl': 'HK'});
    final html = await _get(search);
    if (html == null) return const [];
    final out = <IconCandidate>[];
    for (final id in playPackageIds(html).take(2)) {
      final page = await _get(
        Uri.parse('$playBase/store/apps/details').replace(queryParameters: {'id': id, 'hl': 'zh_HK', 'gl': 'HK'}),
      );
      final c = page == null ? null : parsePlayDetails(page);
      if (c != null) out.add(c);
    }
    return out;
  }

  Future<String?> _get(Uri uri) async {
    final req = await _client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-HK,zh;q=0.9,en;q=0.8');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await res.transform(utf8.decoder).join();
    return res.statusCode == 200 ? text : null;
  }

  /// 下載圖示（細過 1MB）。
  Future<Uint8List?> download(String url) async {
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res) {
        bytes.add(chunk);
        if (bytes.length > 1024 * 1024) return null;
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close(force: true);
}

/// App Store Search API 嘅 JSON。
List<IconCandidate> parseAppleSearch(String text) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } catch (_) {
    return const [];
  }
  final results = data is Map ? data['results'] : null;
  if (results is! List) return const [];
  return [
    for (final r in results.whereType<Map<String, dynamic>>())
      if (r['trackName'] case final String title)
        if ((r['artworkUrl512'] ?? r['artworkUrl100']) case final String url)
          IconCandidate(
            title: title,
            // 512 太大，攞 128 就夠
            iconUrl: url.replaceFirst(RegExp(r'/\d+x\d+bb\.(\w+)$'), '/128x128bb.png'),
            store: 'App Store',
          ),
  ];
}

/// Play 搜尋結果頁入面嘅套件名（按出現次序）。
List<String> playPackageIds(String html) {
  final ids = <String>[];
  for (final m in RegExp(r'/store/apps/details\?id=([A-Za-z0-9_.]+)').allMatches(html)) {
    final id = m.group(1)!;
    if (!ids.contains(id)) ids.add(id);
  }
  return ids;
}

/// Play App 頁嘅 og:title / og:image。
IconCandidate? parsePlayDetails(String html) {
  String? meta(String property) {
    final tag = RegExp('<meta[^>]+property="og:$property"[^>]*>').firstMatch(html)?.group(0);
    final content = tag == null ? null : RegExp(r'content="([^"]*)"').firstMatch(tag)?.group(1);
    return content == null ? null : _unescape(content);
  }

  final image = meta('image');
  var title = meta('title');
  if (image == null || title == null || !image.startsWith('https://')) return null;
  // 「碧藍航線 - Google Play 應用程式」→「碧藍航線」
  title = title.replaceFirst(RegExp(r'\s*[-–]\s*(?:Google Play|Apps on Google Play).*$'), '').trim();
  return IconCandidate(
    title: title,
    iconUrl: '${image.replaceFirst(RegExp(r'=[^/=]*$'), '')}=s128',
    store: 'Google Play',
  );
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// 搵到嘅名同 App 名夠唔夠似（一樣、或者一個包住另一個）。
bool namesMatch(String appName, String found) {
  final a = merchantKey(appName);
  final b = merchantKey(found);
  if (a.isEmpty || b.isEmpty) return false;
  return a == b || (a.length >= 2 && b.contains(a)) || (b.length >= 2 && a.contains(b));
}

int _score(String name, String title) {
  final a = merchantKey(name);
  final b = merchantKey(title);
  if (a == b) return 3;
  if (namesMatch(name, title)) return 2;
  return 0;
}

/// 用戶揀咗 / 網上搵到嘅圖示，存喺 App 資料夾。
class AppIconStore {
  AppIconStore(String root) : dir = Directory(p.join(root, 'app_icons'));
  final Directory dir;

  File _file(String name) {
    final key = sha1.convert(utf8.encode(merchantKey(name).isEmpty ? name : merchantKey(name))).toString();
    return File(p.join(dir.path, '$key.img'));
  }

  Future<Map<String, Uint8List>> load(Iterable<String> names) async {
    final out = <String, Uint8List>{};
    for (final n in names) {
      final f = _file(n);
      if (await f.exists()) out[n] = await f.readAsBytes();
    }
    return out;
  }

  Future<void> save(String name, Uint8List bytes) async {
    await dir.create(recursive: true);
    await _file(name).writeAsBytes(bytes, flush: true);
  }

  Future<void> remove(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}
