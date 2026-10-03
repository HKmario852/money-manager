import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../domain/backup.dart';
import '../providers.dart';
import 'common.dart';
import 'capture_ui.dart';
import 'manage_screens.dart';
import 'update_ui.dart';

const kCurrencies = ['HKD', 'CNY', 'TWD', 'MOP', 'USD', 'JPY', 'GBP', 'EUR', 'SGD'];

Future<bool> authenticateUser(String reason) async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return true; // 冇鎖屏嘅裝置唔阻用戶
    return await auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
  } catch (_) {
    return false;
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const {};
    final db = ref.read(databaseProvider);
    final lock = settings[SettingKeys.biometricLock] == 'true';
    final startDay = ref.watch(monthStartDayProvider);
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('基準貨幣'),
            subtitle: const Text('多幣種會喺下一階段加入'),
            trailing: DropdownButton<String>(
              value: settings[SettingKeys.baseCurrency] ?? 'HKD',
              underline: const SizedBox(),
              items: [for (final c in kCurrencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => v != null ? db.setSetting(SettingKeys.baseCurrency, v) : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text('每月由幾號開始計'),
            subtitle: const Text('例如出糧日係 25 號，可以揀 25'),
            trailing: DropdownButton<int>(
              value: startDay,
              underline: const SizedBox(),
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d 號'))],
              onChanged: (v) => v != null ? db.setSetting(SettingKeys.monthStartDay, '$v') : null,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('私隱鎖'),
            subtitle: const Text('開 App 要用指紋 / Face ID 解鎖'),
            value: lock,
            onChanged: (v) async {
              if (v && !await authenticateUser('確認開啟私隱鎖')) return;
              await db.setSetting(SettingKeys.biometricLock, '$v');
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('自動記賬'),
            subtitle: const Text('讀付款通知、八達通截圖，用 Gemini 自動記'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const AutoCaptureSettingsScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('分類'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const CategoriesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Tag'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const TagsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.bolt),
            title: const Text('常用模板'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const TemplatesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('匯出備份'),
            subtitle: const Text('打包所有記錄同收據相，可以存去 Google Drive / iCloud'),
            onTap: () => exportAndShare(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('由備份還原'),
            subtitle: const Text('會覆蓋而家所有數據'),
            onTap: () => restoreFromBackup(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('檢查更新'),
            subtitle: Text('而家版本 ${ref.watch(installedVersionProvider).value ?? ''}'),
            onTap: () => checkForUpdateManually(context, ref),
          ),
        ],
      ),
    );
  }
}

Future<void> exportAndShare(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final tmp = await getTemporaryDirectory();
    final zip = await exportBackup(
      ref.read(databaseProvider),
      attachmentsDir: ref.read(appPathsProvider).attachments,
      tempDir: tmp.path,
    );
    await SharePlus.instance.share(ShareParams(files: [XFile(zip)], subject: '記錄課金備份'));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
  }
}

Future<void> restoreFromBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
  final path = files.firstOrNull?.path;
  if (path == null || !context.mounted) return;
  if (!await confirm(context, '還原備份？', message: '而家所有記錄會被備份入面嘅數據取代，冇得復原。', ok: '還原')) return;
  try {
    final tmp = await getTemporaryDirectory();
    final unpacked = await unpackBackup(path, tempDir: tmp.path);
    final paths = ref.read(appPathsProvider);
    await ref.read(databaseProvider).close();
    await applyBackup(unpacked, databasePath: paths.database, attachmentsDir: paths.attachments);
    ref.invalidate(databaseProvider);
    messenger.showSnackBar(const SnackBar(content: Text('已還原')));
  } catch (e) {
    ref.invalidate(databaseProvider);
    messenger.showSnackBar(SnackBar(content: Text('還原失敗：$e')));
  }
}
