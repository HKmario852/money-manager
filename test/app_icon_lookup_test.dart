import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/domain/app_icon_lookup.dart';

const appleJson = '''
{"resultCount":2,"results":[
 {"trackName":"Azur Lane","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/b/AppIcon/100x100bb.jpg"},
 {"trackName":"碧藍航線","artworkUrl512":"https://is1-ssl.mzstatic.com/image/thumb/c/d/AppIcon/512x512bb.jpg"}
]}''';

const playSearch = '''
<html><a href="/store/apps/details?id=com.example.azur">x</a>
<a href="/store/apps/details?id=com.example.azur">y</a>
<a href="/store/apps/details?id=com.example.other">z</a></html>''';

String playDetails(String title, String icon) =>
    '<html><head><meta property="og:title" content="$title - Google Play 應用程式">'
    '<meta property="og:image" content="$icon=w240-h480-rw"></head></html>';

void main() {
  test('App Store 結果轉 128px 圖示', () {
    final r = parseAppleSearch(appleJson);
    expect(r.map((c) => c.title), ['Azur Lane', '碧藍航線']);
    expect(r[1].iconUrl, 'https://is1-ssl.mzstatic.com/image/thumb/c/d/AppIcon/128x128bb.png');
    expect(parseAppleSearch('not json'), isEmpty);
  });

  test('Play 搜尋頁攞套件名，App 頁攞 og 標題同圖示', () {
    expect(playPackageIds(playSearch), ['com.example.azur', 'com.example.other']);
    final c = parsePlayDetails(playDetails('碧藍航線 &amp; 朋友', 'https://play-lh.googleusercontent.com/abc'))!;
    expect(c.title, '碧藍航線 & 朋友');
    expect(c.iconUrl, 'https://play-lh.googleusercontent.com/abc=s128');
    expect(parsePlayDetails('<html></html>'), isNull);
  });

  test('名似唔似', () {
    expect(namesMatch('碧藍航線', '碧藍航線'), true);
    expect(namesMatch('MARVEL Future Fight', 'MARVEL Future Fight: Heroes'), true);
    expect(namesMatch('神魔之塔', 'Tower of Saviors'), false);
  });

  test('上網搵：兩邊都搵，名一樣嘅排先；下載圖示', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final path = req.uri.path;
      final res = req.response;
      if (path == '/search') {
        res.write(appleJson);
      } else if (path == '/store/search') {
        res.write(playSearch);
      } else if (path == '/store/apps/details') {
        final id = req.uri.queryParameters['id'];
        res.write(
          id == 'com.example.azur'
              ? playDetails('碧藍航線', 'https://play-lh.googleusercontent.com/azur')
              : playDetails('Other Game', 'https://play-lh.googleusercontent.com/other'),
        );
      } else if (path == '/icon') {
        res.add([1, 2, 3]);
      } else {
        res.statusCode = 404;
      }
      res.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final lookup = AppIconLookup(appleBase: base, playBase: base);
    addTearDown(lookup.close);
    final found = await lookup.search('碧藍航線');
    expect(found.first.title, '碧藍航線');
    expect(found.map((c) => c.title), containsAll(['Azur Lane', 'Other Game']));
    // 同名嘅兩邊只留一個
    expect(found.where((c) => c.title == '碧藍航線'), hasLength(1));
    expect(
      found.firstWhere((c) => c.title == 'Other Game').iconUrl,
      'https://play-lh.googleusercontent.com/other=s128',
    );
    expect(await lookup.download('$base/icon'), [1, 2, 3]);
    expect(await lookup.download('$base/missing'), isNull);
  });

  test('冇網就返回空', () async {
    final lookup = AppIconLookup(appleBase: 'http://127.0.0.1:1', playBase: 'http://127.0.0.1:1');
    addTearDown(lookup.close);
    expect(await lookup.search('碧藍航線'), isEmpty);
  });

  test('圖示存喺 App 資料夾', () async {
    final dir = await Directory.systemTemp.createTemp('icons');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppIconStore(dir.path);
    await store.save('碧藍航線', Uint8List.fromList([9]));
    expect((await store.load(['碧藍航線', '神魔之塔'])).keys, ['碧藍航線']);
    await store.remove('碧藍航線');
    expect(await store.load(['碧藍航線']), isEmpty);
  });
}
