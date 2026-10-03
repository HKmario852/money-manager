import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/domain/update.dart';

void main() {
  Map<String, dynamic> release({String tag = 'build-42', List<Map<String, dynamic>>? assets, bool draft = false}) => {
    'tag_name': tag,
    'name': 'v1.0.0 (build 42)',
    'draft': draft,
    'prerelease': false,
    'body':
        "<!-- Release notes generated using configuration -->\n## What's Changed\n"
        '* 自動記錄 by @HKmario852 in https://github.com/HKmario852/money-manager/pull/4\n\n'
        '**Full Changelog**: https://github.com/HKmario852/money-manager/compare/build-41...build-42',
    'assets':
        assets ??
        [
          {
            'name': 'money-manager-1.0.0-build42.apk',
            'browser_download_url': 'https://github.com/HKmario852/money-manager/releases/download/build-42/x.apk',
            'size': 1234,
            'digest': 'sha256:ABCDEF',
          },
        ],
  };

  test('讀 GitHub release', () {
    final r = parseRelease(release())!;
    expect(r.build, 42);
    expect(r.name, 'v1.0.0 (build 42)');
    expect(r.size, 1234);
    expect(r.sha256, 'abcdef');
    expect(r.notes, '• 自動記錄');
  });

  test('唔啱嘅 release 唔理', () {
    expect(parseRelease(release(tag: 'v1.0.0')), isNull);
    expect(parseRelease(release(draft: true)), isNull);
    expect(parseRelease(release(assets: [])), isNull);
    // 只接受 github.com 嘅 https 下載
    expect(
      parseRelease(
        release(
          assets: [
            {'name': 'a.apk', 'browser_download_url': 'http://example.com/a.apk', 'size': 1},
          ],
        ),
      ),
      isNull,
    );
  });
}
