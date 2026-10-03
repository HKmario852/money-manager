import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/domain/updater.dart';

Map<String, dynamic> release({String tag = 'build-42', List<Map<String, dynamic>>? assets}) => {
  'tag_name': tag,
  'name': 'v1.0.0 (42)',
  'body': '  ## What\'s Changed\n* App 內更新  ',
  'assets':
      assets ??
      [
        {'name': 'money-manager.apk', 'browser_download_url': 'https://example.com/money-manager.apk', 'size': 1234},
      ],
};

void main() {
  test('parses a CI release', () {
    final r = ReleaseInfo.fromGitHub(release())!;
    expect(r.build, 42);
    expect(r.title, 'v1.0.0 (42)');
    expect(r.notes, "## What's Changed\n* App 內更新");
    expect(r.apkUrl, 'https://example.com/money-manager.apk');
    expect(r.apkSize, 1234);
  });

  test('ignores releases that are not CI builds', () {
    expect(ReleaseInfo.fromGitHub(release(tag: 'v1.0.0')), isNull);
    expect(ReleaseInfo.fromGitHub(release(tag: 'build-x')), isNull);
  });

  test('ignores releases without the APK asset', () {
    expect(ReleaseInfo.fromGitHub(release(assets: [])), isNull);
    expect(
      ReleaseInfo.fromGitHub(
        release(assets: [
          {'name': 'notes.txt', 'browser_download_url': 'https://example.com/notes.txt', 'size': 1},
        ]),
      ),
      isNull,
    );
  });
}
