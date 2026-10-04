import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/domain/app_icon_lookup.dart';
import 'package:money_manager/ui/app_spending_screen.dart';

void main() {
  testWidgets('搵圖示畫面：名似嘅預先剔咗，儲存', (tester) async {
    final dir = Directory.systemTemp.createTempSync('icons');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = AppIconStore(dir.path);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appIconStoreProvider.overrideWithValue(store),
          appIconLookupProvider.overrideWithValue(_FakeLookup()),
        ],
        child: const MaterialApp(home: FindIconsScreen(['碧藍航線', '神魔之塔', '舊遊戲'])),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('碧藍航線 · App Store'), findsOneWidget);
    expect(find.text('未揀'), findsOneWidget); // 神魔之塔：名唔似，唔會自動揀
    expect(find.textContaining('搵唔到'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('用 1 個圖示'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    final saved = await tester.runAsync(() => store.load(['碧藍航線', '神魔之塔']));
    expect(saved!.keys, ['碧藍航線']);
  });
}

class _FakeLookup extends AppIconLookup {
  @override
  Future<List<IconCandidate>> search(String name) async => switch (name) {
    '碧藍航線' => const [IconCandidate(title: '碧藍航線', iconUrl: 'https://x/1', store: 'App Store')],
    '神魔之塔' => const [IconCandidate(title: 'Tower of Saviors', iconUrl: 'https://x/2', store: 'Google Play')],
    _ => const [],
  };

  @override
  Future<Uint8List?> download(String url) async => Uint8List.fromList(utf8.encode(url));
}
