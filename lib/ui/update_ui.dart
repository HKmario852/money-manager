import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../domain/update.dart';
import '../providers.dart';
import 'common.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// 自動檢查最多一日一次。
const _autoInterval = Duration(hours: 24);

/// 檢查新版本。[manual] = 用戶喺設定撳「檢查更新」：冇新版本都會話佢知，亦唔理「略過呢個版本」。
Future<void> checkForUpdate(BuildContext context, WidgetRef ref, {bool manual = false}) async {
  final updater = Updater();
  if (!updater.supported) {
    updater.close();
    if (manual) showError(context, 'iPhone 版要經 App Store / TestFlight 更新');
    return;
  }
  final db = ref.read(databaseProvider);
  try {
    if (!manual) {
      final last = int.tryParse(await db.getSetting(SettingKeys.updateLastCheck) ?? '');
      if (last != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < _autoInterval) {
        return;
      }
    }
    final info = await ref.read(packageInfoProvider.future);
    final current = int.tryParse(info.buildNumber) ?? 0;
    final AppRelease? release;
    try {
      release = await updater.latest();
    } on UpdateException catch (e) {
      if (manual && context.mounted) showError(context, e.message);
      return;
    }
    await db.setSetting(SettingKeys.updateLastCheck, '${DateTime.now().millisecondsSinceEpoch}');
    if (!context.mounted) return;
    if (release == null || release.build <= current) {
      if (manual) showError(context, '已經係最新版本（build $current）');
      return;
    }
    if (!manual && await db.getSetting(SettingKeys.updateSkippedBuild) == '${release.build}') return;
    if (!context.mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('有新版本 build ${release!.build}'),
        content: SingleChildScrollView(
          child: Text(
            [
              '而家用緊 build $current。',
              if (release.notes.isNotEmpty) '\n${release.notes}',
              '\n下載大約 ${(release.size / 1024 / 1024).toStringAsFixed(0)} MB，你嘅記錄會保留。',
            ].join('\n'),
          ),
        ),
        actions: [
          if (!manual) TextButton(onPressed: () => Navigator.pop(c, 'skip'), child: const Text('略過呢版')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('稍後')),
          FilledButton(onPressed: () => Navigator.pop(c, 'update'), child: const Text('更新')),
        ],
      ),
    );
    if (choice == 'skip') await db.setSetting(SettingKeys.updateSkippedBuild, '${release.build}');
    if (choice != 'update' || !context.mounted) return;

    final progress = ValueNotifier<double?>(null);
    final job = getTemporaryDirectory().then(
      (dir) => updater.download(release!, dir, onProgress: (p) => progress.value = p),
    );
    final apk = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        job.then(
          (f) {
            if (c.mounted) Navigator.pop(c, f);
          },
          onError: (Object e) {
            if (c.mounted) Navigator.pop(c, e);
          },
        );
        return AlertDialog(
          title: const Text('下載緊新版本'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: p),
                const SizedBox(height: 8),
                Text(p == null ? '連接緊…' : '${(p * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        );
      },
    );
    progress.dispose();
    if (!context.mounted) return;
    if (apk is! File) {
      showError(context, apk ?? '下載失敗');
      return;
    }
    try {
      if (!await updater.install(apk) && context.mounted) {
        showError(context, '請喺打開咗嘅設定頁允許「記錄課金」安裝應用程式，返嚟再撳一次「檢查更新」。');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  } finally {
    updater.close();
  }
}
