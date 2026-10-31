import 'package:flutter/material.dart';

import 'core/store.dart';
import 'ui/home.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  runApp(TodoApp(settings: settings, store: TaskStore()));
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.settings, required this.store});
  final Settings settings;
  final TaskStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final t = settings.theme;
        return MaterialApp(
          title: 'todo.md',
          debugShowCheckedModeBanner: false,
          theme: switch (t) {
            AppTheme.soft => softTheme(),
            AppTheme.dark => darkTheme(),
            _ => lightTheme(),
          },
          darkTheme: darkTheme(),
          themeMode: switch (t) {
            AppTheme.system => ThemeMode.system,
            AppTheme.dark => ThemeMode.dark,
            _ => ThemeMode.light,
          },
          home: HomePage(store: store, settings: settings),
        );
      },
    );
  }
}
