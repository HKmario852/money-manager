import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../domain/capture/capture_service.dart';
import '../domain/capture/gemini.dart';
import '../domain/capture/sources.dart';
import '../domain/capture/takeout.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';
import 'entry_screen.dart';
import 'theme.dart';

/// 首頁嘅「待確認」卡。冇嘢等確認就唔顯示。
class PendingCapturesCard extends ConsumerWidget {
  const PendingCapturesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCapturesProvider).value ?? const <Capture>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final total = pending.fold(0, (s, c) => s + (c.isIncome ? 0 : (c.amount ?? 0)));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppCard(
        color: AppColors.lime,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureInboxScreen())),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${pending.length} 筆自動記錄待確認', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (total > 0) Text('合共 ${formatMoney(total)}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class CaptureInboxScreen extends ConsumerStatefulWidget {
  const CaptureInboxScreen({super.key});

  @override
  ConsumerState<CaptureInboxScreen> createState() => _CaptureInboxScreenState();
}

class _CaptureInboxScreenState extends ConsumerState<CaptureInboxScreen> {
  bool syncing = false;

  Future<void> _sync() async {
    setState(() => syncing = true);
    final report = await ref.read(captureSyncProvider).run(force: true);
    if (!mounted) return;
    setState(() => syncing = false);
    final msg = [
      if (report.added > 0) '新增 ${report.added} 筆',
      if (report.autoConfirmed > 0) '自動入帳 ${report.autoConfirmed} 筆',
      ...report.errors,
    ];
    showError(context, msg.isEmpty ? '冇新記錄' : msg.join('\n'));
  }

