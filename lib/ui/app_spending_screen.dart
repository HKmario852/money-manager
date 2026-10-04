import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../domain/app_icon_lookup.dart';
import '../domain/app_spending.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'capture_screens.dart';
import 'common.dart';
import 'theme.dart';
import 'transactions_screen.dart';

const _appsChannel = MethodChannel('hk.mario.money_manager/apps');

final appIconStoreProvider = Provider<AppIconStore>((ref) => AppIconStore(ref.watch(appPathsProvider).root));

final appIconLookupProvider = Provider<AppIconLookup>((ref) {
  final lookup = AppIconLookup();
  ref.onDispose(lookup.close);
  return lookup;
});

/// App 圖示（按 App 名搵）：自己揀咗 / 網上搵咗嘅優先，其次電話上裝咗嘅。
final appIconsProvider = FutureProvider.family<Map<String, Uint8List>, String>((ref, joinedNames) async {
  if (joinedNames.isEmpty) return const {};
  final names = joinedNames.split('\n');
  var installed = const <String, Uint8List>{};
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      installed = await _appsChannel.invokeMapMethod<String, Uint8List>('icons', names) ?? const {};
    } catch (_) {}
  }
  final saved = await ref.watch(appIconStoreProvider).load(names);
  return {...installed, ...saved};
});

/// 課金 / 訂閱 / 遊戲嘅支出，按 App 分組。
final appSpendingProvider = Provider.autoDispose.family<AsyncValue<List<AppSpend>>, (DateTime?, DateTime?)>((
  ref,
  range,
) {
  final accounts = ref.watch(accountMapProvider);
  final TxFilter filter = (
    from: range.$1,
    to: range.$2,
    accountId: null,
    categoryId: null,
    tagId: null,
    kind: EntryKind.expense,
    search: null,
    limit: null,
  );
  return ref.watch(transactionsProvider(filter)).whenData((txs) => groupByApp(txs, appCategoryIds(accounts.values)));
});

String _iconKey(Iterable<AppSpend> apps) => (apps.map((a) => a.name).toList()..sort()).join('\n');

/// App 圖示；搵唔到就用 App 名第一個字（同分類方塊一樣）。
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, this.icon, {super.key, this.size = 40});
  final String name;
  final Uint8List? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    if (icon != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(icon!, width: size, height: size, gaplessPlayback: true),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.lime, borderRadius: radius),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: AppColors.limeInk, fontSize: size * 0.45, fontWeight: FontWeight.w800, height: 1),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow(this.app, this.icon, this.max, {required this.onTap});
  final AppSpend app;
  final Uint8List? icon;
  final int max;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AppIcon(app.name, icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(formatMoney(app.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : app.total / max,
                      minHeight: 6,
                      color: AppColors.ink,
                      backgroundColor: AppColors.track,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${app.purchases.length} 筆 · 最近 ${formatDate(app.last!, withYear: true)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 統計頁：今期邊個 App 用最多錢。
class AppSpendingCard extends ConsumerWidget {
  const AppSpendingCard(this.range, {super.key});
  final (DateTime, DateTime) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appSpendingProvider((range.$1, range.$2))).value ?? const <AppSpend>[];
    if (apps.isEmpty) return const SizedBox();
    final top = apps.take(5).toList();
    final icons = ref.watch(appIconsProvider(_iconKey(top))).value ?? const {};
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SectionCard(
        title: 'App 課金',
        trailing: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSpendingScreen())),
          child: const Text('全部'),
        ),
        child: Column(
          children: [
            for (final a in top)
              _AppRow(
                a,
                icons[a.name],
                top.first.total,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailScreen(a.name))),
              ),
          ],
        ),
      ),
    );
  }
}

enum _Span { month, year, all }

class AppSpendingScreen extends ConsumerStatefulWidget {
  const AppSpendingScreen({super.key});

  @override
  ConsumerState<AppSpendingScreen> createState() => _AppSpendingScreenState();
}

class _AppSpendingScreenState extends ConsumerState<AppSpendingScreen> {
  _Span span = _Span.all;

