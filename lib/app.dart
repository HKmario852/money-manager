import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'domain/ledger.dart';
import 'domain/money.dart';
import 'providers.dart';
import 'ui/accounts_screen.dart';
import 'ui/common.dart';
import 'ui/entry_screen.dart';
import 'ui/home_screen.dart';
import 'ui/reports_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/transactions_screen.dart';
import 'ui/update_ui.dart';

class MoneyApp extends StatelessWidget {
  const MoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B), brightness: b),
      useMaterial3: true,
    );
    return MaterialApp(
      title: '記錄課金',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: const Locale('zh', 'HK'),
      supportedLocales: const [Locale('zh', 'HK'), Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Gate(),
    );
  }
}

/// 未解鎖嘅狀態。開咗私隱鎖先會用到。
class UnlockState extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final unlockedProvider = NotifierProvider<UnlockState, bool>(UnlockState.new);

class _Gate extends ConsumerStatefulWidget {
  const _Gate();

  @override
  ConsumerState<_Gate> createState() => _GateState();
}

class _GateState extends ConsumerState<_Gate> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        // 離開超過一分鐘就再鎖
        if (_hiddenAt != null && DateTime.now().difference(_hiddenAt!) > const Duration(minutes: 1)) {
          ref.read(unlockedProvider.notifier).set(false);
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return asyncBody(settings, (s) {
      if (s[SettingKeys.onboarded] != 'true') return const OnboardingScreen();
      if (s[SettingKeys.biometricLock] == 'true' && !ref.watch(unlockedProvider)) return const LockScreen();
      return const HomeShell();
    });
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int index = 0;

  static const _pages = [HomeScreen(), TransactionsScreen(), ReportsScreen(), AccountsScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => autoCheckForUpdate(context, ref));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add-entry',
        tooltip: '記一筆',
        shape: const CircleBorder(),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntryScreen())),
        child: const Icon(Icons.add, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _tab(0, Icons.home_outlined, Icons.home, '首頁'),
            _tab(1, Icons.receipt_long_outlined, Icons.receipt_long, '交易'),
            const SizedBox(width: 72),
            _tab(2, Icons.pie_chart_outline, Icons.pie_chart, '報表'),
            _tab(3, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, '賬戶'),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i, IconData icon, IconData selected, String label) {
    final active = index == i;
    final color = active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? selected : icon, color: color),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (await authenticateUser('解鎖記錄課金')) {
      ref.read(unlockedProvider.notifier).set(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('記錄課金已上鎖'),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('解鎖')),
          ],
        ),
      ),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String currency = 'HKD';
  final name = TextEditingController(text: '現金');
  final balance = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    balance.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final db = ref.read(databaseProvider);
    try {
      await ref
          .read(ledgerProvider)
          .createFundAccount(
            name: name.text.trim().isEmpty ? '現金' : name.text.trim(),
            type: AccountType.asset,
            subtype: AccountSubtype.cash,
            openingBalance: parseMinor(balance.text.trim()) ?? 0,
          );
      await db.setSetting(SettingKeys.baseCurrency, currency);
      await db.setSetting(SettingKeys.onboarded, 'true');
    } on LedgerException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Icon(Icons.savings, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('歡迎使用記錄課金', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('先設定基準貨幣同第一個賬戶，之後隨時可以加多啲。', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: '基準貨幣'),
              items: [for (final c in kCurrencies) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => currency = v ?? 'HKD'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '第一個賬戶'),
            ),
            TextField(
              controller: balance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '銀包而家有幾多錢', prefixText: '\$ '),
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: _finish, child: const Text('開始記賬')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => restoreFromBackup(context, ref), child: const Text('我有備份，由備份還原')),
          ],
        ),
      ),
    );
  }
}
