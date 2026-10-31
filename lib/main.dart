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
          // Everything a touch smaller than stock: scale all text on top of
          // the system font size.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(data: mq.copyWith(textScaler: _Scaled(mq.textScaler, 0.93)), child: child!);
          },
        );
      },
    );
  }
}

class _Scaled extends TextScaler {
  const _Scaled(this.inner, this.factor);
  final TextScaler inner;
  final double factor;

  @override
  double scale(double fontSize) => inner.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => inner.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is _Scaled && other.inner == inner && other.factor == factor;

  @override
  int get hashCode => Object.hash(inner, factor);
}
