import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../domain/auto_capture.dart';
import '../domain/capture.dart';
import '../domain/ledger.dart';
import '../providers.dart';
import 'common.dart';
import 'entry_screen.dart';
import 'transactions_screen.dart';

final autoCaptureProvider = Provider<AutoCapture>(
  (ref) => AutoCapture(
    ref.watch(databaseProvider),
    CaptureService(ref.watch(ledgerProvider)),
    dataDir: ref.watch(appPathsProvider).root,
  ),
);

final pendingProvider = StreamProvider.autoDispose<List<TxView>>((ref) async* {
  final ledger = ref.watch(ledgerProvider);
  Future<List<TxView>> load() => ledger.transactions(status: EntryStatus.pending);
  yield await load();
  await for (final _ in ledger.db.tableUpdates()) {
    yield await load();
  }
});

final hasGeminiKeyProvider = FutureProvider.autoDispose<bool>(
  (ref) async => (await ref.watch(autoCaptureProvider).apiKey())?.isNotEmpty ?? false,
);

/// 開 App / 返嚟 App 時處理排隊嘅通知。同一時間只跑一次。
bool _processing = false;
Future<void> processPendingNotifications(WidgetRef ref, {ScaffoldMessengerState? messenger}) async {
  if (_processing) return;
  _processing = true;
  try {
    final r = await ref.read(autoCaptureProvider).processNotifications();
    if (r != null && r.added > 0) {
      final auto = await ref.read(autoCaptureProvider).autoPost();
      messenger?.showSnackBar(SnackBar(content: Text(auto ? '自動記低咗 ${r.added} 筆' : '有 ${r.added} 筆新嘅待確認')));
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('自動記賬出錯：$e')));
  } finally {
    _processing = false;
  }
}

/// 首頁「待確認」卡。
class PendingCard extends ConsumerWidget {
  const PendingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingProvider).value ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.inbox),
        title: Text('${pending.length} 筆自動記錄待確認'),
        subtitle: const Text('撳入去睇吓啱唔啱'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())),
      ),
    );
  }
}

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingProvider);
    final accounts = ref.watch(accountMapProvider);
    final ledger = ref.read(ledgerProvider);
    final list = pending.value ?? const <TxView>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('待確認'),
        actions: [
          IconButton(
            tooltip: '由截圖匯入',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: () => importScreenshotsFlow(context, ref),
          ),
          if (list.isNotEmpty)
            TextButton(
              onPressed: () async {
                for (final t in list) {
                  await ledger.confirmEntry(t.entry.id);
                }
              },
              child: const Text('全部確認'),
            ),
        ],
      ),
      body: asyncBody(
        pending,
        (list) => list.isEmpty
            ? const EmptyState('冇待確認嘅記錄', icon: Icons.inbox_outlined)
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = list[i];
                  return Dismissible(
                    key: ValueKey(t.entry.id),
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: const Text('唔要'),
                    ),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => ledger.deleteEntry(t.entry.id),
                    child: _PendingTile(t, accounts: accounts),
                  );
                },
              ),
      ),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile(this.tx, {required this.accounts});
  final TxView tx;
  final Map<String, Account> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = tx.entry;
    final source = switch (e.source) {
      EntrySource.notification => '通知',
      EntrySource.email => '電郵',
      EntrySource.import => '截圖',
      _ => '自動',
    };
    final when =
        '${e.occurredAt.month}月${e.occurredAt.day}日 '
        '${e.occurredAt.hour.toString().padLeft(2, '0')}:${e.occurredAt.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TxTile(tx, accounts: accounts),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  [?e.merchant, when, source].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryScreen(existing: tx))),
                child: const Text('改'),
              ),
              FilledButton.tonal(
                onPressed: () => ref.read(ledgerProvider).confirmEntry(e.id),
                child: const Text('✓ 確認'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 揀賬戶 → 揀截圖 → Gemini 讀 → 入待確認。
Future<void> importScreenshotsFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final capture = ref.read(autoCaptureProvider);
  if ((await capture.apiKey())?.isNotEmpty != true) {
    messenger.showSnackBar(const SnackBar(content: Text('請先喺 設定 › 自動記賬 輸入 Gemini API key')));
    return;
  }
  if (!context.mounted) return;
  final funds = fundAccounts(ref.read(accountMapProvider).values);
  // 八達通 / 錢包排頭
  funds.sort((a, b) => (b.subtype == AccountSubtype.ewallet ? 1 : 0) - (a.subtype == AccountSubtype.ewallet ? 1 : 0));
  final account = await pickAccount(context, funds, title: '截圖係邊個賬戶嘅紀錄？');
  if (account == null) return;
  final files = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 1600);
  if (files.isEmpty || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Gemini 讀緊截圖…')),
          ],
        ),
      ),
    ),
  );
  final nav = Navigator.of(context, rootNavigator: true);
  try {
    final images = [for (final f in files) (await f.readAsBytes(), f.mimeType ?? 'image/jpeg')];
    final r = await capture.importScreenshots(images, accountId: account.id);
    nav.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          [
            '新增 ${r.added} 筆',
            if (r.duplicates > 0) '${r.duplicates} 筆之前記過',
            if (r.skipped > 0) '${r.skipped} 筆讀唔到',
          ].join('，'),
        ),
      ),
    );
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('匯入失敗：$e')));
  }
}

