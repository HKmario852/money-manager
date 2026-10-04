import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../domain/backup.dart';
import '../providers.dart';
import 'capture_screens.dart';
import 'common.dart';
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
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('儲蓄率目標'),
            subtitle: const Text('統計頁會同你嘅實際儲蓄率比較'),
            trailing: DropdownButton<int>(
              value: ref.watch(savingsTargetProvider),
              underline: const SizedBox(),
              items: [for (var p = 0; p <= 90; p += 5) DropdownMenuItem(value: p, child: Text('$p%'))],
              onChanged: (v) => v != null ? db.setSetting(SettingKeys.savingsTarget, '$v') : null,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.receipt_long_outlined),
            title: const Text('只記支出'),
            subtitle: const Text('收埋淨資產同帳戶結餘，帳戶淨係用嚟分付款方法'),
            value: settings[SettingKeys.spendingOnly] == 'true',
            onChanged: (v) => db.setSetting(SettingKeys.spendingOnly, '$v'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('私隱鎖'),
            subtitle: const Text('開 App 要用指紋 / Face ID 解鎖'),
            value: lock,
            onChanged: (v) async {
              if (v && !await LocalAuthentication().isDeviceSupported()) {
                if (context.mounted) showError(context, '部機未設定鎖屏密碼或者指紋，開唔到私隱鎖');
                return;
              }
              if (v && !await authenticateUser('確認開啟私隱鎖')) return;
              await db.setSetting(SettingKeys.biometricLock, '$v');
            },
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
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('自動記錄'),
            subtitle: const Text('讀付款通知、Gmail 收據，Gemini 幫手分類'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const AutoCaptureSettingsScreen()),
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
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('檢查更新'),
            subtitle: Text(switch (ref.watch(packageInfoProvider).value) {
              final i? => '目前版本 ${i.version}（build ${i.buildNumber}）',
              null => ' ',
            }),
            onTap: () => checkForUpdate(context, ref, manual: true),
          ),
        ],
      ),
    );
  }
}

/// 問匯出密碼（可以留空）。返回 null = 取消。
Future<String?> _askExportPassword(BuildContext context) {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('備份密碼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('設密碼會用 AES 加密個備份檔。留空就唔加密。忘記密碼就冇辦法還原。'),
            const SizedBox(height: 12),
            TextField(
              controller: first,
              obscureText: true,
              decoration: const InputDecoration(hintText: '密碼（可留空）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: second,
              obscureText: true,
              decoration: InputDecoration(hintText: '再輸入一次', errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (first.text != second.text) {
                setState(() => error = '兩次輸入唔一樣');
                return;
              }
              Navigator.pop(c, first.text);
            },
            child: const Text('匯出'),
          ),
        ],
      ),
    ),
  );
}

Future<void> exportAndShare(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final password = await _askExportPassword(context);
  if (password == null) return;
  try {
    final tmp = await getTemporaryDirectory();
    final zip = await exportBackup(
      ref.read(databaseProvider),
      attachmentsDir: ref.read(appPathsProvider).attachments,
      tempDir: tmp.path,
      password: password,
    );
    await SharePlus.instance.share(ShareParams(files: [XFile(zip)], subject: 'Money Expense 備份'));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
  }
}

Future<void> restoreFromBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
  final path = files.firstOrNull?.path;
  if (path == null || !context.mounted) return;
  String? password;
  try {
    if (await isEncryptedBackup(path)) {
      if (!context.mounted) return;
      password = await promptText(context, '輸入備份密碼', obscure: true);
      if (password == null) return;
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('還原失敗：$e')));
    return;
  }
  if (!context.mounted) return;
  if (!await confirm(context, '還原備份？', message: '而家所有記錄會被備份入面嘅數據取代。', ok: '還原')) return;
  final tmp = await getTemporaryDirectory();
  final db = ref.read(databaseProvider);
  final String unpacked;
  try {
    // 先解壓同檢查，冇問題先關資料庫覆蓋
    unpacked = await unpackBackup(path, tempDir: tmp.path, password: password, maxSchemaVersion: db.schemaVersion);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('還原失敗：$e')));
    return;
  }
  try {
    final paths = ref.read(appPathsProvider);
    await db.close();
    await applyBackup(unpacked, databasePath: paths.database, attachmentsDir: paths.attachments);
    ref.invalidate(databaseProvider);
    messenger.showSnackBar(const SnackBar(content: Text('已還原')));
  } catch (e) {
    ref.invalidate(databaseProvider);
    messenger.showSnackBar(SnackBar(content: Text('還原失敗，已保留原本數據：$e')));
  }
}