  Future<void> _confirm(Capture c) async {
    try {
      await ref.read(captureServiceProvider).confirm(c);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit(Capture c) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryScreen(
          seed: EntrySeed(
            kind: c.isTransfer ? EntryKind.transfer : (c.isIncome ? EntryKind.income : EntryKind.expense),
            occurredAt: c.occurredAt,
            amount: c.amount,
            categoryId: c.isTransfer ? null : c.categoryId,
            fundId: c.isTransfer ? c.categoryId : c.fundAccountId,
            toFundId: c.isTransfer ? c.fundAccountId : null,
            merchant: c.merchant,
            note: c.merchant == null ? c.title : null,
          ),
        ),
      ),
    );
    if (id == null) return;
    final tx = await ref.read(ledgerProvider).transaction(id);
    final kind = tx?.entry.kind;
    await ref
        .read(captureServiceProvider)
        .markConfirmed(
          c,
          entryId: id,
          // 增值記住「由邊個賬戶」，支出 / 收入記住分類
          categoryId: tx == null
              ? null
              : (kind == EntryKind.transfer ? (c.isTransfer ? tx.from.id : null) : tx.category.id),
          fundId: tx == null ? null : (kind == EntryKind.income || kind == EntryKind.transfer ? tx.to.id : tx.from.id),
        );
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingCapturesProvider);
    final accounts = ref.watch(accountMapProvider);
    final ready = (pending.value ?? const <Capture>[])
        .where((c) => c.amount != null && c.categoryId != null && c.fundAccountId != null)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('待確認'),
        actions: [
          IconButton(
            tooltip: '匯入八達通截圖',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: () => importOctopusScreenshots(context, ref, openInbox: false),
          ),
          IconButton(
            tooltip: '重新整理',
            onPressed: syncing ? null : _sync,
            icon: syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '自動記錄設定',
            icon: const Icon(Icons.tune),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoCaptureSettingsScreen())),
          ),
        ],
      ),
      body: asyncBody(pending, (list) {
        if (list.isEmpty) return const EmptyState('冇嘢等確認', icon: Icons.done_all);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (ready.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: FilledButton.icon(
                  onPressed: () async {
                    final total = ready.fold(0, (s, c) => s + (c.amount ?? 0));
                    if (ready.length > 5 &&
                        !await confirm(
                          context,
                          '全部入帳？',
                          message: '${ready.length} 筆，共 ${formatMoney(total)}',
                          ok: '入帳',
                        )) {
                      return;
                    }
                    for (final c in ready) {
                      await _confirm(c);
                    }
                  },
                  icon: const Icon(Icons.done_all, color: AppColors.lime),
                  label: Text('全部入帳（${ready.length} 筆已填好）'),
                ),
              ),
            for (final c in list)
              Dismissible(
                key: ValueKey(c.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Text('略過', style: TextStyle(color: AppColors.muted)),
                ),
                onDismissed: (_) => ref.read(captureServiceProvider).dismiss(c.id),
                child: _CaptureCard(
                  c,
                  accounts: accounts,
                  onConfirm: () => _confirm(c),
                  onEdit: () => _edit(c),
                  onDismiss: () => ref.read(captureServiceProvider).dismiss(c.id),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '向左掃或者撳「略過」唔記。你改過嘅分類同賬戶，下次同一個商戶會自動用返。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _CaptureCard extends ConsumerWidget {
  const _CaptureCard(
    this.c, {
    required this.accounts,
    required this.onConfirm,
    required this.onEdit,
    required this.onDismiss,
  });
  final Capture c;
  final Map<String, Account> accounts;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = accounts[c.categoryId];
    final fund = accounts[c.fundAccountId];
    final service = ref.read(captureServiceProvider);
    final ready = c.amount != null && category != null && fund != null;
    final foreign = c.currency != null && c.currency != 'HKD';

    Future<void> pickCategory() async {
      if (c.isTransfer) {
        final options = fundAccounts(accounts.values).where((a) => a.id != c.fundAccountId).toList();
        final picked = await pickAccount(context, options, title: '由邊個賬戶增值？');
        if (picked != null) await service.update(c.id, categoryId: picked.id);
        return;
      }
      final type = c.isIncome ? AccountType.income : AccountType.expense;
      final options = accounts.values.where((a) => a.type == type && !a.isArchived).toList()
        ..sort((a, b) => categoryPath(a, accounts).compareTo(categoryPath(b, accounts)));
      final picked = await pickAccount(context, options, title: '揀分類');
      if (picked != null) await service.update(c.id, categoryId: picked.id);
    }

    Future<void> pickFund() async {
      final picked = await pickAccount(context, fundAccounts(accounts.values), title: '揀賬戶');
      if (picked == null) return;
      final others = await service.setFund(c, picked.id);
      if (others > 0 && context.mounted) {
        showError(context, '另外 $others 筆${c.sourceLabel ?? ''}都用咗「${picked.name}」');
      }
    }

    Widget chip(Account? a, String placeholder, VoidCallback onTap) => ActionChip(
      avatar: a != null ? AccountAvatar(a, radius: 10) : const Icon(Icons.add, size: 16),
      label: Text(a != null ? (isFund(a.type) ? a.name : categoryPath(a, accounts)) : placeholder),
      backgroundColor: a != null ? AppColors.chip : AppColors.peach,
      onPressed: onTap,
    );

    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (c.source) {
                  EntrySource.email => Icons.mail_outline,
                  EntrySource.import => Icons.photo_outlined,
                  _ => Icons.notifications_none,
                },
                size: 16,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${c.sourceLabel ?? c.sourceKey} · ${formatDate(c.occurredAt)} ${formatTime(c.occurredAt)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c.parsedBy == ParsedBy.gemini) const Pill('Gemini', background: AppColors.chip),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  c.merchant ?? c.title ?? '未知商戶',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                c.amount == null
                    ? '未讀到金額'
                    : '${c.isTransfer ? '⇄ ' : (c.isIncome ? '+' : '-')}${foreign ? '${c.currency} ' : moneySymbol}${minorToInput(c.amount!)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: c.amount == null ? 13 : 18,
                  color: c.amount == null
                      ? AppColors.orange
                      : (c.isTransfer ? AppColors.muted : (c.isIncome ? incomeColor : expenseColor)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (foreign)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('外幣：請撳「修改」改做港幣金額', style: TextStyle(color: AppColors.orange, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [chip(category, '揀分類', pickCategory), chip(fund, '揀賬戶', pickFund)]),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: onDismiss, child: const Text('略過')),
              const Spacer(),
              OutlinedButton(onPressed: onEdit, child: const Text('修改')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: ready && !foreign ? onConfirm : null,
                icon: const Icon(Icons.check, color: AppColors.lime),
                label: const Text('入帳'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 自動記錄設定：通知讀取、Gmail 收據、Gemini、自動入帳。
class AutoCaptureSettingsScreen extends ConsumerStatefulWidget {
  const AutoCaptureSettingsScreen({super.key});

  @override
  ConsumerState<AutoCaptureSettingsScreen> createState() => _AutoCaptureSettingsScreenState();
}

class _AutoCaptureSettingsScreenState extends ConsumerState<AutoCaptureSettingsScreen> with WidgetsBindingObserver {
  bool granted = false;
  List<SeenApp> apps = const [];
  Set<String> allowed = {};

  NotificationBridge get bridge => ref.read(notificationBridgeProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 由系統設定返嚟，重新睇權限
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final g = await bridge.isGranted();
    final a = await bridge.seenApps();
    final al = await bridge.allowedApps();
    if (!mounted) return;
    setState(() {
      granted = g;
      apps = a;
      allowed = al;
    });
  }

  Future<void> _toggleApp(String pkg, bool on) async {
    final next = {...allowed};
    on ? next.add(pkg) : next.remove(pkg);
    await bridge.setAllowedApps(next);
    setState(() => allowed = next);
  }

  Future<String> _token() async {
    final db = ref.read(databaseProvider);
    var token = await db.getSetting(SettingKeys.gmailScriptToken);
    if (token == null || token.isEmpty) {
      final r = Random.secure();
      const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      token = List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
      await db.setSetting(SettingKeys.gmailScriptToken, token);
    }
    return token;
  }

  Future<void> _copyScript() async {
    final token = await _token();
    await Clipboard.setData(ClipboardData(text: gmailScriptSource(token)));
    if (mounted) showError(context, '已複製 Apps Script 程式碼（已包含你嘅密鑰）');
  }

  Future<void> _testGmail() async {
    final db = ref.read(databaseProvider);
    final url = await db.getSetting(SettingKeys.gmailScriptUrl);
    if (url == null || url.isEmpty) {
      if (mounted) showError(context, '請先貼上 Apps Script 網址');
      return;
    }
    final gmail = GmailBridge(url: url, token: await _token());
    try {
      final list = await gmail.fetch(since: DateTime.now().subtract(const Duration(days: 30)));
      if (mounted) showError(context, '連線成功，近 30 日搵到 ${list.length} 封收據');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      gmail.close();
    }
  }

  Future<void> _testGemini() async {
    final key = await ref.read(geminiKeyProvider.future);
    if (key == null) {
      if (mounted) showError(context, '請先輸入 Gemini API key');
      return;
    }
    final model = await ref.read(databaseProvider).getSetting(SettingKeys.geminiModel);
    final g = GeminiParser(apiKey: key, model: (model == null || model.isEmpty) ? defaultGeminiModel : model);
    try {
      final p = await g.parse(source: 'Test', body: '你已成功付款 HK\$38.00 予 7-Eleven', categories: const ['餐飲', '購物']);
      if (mounted) showError(context, p != null ? 'Gemini 正常：讀到 ${formatMoney(p.amount)}' : 'Gemini 有回應但讀唔到金額');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      g.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const {};
    final db = ref.read(databaseProvider);
    final hasKey = ref.watch(geminiKeyProvider).value != null;
    final auto = settings[SettingKeys.autoConfirm] == 'true';
    final url = settings[SettingKeys.gmailScriptUrl] ?? '';
    final model = settings[SettingKeys.geminiModel] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('自動記錄')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SectionCard(
            title: '手機通知',
            child: !bridge.supported
                ? const Text('iPhone 唔容許讀其他 App 嘅通知，請用 Gmail 收據。', style: TextStyle(color: AppColors.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        granted ? '已開啟通知存取權。揀邊啲 App 嘅付款通知要記：' : '要喺系統設定開「通知存取權」先讀到付款通知。',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      if (!granted)
                        FilledButton(onPressed: bridge.openSettings, child: const Text('開啟通知存取權'))
                      else if (apps.isEmpty)
                        const Text('未收過其他 App 嘅通知。用 AlipayHK 等付一次款之後返嚟呢度揀。')
                      else
                        for (final a in apps)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(a.name),
                            subtitle: a.name != a.package
                                ? Text(a.package, style: const TextStyle(fontSize: 11, color: AppColors.muted))
                                : null,
                            value: allowed.contains(a.package),
                            onChanged: (v) => _toggleApp(a.package, v),
                          ),
                      const SizedBox(height: 4),
                      const Text(
                        '只會讀你揀咗嘅 App。其他 App 淨係記低個名方便你揀，唔會讀內容。',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          SectionCard(
            title: 'Gmail 收據（Google Play）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1. 撳「複製 Script」\n'
                  '2. 電腦開 script.google.com → 新專案 → 貼上 → 儲存\n'
                  '3. 部署 → 新增部署作業 → 類型揀「網頁應用程式」，執行身分「我」，存取權「任何人」→ 部署 → 授權\n'
                  '4. 將「網頁應用程式網址」貼落下面',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _copyScript,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('複製 Script'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('gmail-$url'),
                  initialValue: url,
                  decoration: const InputDecoration(hintText: 'https://script.google.com/macros/s/…/exec'),
                  keyboardType: TextInputType.url,
                  onFieldSubmitted: (v) => db.setSetting(SettingKeys.gmailScriptUrl, v.trim()),
                  onChanged: (v) => db.setSetting(SettingKeys.gmailScriptUrl, v.trim()),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _testGmail, child: const Text('測試連線')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SectionCard(
            title: 'Google Takeout（Play 購買記錄）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1. 電腦開 takeout.google.com → 取消全選 → 只剔「Google Play 商店」\n'
                  '2. 傳送方式揀「新增至雲端硬碟」，可以揀每 2 個月自動匯出\n'
                  '3. 匯出好之後撳下面個掣，喺 Google Drive 揀個 zip\n'
                  '已經記咗或者匯入過嘅會自動略過。',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => importTakeout(context, ref),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('匯入 Takeout'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SectionCard(
            title: 'Gemini 解析',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '固定規則讀唔到嘅通知或者電郵，會將嗰段文字傳俾 Google Gemini 讀。唔設定就只用規則，讀唔到嘅要你自己填。',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(hasKey ? Icons.key : Icons.key_off),
                  title: Text(hasKey ? 'API key 已設定（加密儲存）' : '未設定 API key'),
                  trailing: TextButton(
                    onPressed: () async {
                      final v = await promptText(context, 'Gemini API key', hint: 'AIza…', obscure: true);
                      if (v != null) await ref.read(geminiKeyProvider.notifier).set(v);
                    },
                    child: Text(hasKey ? '更改' : '設定'),
                  ),
                ),
                if (hasKey)
                  TextButton(
                    onPressed: () => ref.read(geminiKeyProvider.notifier).set(null),
                    child: const Text('刪除 API key'),
                  ),
                TextFormField(
                  key: ValueKey('model-$model'),
                  initialValue: model,
                  decoration: const InputDecoration(labelText: '模型', hintText: defaultGeminiModel),
                  onChanged: (v) => db.setSetting(SettingKeys.geminiModel, v.trim()),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _testGemini, child: const Text('測試 Gemini')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AppCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自動入帳', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('分類同賬戶都認得嘅就直接入帳，唔使撳確認。'),
              value: auto,
              onChanged: (v) => db.setSetting(SettingKeys.autoConfirm, '$v'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 八達通拍卡同步餘額。[account] 係八達通資金賬戶。
Future<void> syncOctopusBalance(BuildContext context, WidgetRef ref, Account account) async {
  final bridge = ref.read(notificationBridgeProvider);
  if (!await bridge.hasNfc()) {
    if (context.mounted) showError(context, '呢部機冇 NFC，讀唔到八達通');
    return;
  }
  if (!context.mounted) return;
  final read = bridge.readOctopusBalance();
  final int? cardBalance = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      read.then(
        (v) {
          if (c.mounted) Navigator.pop(c, v);
        },
        onError: (Object e) {
          if (c.mounted) Navigator.pop(c);
          if (context.mounted && !(e is PlatformException && e.code == 'cancelled')) {
            showError(context, e is PlatformException ? (e.message ?? e.code) : e);
          }
        },
      );
      return AlertDialog(
        title: const Text('拍八達通'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.contactless, size: 56), SizedBox(height: 12), Text('將八達通貼住手機背面，唔好郁，直到讀完。')],
        ),
        actions: [
          TextButton(
            onPressed: () {
              bridge.cancelOctopus();
            },
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
  if (cardBalance == null || !context.mounted) return;

  final ledger = ref.read(ledgerProvider);
  final book = toDisplay(account.type, (await ledger.balances())[account.id] ?? 0);
  final diff = book - cardBalance;
  if (!context.mounted) return;
  if (diff == 0) {
    showError(context, '張卡餘額 ${formatMoney(cardBalance)}，同帳面一樣 👍');
    return;
  }
  final accounts = ref.read(accountsProvider).value ?? const <Account>[];
  if (diff > 0) {
    // 張卡少咗：當係未記嘅消費
    final ok = await confirm(
      context,
      '張卡餘額 ${formatMoney(cardBalance)}',
      message:
          '帳面係 ${formatMoney(book)}，少咗 ${formatMoney(diff)}。記做一筆八達通消費？之後可以喺交易入面改分類。\n\n'
          '想逐筆記低，可以先喺八達通 App 影交易紀錄，用「匯入八達通截圖」，入完帳再拍卡對數。',
      ok: '記低',
    );
    if (!ok) return;
    final transport =
        categoryByPath('交通', accounts, AccountType.expense) ??
        accounts.firstWhere((a) => a.type == AccountType.expense && !a.isArchived);
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.expense,
        amount: diff,
        fromAccountId: account.id,
        toAccountId: transport.id,
        occurredAt: DateTime.now(),
        note: '八達通拍卡對數',
      ),
    );
    if (context.mounted) showError(context, '已記低 ${formatMoney(diff)}，八達通餘額而家係 ${formatMoney(cardBalance)}');
  } else {
    // 張卡多咗：多數係增值未記
    final source = await pickAccount(
      context,
      fundAccounts(accounts).where((a) => a.id != account.id).toList(),
      title: '張卡多咗 ${formatMoney(-diff)}，係由邊個帳戶增值？',
    );
    if (source == null) {
      if (context.mounted &&
          await confirm(context, '唔揀帳戶？', message: '直接將八達通結餘改做 ${formatMoney(cardBalance)}。', ok: '調整')) {
        await ledger.adjustBalance(account.id, cardBalance);
      }
      return;
    }
    await ledger.saveEntry(
      EntryDraft(
        kind: EntryKind.transfer,
        amount: -diff,
        fromAccountId: source.id,
        toAccountId: account.id,
        occurredAt: DateTime.now(),
        note: '八達通增值',
      ),
    );
    if (context.mounted) showError(context, '已記低增值 ${formatMoney(-diff)}');
  }
}

/// 揀八達通 App「交易紀錄」截圖，用 Gemini 讀出每一筆放入待確認。
Future<void> importOctopusScreenshots(BuildContext context, WidgetRef ref, {bool openInbox = true}) async {
  if (await ref.read(geminiKeyProvider.future) == null) {
    if (context.mounted) showError(context, '要先喺「自動記錄」設定輸入 Gemini API key 先讀到截圖');
    return;
  }
  final files = await ImagePicker().pickMultiImage(limit: 10);
  if (files.isEmpty || !context.mounted) return;
  final images = <({List<int> bytes, String mimeType})>[];
  for (final f in files) {
    final name = f.name.toLowerCase();
    final mime =
        f.mimeType ?? (name.endsWith('.png') ? 'image/png' : (name.endsWith('.webp') ? 'image/webp' : 'image/jpeg'));
    images.add((bytes: await f.readAsBytes(), mimeType: mime));
  }
  if (!context.mounted) return;
  final job = ref.read(captureSyncProvider).importOctopusScreenshots(images);
  final report = await showDialog<SyncReport>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      job.then(
        (r) {
          if (c.mounted) Navigator.pop(c, r);
        },
        onError: (Object e) {
          if (c.mounted) Navigator.pop(c, SyncReport(errors: ['$e']));
        },
      );
      return AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text('Gemini 讀緊 ${images.length} 張截圖…')),
          ],
        ),
      );
    },
  );
  if (report == null || !context.mounted) return;
  final msg = [
    if (report.added > 0) '新增 ${report.added} 筆待確認',
    if (report.autoConfirmed > 0) '自動入帳 ${report.autoConfirmed} 筆',
    if (report.skipped > 0) '${report.skipped} 筆之前匯入過或者已經記咗，略過',
    ...report.errors,
  ];
  showError(context, msg.isEmpty ? '截圖入面搵唔到交易' : msg.join('\n'));
  if (openInbox && report.added > 0) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureInboxScreen()));
  }
}

/// 揀 Google Takeout zip（或者入面嘅 Play JSON），將 Play 購買放入待確認。
Future<void> importTakeout(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip', 'json']);
  final path = picked.firstOrNull?.path;
  if (path == null || !context.mounted) return;
  final List<PlayPurchase> purchases;
  try {
    purchases = await readTakeout(path);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  if (purchases.isEmpty) {
    showError(context, '入面冇要俾錢嘅 Google Play 購買');
    return;
  }

  // Takeout 包埋好多年前嘅記錄：預設只入開始用 app 之後嘅
  final since = await ref.read(captureSyncProvider).appStartedAt();
  final older = since == null ? 0 : purchases.where((p) => p.at.isBefore(since)).length;
  DateTime? cutoff;
  if (older > 0 && context.mounted) {
    final all = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('搵到 ${purchases.length} 筆 Play 購買'),
        content: Text('其中 $older 筆係 ${formatDate(since!, withYear: true)} 開始用 app 之前。要唔要都匯入？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('全部匯入')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('只入之後')),
        ],
      ),
    );
    if (all == null) return;
    if (!all) cutoff = since;
  }
  if (!context.mounted) return;

  final items = takeoutToCaptures(purchases, since: cutoff);
  final job = ref.read(captureSyncProvider).importTakeout(items);
  final report = await showDialog<SyncReport>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      job.then(
        (r) {
          if (c.mounted) Navigator.pop(c, r);
        },
        onError: (Object e) {
          if (c.mounted) Navigator.pop(c, SyncReport(errors: ['$e']));
        },
      );
      return AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text('匯入緊 ${items.length} 筆…')),
          ],
        ),
      );
    },
  );
  if (report == null || !context.mounted) return;
  final msg = [
    if (report.added > 0) '新增 ${report.added} 筆待確認',
    if (report.autoConfirmed > 0) '自動入帳 ${report.autoConfirmed} 筆',
    if (report.skipped > 0) '${report.skipped} 筆之前匯入過或者已經記咗，略過',
    ...report.errors,
  ];
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(report.added + report.autoConfirmed > 0 ? '匯入完成' : '冇新嘅購買'),
      content: Text(msg.isEmpty ? '揀咗嘅時間入面冇購買' : msg.join('\n')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('好'))],
    ),
  );
  if (report.added > 0 && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureInboxScreen()));
  }
}
