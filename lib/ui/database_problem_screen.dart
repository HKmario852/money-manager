import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/database_key.dart';
import 'theme.dart';

/// 開唔到資料庫時顯示：金鑰唔見咗（[DatabaseKeyMissing]）或者讀唔到 secure storage（[DatabaseKeyUnavailable]）。
/// 唔會自動刪除任何數據。
class DatabaseProblemApp extends StatelessWidget {
  const DatabaseProblemApp({super.key, required this.problem, required this.onRetry, required this.onStartOver});

  final DatabaseKeyResult problem;
  final VoidCallback onRetry;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final missing = problem is DatabaseKeyMissing;
    return MaterialApp(
      title: 'Money Expense',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('zh', 'HK'),
      supportedLocales: const [Locale('zh', 'HK'), Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(missing ? '開唔到記帳資料' : '暫時讀唔到加密金鑰', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(
                    missing
                        ? '記帳資料已加密，但手機入面嘅金鑰唔見咗（例如清除咗 App 部分數據）。冇金鑰就無法讀取呢份資料。\n\n'
                              '「重新開始」會將開唔到嘅資料改名留喺手機（唔會刪除），再開一個新嘅空白帳簿；之後可以喺「設定 › 還原備份」用之前匯出嘅備份還原。'
                        : 'Android 嘅安全儲存暫時讀唔到（${(problem as DatabaseKeyUnavailable).error}）。數據冇改動，請稍後再試，或者重新開機後再開 App。',
                  ),
                  const Spacer(),
                  if (missing)
                    FilledButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('重新開始？'),
                            content: const Text('開唔到嘅資料會改名留低，App 會用一個新嘅空白帳簿開啟。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('重新開始')),
                            ],
                          ),
                        );
                        if (ok == true) onStartOver();
                      },
                      child: const Text('重新開始'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onRetry, child: const Text('再試一次')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