// ------------------------------------------------------------------ 設定

class AutoCaptureSettingsScreen extends ConsumerStatefulWidget {
  const AutoCaptureSettingsScreen({super.key});

  @override
  ConsumerState<AutoCaptureSettingsScreen> createState() => _AutoCaptureSettingsScreenState();
}

class _AutoCaptureSettingsScreenState extends ConsumerState<AutoCaptureSettingsScreen> with WidgetsBindingObserver {
  bool? access;
  List<String> allowed = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 由系統設定返嚟就再睇吓開咗權限未
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final c = ref.read(autoCaptureProvider);
    try {
      final a = await c.notificationAccessGranted();
      final pk = await c.allowedPackages();
      if (mounted) {
        setState(() {
          access = a;
          allowed = pk;
        });
      }
    } catch (_) {
      if (mounted) setState(() => access = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const {};
    final hasKey = ref.watch(hasGeminiKeyProvider).value ?? false;
    final accounts = ref.watch(accountMapProvider);
    final db = ref.read(databaseProvider);
    final capture = ref.read(autoCaptureProvider);
    final defaultFund = accounts[settings[SettingKeys.captureDefaultFund]];

    return Scaffold(
      appBar: AppBar(title: const Text('自動記賬')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '讀你揀嘅 App 嘅付款通知同交易紀錄截圖，用 Gemini 認出金額、商戶同分類，'
              '再放入「待確認」等你撳 ✓。通知同截圖嘅內容會送去 Google Gemini 分析。',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Gemini API key'),
            subtitle: Text(hasKey ? '已設定 · 模型 ${settings[SettingKeys.geminiModel] ?? '-'}' : '未設定（必須）'),
            trailing: hasKey ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.chevron_right),
            onTap: () => _editKey(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fact_check_outlined),
            title: const Text('記低之前要我確認'),
            subtitle: const Text('關咗就直接入賬（之後都可以改 / 刪）'),
            value: settings[SettingKeys.captureMode] != 'auto',
            onChanged: (v) => db.setSetting(SettingKeys.captureMode, v ? 'confirm' : 'auto'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('認唔到賬戶時用'),
            subtitle: Text(defaultFund?.name ?? '第一個賬戶'),
            onTap: () async {
              final a = await pickAccount(context, fundAccounts(accounts.values));
              if (a != null) await db.setSetting(SettingKeys.captureDefaultFund, a.id);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('讀通知權限'),
            subtitle: Text(switch (access) {
              null => '檢查緊…',
              true => '已開啟',
              false => '未開啟：撳入去，喺清單開「記錄課金 自動記賬」',
            }),
            trailing: access == true
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.chevron_right),
            onTap: capture.openNotificationAccessSettings,
          ),
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('讀邊啲 App 嘅通知'),
            subtitle: Text(allowed.isEmpty ? '未揀（揀銀行、信用卡、八達通、PayMe、Google Play…）' : '已揀 ${allowed.length} 個 App'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const _AppPickerScreen()));
              _refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('即刻處理通知'),
            subtitle: const Text('平時開 App 會自動處理'),
            onTap: () => processPendingNotifications(ref, messenger: ScaffoldMessenger.of(context)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_photo_alternate_outlined),
            title: const Text('由截圖匯入'),
            subtitle: const Text('例如八達通 App 嘅交易紀錄；重複嘅紀錄會自動略過'),
            onTap: () => importScreenshotsFlow(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _editKey(BuildContext context) async {
    final capture = ref.read(autoCaptureProvider);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final hasKey = ref.read(hasGeminiKeyProvider).value ?? false;
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Gemini API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('喺 aistudio.google.com 攞。條 key 只會加密存喺呢部手機。'),
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
          ],
        ),
        actions: [
          if (hasKey) TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('移除')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('儲存')),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      if (result.trim().isEmpty) {
        await capture.clearApiKey();
        messenger.showSnackBar(const SnackBar(content: Text('已移除 API key')));
      } else {
        final model = await capture.saveApiKey(result);
        messenger.showSnackBar(SnackBar(content: Text('API key 可以用（$model）')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    ref.invalidate(hasGeminiKeyProvider);
  }
}

/// 揀要讀通知嘅 App；銀行 / 錢包 / 商店類嘅會預先建議。
class _AppPickerScreen extends ConsumerStatefulWidget {
  const _AppPickerScreen();

  @override
  ConsumerState<_AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends ConsumerState<_AppPickerScreen> {
  List<({String package, String label})>? apps;
  Set<String> selected = {};
  String query = '';

  static final _suggest = RegExp(
    r'bank|銀行|pay|wallet|錢包|八達通|octopus|card|信用卡|hsbc|滙豐|匯豐|中銀|boc|恒生|hang ?seng|citi|花旗|渣打|'
    r'standard chartered|dbs|星展|東亞|bea|大新|dah sing|mox|za bank|welab|airstar|fusion|livi|ant bank|alipay|支付寶|'
    r'tap ?& ?go|google play|play store|amex|american express|aeon|wewa|earnmore',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = ref.read(autoCaptureProvider);
    final list = await c.launchableApps();
    final current = (await c.allowedPackages()).toSet();
    setState(() {
      apps = list;
      selected = current.isNotEmpty
          ? current
          : {
              for (final a in list)
                if (_suggest.hasMatch('${a.label} ${a.package}') || a.package == 'com.android.vending') a.package,
            };
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = apps;
    final shown = list == null
        ? const <({String package, String label})>[]
        : (list
              .where((a) => query.isEmpty || '${a.label} ${a.package}'.toLowerCase().contains(query.toLowerCase()))
              .toList()
            ..sort((a, b) => (selected.contains(b.package) ? 1 : 0) - (selected.contains(a.package) ? 1 : 0)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('讀邊啲 App 嘅通知'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(autoCaptureProvider).setAllowedPackages(selected.toList());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('只會讀已剔嘅 App。唔好揀 WhatsApp / WeChat 等聊天 App，免得私人訊息送去分析。'),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搵 App'),
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final a in shown)
                        CheckboxListTile(
                          value: selected.contains(a.package),
                          title: Text(a.label),
                          subtitle: Text(a.package, style: Theme.of(context).textTheme.bodySmall),
                          onChanged: (v) =>
                              setState(() => v == true ? selected.add(a.package) : selected.remove(a.package)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
