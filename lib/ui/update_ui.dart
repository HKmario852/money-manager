import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../domain/updater.dart';
import '../providers.dart';

final updaterProvider = Provider<Updater>((ref) => Updater());

final installedVersionProvider = FutureProvider<InstalledVersion>(
  (ref) => ref.read(updaterProvider).installedVersion(),
);

/// 開 App 時靜靜雞檢查，一日最多一次；用戶撳過「遲啲」嘅版本唔會再彈。
Future<void> autoCheckForUpdate(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final last = DateTime.tryParse(await db.getSetting(SettingKeys.updateLastCheck) ?? '');
  if (last != null && DateTime.now().difference(last) < const Duration(days: 1)) return;
  try {
    final release = await ref.read(updaterProvider).checkForUpdate();
    await db.setSetting(SettingKeys.updateLastCheck, DateTime.now().toIso8601String());
    final dismissed = int.tryParse(await db.getSetting(SettingKeys.updateDismissedBuild) ?? '');
    if (release == null || release.build == dismissed || !context.mounted) return;
    await _offerUpdate(context, ref, release);
  } catch (_) {
    // 冇網 / GitHub 唔得都唔好煩用戶，下次開 App 再試
  }
}

/// 設定入面手動檢查。
Future<void> checkForUpdateManually(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final release = await ref.read(updaterProvider).checkForUpdate();
    if (!context.mounted) return;
    if (release == null) {
      messenger.showSnackBar(const SnackBar(content: Text('已經係最新版本')));
      return;
    }
    await _offerUpdate(context, ref, release);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('檢查唔到更新：$e')));
  }
}

Future<void> _offerUpdate(BuildContext context, WidgetRef ref, ReleaseInfo release) async {
  final sizeMb = release.apkSize > 0 ? '（${(release.apkSize / 1024 / 1024).toStringAsFixed(1)} MB）' : '';
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('有新版本 ${release.title}'),
      content: SingleChildScrollView(
        child: Text([if (release.notes.isNotEmpty) release.notes, '更新會保留你所有記錄。$sizeMb'].join('\n\n')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('遲啲')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('更新')),
      ],
    ),
  );
  if (go != true) {
    await ref.read(databaseProvider).setSetting(SettingKeys.updateDismissedBuild, '${release.build}');
    return;
  }
  if (context.mounted) await _downloadAndInstall(context, ref, release);
}

Future<void> _downloadAndInstall(BuildContext context, WidgetRef ref, ReleaseInfo release) async {
  final updater = ref.read(updaterProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (!await updater.canInstall()) {
    if (!context.mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('要開一個權限'),
        content: const Text(
          'Android 要你批准「記錄課金」安裝 App，先可以喺 App 入面更新。\n\n'
          '撳「去設定」之後開咗「允許此來源」，再返嚟撳一次更新。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去設定')),
        ],
      ),
    );
    if (open == true) await updater.openInstallSettings();
    return;
  }

  if (!context.mounted) return;
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('下載緊新版本'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v),
              const SizedBox(height: 8),
              Text(v == null ? '連接緊…' : '${(v * 100).round()}%'),
            ],
          ),
        ),
      ),
    ),
  );
  final nav = Navigator.of(context, rootNavigator: true);
  try {
    final cache = await getTemporaryDirectory();
    final apk = await updater.download(release, cacheDir: cache.path, onProgress: (v) => progress.value = v);
    nav.pop();
    await updater.install(apk);
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('更新失敗：$e')));
  }
}
