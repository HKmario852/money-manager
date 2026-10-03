import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();
  runApp(ProviderScope(overrides: [appPathsProvider.overrideWithValue(paths)], child: const MoneyApp()));
}
