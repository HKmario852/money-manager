import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database_key.dart';
import 'providers.dart';
import 'ui/database_problem_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final paths = await AppPaths.resolve();
  await _start(paths);
}

/// 攞到資料庫金鑰先開 App；攞唔到就顯示原因同選擇，唔會自動刪除數據。
Future<void> _start(AppPaths paths) async {
  switch (await loadAppDatabaseKey(paths)) {
    case DatabaseKeyReady(:final key):
      runApp(
        ProviderScope(
          overrides: [appPathsProvider.overrideWithValue(paths), databaseKeyProvider.overrideWithValue(key)],
          child: const MoneyApp(),
        ),
      );
    case final problem:
      runApp(
        DatabaseProblemApp(
          problem: problem,
          onRetry: () => _start(paths),
          onStartOver: () {
            setAsideUnreadableDatabase(paths.database);
            _start(paths);
          },
        ),
      );
  }
}