  @override
  Widget build(BuildContext context) {
    final startDay = ref.watch(monthStartDayProvider);
    final now = DateTime.now();
    final (DateTime?, DateTime?) range = switch (span) {
      _Span.month => unitRange(PeriodUnit.month, now, startDay),
      _Span.year => unitRange(PeriodUnit.year, now, startDay),
      _Span.all => (null, null),
    };
    final apps = ref.watch(appSpendingProvider(range));
    final icons = ref.watch(appIconsProvider(_iconKey(apps.value ?? const []))).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('App 課金')),
      body: asyncBody(apps, (list) {
        final total = list.fold(0, (s, a) => s + a.total);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PillSegment<_Span>(
                options: const {_Span.month: '今個月', _Span.year: '今年', _Span.all: '全部'},
                value: span,
                onChanged: (v) => setState(() => span = v),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${list.length} 個 App · ${list.fold(0, (s, a) => s + a.purchases.length)} 筆',
                    style: const TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BigMoney(total, color: Colors.white, dimColor: const Color(0xFF8C9099)),
                  ),
                ],
              ),
            ),
            const _PendingHint(),
            if (apps.value != null && list.isNotEmpty)
              _MissingIconsHint([
                for (final a in list)
                  if (!icons.containsKey(a.name) && a.name != '未註明 App') a.name,
              ], loaded: ref.watch(appIconsProvider(_iconKey(list))).hasValue),
            const SizedBox(height: 6),
            if (list.isEmpty)
              const EmptyState('呢段時間未有課金、訂閱或者買 App 嘅記錄', icon: Icons.sports_esports_outlined)
            else
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    for (final a in list)
                      _AppRow(
                        a,
                        icons[a.name],
                        list.first.total,
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailScreen(a.name))),
                      ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// 一個 App 嘅所有購買。
class AppDetailScreen extends ConsumerWidget {
  const AppDetailScreen(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appSpendingProvider((null, null)));
    final accounts = ref.watch(accountMapProvider);
    final icon = ref.watch(appIconsProvider(name)).value?[name];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: asyncBody(apps, (list) {
        final app = list.where((a) => a.name == name).firstOrNull;
        if (app == null) return const EmptyState('冇記錄', icon: Icons.sports_esports_outlined);
        final year = DateTime.now().year;
        final thisYear = app.purchases.where((t) => t.entry.occurredAt.year == year).fold(0, (s, t) => s + t.amount);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Row(
                children: [
                  GestureDetector(onTap: () => changeAppIcon(context, ref, name), child: AppIcon(name, icon, size: 56)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '總共用咗',
                          style: TextStyle(color: Color(0xFFB9BDC4), fontWeight: FontWeight.w600),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: BigMoney(app.total, color: Colors.white, dimColor: const Color(0xFF8C9099), size: 36),
                        ),
                        Text(
                          '${app.purchases.length} 筆 · $year 年 ${formatMoney(thisYear)}',
                          style: const TextStyle(color: Color(0xFFB9BDC4)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [for (final t in app.purchases) TxTile(t, accounts: accounts)]),
            ),
          ],
        );
      }),
    );
  }
}

/// 匯入咗但未入帳嘅課金唔計入面，提一提。
class _PendingHint extends ConsumerWidget {
  const _PendingHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountMapProvider);
    final ids = appCategoryIds(accounts.values);
    final pending = (ref.watch(pendingCapturesProvider).value ?? const <Capture>[])
        .where((c) => ids.contains(c.categoryId))
        .length;
    if (pending == 0) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppCard(
        color: AppColors.peach,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptureInboxScreen())),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '仲有 $pending 筆課金等確認，入帳之後先會計入呢度',
                style: const TextStyle(color: AppColors.peachInk, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.peachInk),
          ],
        ),
      ),
    );
  }
}

