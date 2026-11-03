// ignore_for_file: invalid_use_of_visible_for_testing_member

// Renders the main screens to PNGs with real fonts (for the README and for
// eyeballing changes):  flutter test screenshots/ --update-goldens
// Needs the Roboto and Material Icons fonts from the Flutter SDK cache.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todomd/core/day.dart';
import 'package:todomd/core/store.dart';
import 'package:todomd/main.dart';
import 'package:todomd/ui/settings.dart';

const notes = {
  'home.md': '''# Home

- [ ] Sort the kitchen !2026-11-01 #home
  - [x] Fix the tap x2026-10-29
    - [x] Call a plumber x2026-10-28
  - [ ] Clean counter tops ~15m #home #quick
  - [ ] Take bins out ~2m
- [/] Paint the hallway ~2d
- [ ] Renew car insurance !2026-10-28 #admin
- [ ] Buy christmas presents !2026-12-20 ~3h
- [-] Fix the old shed -2026-10-20
''',
  'work/project.md': '''# Project

- [/] Write the release notes !2026-10-31 ~1h
- [ ] Review open PRs ~30m
  - [ ] Parser fix
  - [x] CI workflow x2026-10-30
- [ ] Plan next sprint !2026-11-04
- [x] Ship 0.1.0 x2026-10-31
''',
  'work/ideas.md': '''- [ ] Weekly view for the agenda ~1w
- [ ] Recurring tasks
''',
};

Future<void> loadFonts() async {
  final cache = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f.startsWith('/') ? f : '$cache/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf'];
  await load('Roboto', roboto);
  // Android's "monospace" (task syntax in the help sheets), if installed here.
  const mono = '/usr/share/fonts/droid/DroidSansMono.ttf';
  if (File(mono).existsSync()) await load('monospace', [mono]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  late Directory tmp;
  late TaskStore store;

  setUpAll(() async {
    await loadFonts();
  });

  Future<void> boot(WidgetTester tester, String theme, {int tab = 0, int states = 0x3}) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    todayFn = () => dayOf(2026, 10, 31);
    tmp = Directory(Directory.systemTemp.createTempSync('todomd_shots').resolveSymbolicLinksSync());
    notes.forEach((rel, text) {
      final f = File('${tmp.path}/notes/$rel');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    });
    SharedPreferences.setMockInitialValues({
      'directories': ['${tmp.path}/notes'],
      'view/theme': theme,
      'view/tab': tab,
      'filter/states': states,
      'views/list': '[{"name":"This week","filter":"due:overdue OR due:week"},{"name":"Home","filter":"#home OR #admin"}]',
    });
    final settings = await Settings.load();
    store = TaskStore()..watching = false;
    await tester.runAsync(() => store.setRoots(['${tmp.path}/notes']));
    await tester.pumpWidget(TodoApp(settings: settings, store: store));
    await tester.pumpAndSettle();
    addTearDown(() {
      store.dispose();
      tmp.deleteSync(recursive: true);
    });
  }

  Future<void> shot(String name) => expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));

  for (final theme in ['light', 'soft', 'dark', 'clean', 'midnight', 'paper']) {
    testWidgets('tasks $theme', (tester) async {
      await boot(tester, theme, states: 0xF);
      await shot('tasks-$theme');
    });
  }

  testWidgets('agenda', (tester) async {
    await boot(tester, 'light', tab: 1);
    await shot('agenda-light');
  });

  testWidgets('calendar', (tester) async {
    await boot(tester, 'light', tab: 2);
    await shot('calendar-light');
  });

  testWidgets('selection', (tester) async {
    await boot(tester, 'light');
    final g = await tester.startGesture(tester.getCenter(find.text('Paint the hallway')));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveTo(tester.getCenter(find.text('Buy christmas presents')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    await shot('selection-light');
  });

  testWidgets('sheet', (tester) async {
    await boot(tester, 'light');
    await tester.tap(find.text('Sort the kitchen'));
    await tester.pumpAndSettle();
    await shot('sheet-light');
  });

  testWidgets('add', (tester) async {
    await boot(tester, 'light');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addText')), 'Book the dentist ~15m');
    await tester.tap(find.byKey(const ValueKey('due-Tomorrow')));
    await tester.pumpAndSettle();
    await shot('add-light');
  });

  testWidgets('views', (tester) async {
    await boot(tester, 'light');
    await tester.tap(find.byKey(const Key('viewTitle')));
    await tester.pumpAndSettle();
    await shot('views-light');
    await tester.tap(find.byKey(const ValueKey('editView-Home')));
    await tester.pumpAndSettle();
    await shot('view-edit-light');
  });

  testWidgets('status', (tester) async {
    await boot(tester, 'light');
    final t = tester.getRect(find.text('Take bins out'));
    await tester.tapAt(Offset(t.left - 15, t.center.dy + 6)); // its checkbox
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300)); // the fade-in
    await shot('status-light');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('filter help', (tester) async {
    await boot(tester, 'light');
    await tester.tap(find.byTooltip('How to filter'));
    await tester.pumpAndSettle();
    await shot('filter-help-light');
  });

  testWidgets('help', (tester) async {
    await boot(tester, 'light');
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    await shot('help-light');
  });

  // For the README (resized into docs/screenshots by tool/readme_shots.py).
  group('readme', () {
    testWidgets('tasks', (tester) async {
      await boot(tester, 'midnight');
      await shot('readme-tasks');
    });
    testWidgets('agenda', (tester) async {
      await boot(tester, 'midnight', tab: 1);
      await shot('readme-agenda');
    });
    testWidgets('task', (tester) async {
      await boot(tester, 'midnight');
      await tester.tap(find.text('Sort the kitchen'));
      await tester.pumpAndSettle();
      await shot('readme-task');
    });
    testWidgets('calendar', (tester) async {
      await boot(tester, 'midnight', tab: 2);
      await shot('readme-calendar');
    });
  });
}