/// 有 App 未有圖示：提用戶上網搵。
class _MissingIconsHint extends StatelessWidget {
  const _MissingIconsHint(this.names, {required this.loaded});
  final List<String> names;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    if (!loaded || names.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FindIconsScreen(names))),
        child: Row(
          children: [
            const Icon(Icons.image_search_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${names.length} 個 App 未有圖示，上網搵', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// 撳 App 圖示：上網搵、由相簿揀、或者用返預設。
Future<void> changeAppIcon(BuildContext context, WidgetRef ref, String name) async {
  final store = ref.read(appIconStoreProvider);
  final hasSaved = (await store.load([name])).isNotEmpty;
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image_search_outlined),
            title: const Text('上網搵圖示'),
            onTap: () => Navigator.pop(context, 'search'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('由相簿揀'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          if (hasSaved)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('用返預設'),
              onTap: () => Navigator.pop(context, 'reset'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'search':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FindIconsScreen([name])));
    case 'gallery':
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 192, maxHeight: 192);
      if (file == null) return;
      await store.save(name, await file.readAsBytes());
      ref.invalidate(appIconsProvider);
    case 'reset':
      await store.remove(name);
      ref.invalidate(appIconsProvider);
  }
}

/// 逐個 App 上網搵圖示，名似嘅預先剔咗，用戶確認先儲存。
class FindIconsScreen extends ConsumerStatefulWidget {
  const FindIconsScreen(this.names, {super.key});
  final List<String> names;

  @override
  ConsumerState<FindIconsScreen> createState() => _FindIconsScreenState();
}

class _FindIconsScreenState extends ConsumerState<FindIconsScreen> {
  final results = <String, List<IconCandidate>>{};
  final chosen = <String, int>{};
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final lookup = ref.read(appIconLookupProvider);
    for (final name in widget.names) {
      final found = await lookup.search(name);
      if (!mounted) return;
      setState(() {
        results[name] = found;
        // 淨係得一個 App 嗰陣用戶自己揀咗要搵，第一個就預先揀咗
        if (found.isNotEmpty && (widget.names.length == 1 || namesMatch(name, found.first.title))) chosen[name] = 0;
      });
    }
  }

  Future<void> _pick(String name) async {
    final found = results[name] ?? const [];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('邊個係 $name？', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (var i = 0; i < found.length; i++)
              ListTile(
                leading: _NetIcon(found[i].iconUrl),
                title: Text(found[i].title),
                subtitle: Text(found[i].store),
                trailing: chosen[name] == i ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, i),
              ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('都唔係'),
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => picked < 0 ? chosen.remove(name) : chosen[name] = picked);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final lookup = ref.read(appIconLookupProvider);
    final store = ref.read(appIconStoreProvider);
    var saved = 0;
    for (final e in chosen.entries) {
      final bytes = await lookup.download(results[e.key]![e.value].iconUrl);
      if (bytes == null) continue;
      await store.save(e.key, bytes);
      saved++;
    }
    ref.invalidate(appIconsProvider);
    if (!mounted) return;
    final failed = chosen.length - saved;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('加咗 $saved 個圖示${failed > 0 ? '，$failed 個下載唔到' : ''}')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final searching = results.length < widget.names.length;
    return Scaffold(
      appBar: AppBar(title: const Text('搵 App 圖示')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            searching
                ? '喺 App Store 同 Google Play 搵緊（${results.length}/${widget.names.length}）…'
                : '剔咗嘅會用。撳一行可以揀第二個，或者揀「都唔係」。',
            style: const TextStyle(color: AppColors.muted),
          ),
          if (searching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Column(
              children: [
                for (final name in widget.names)
                  if (results[name] case final found?) _row(name, found),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: searching || saving || chosen.isEmpty ? null : _save,
            child: Text(saving ? '下載緊…' : '用 ${chosen.length} 個圖示'),
          ),
        ),
      ),
    );
  }

  Widget _row(String name, List<IconCandidate> found) {
    final i = chosen[name];
    final c = i == null ? null : found[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: c == null ? AppIcon(name, null) : _NetIcon(c.iconUrl),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        found.isEmpty ? '搵唔到（可能已經落架），可以喺 App 頁由相簿揀' : (c == null ? '未揀' : '${c.title} · ${c.store}'),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: found.isEmpty
          ? null
          : Checkbox(value: c != null, onChanged: (v) => v == true ? _pick(name) : setState(() => chosen.remove(name))),
      onTap: found.isEmpty ? null : () => _pick(name),
    );
  }
}

class _NetIcon extends StatelessWidget {
  const _NetIcon(this.url);
  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.network(
      url,
      width: 40,
      height: 40,
      errorBuilder: (_, _, _) =>
          const SizedBox(width: 40, height: 40, child: Icon(Icons.broken_image_outlined, color: AppColors.muted)),
    ),
  );
}
