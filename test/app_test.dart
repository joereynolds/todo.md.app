// Drives the real home screen (the desktop's tests/test_window.cpp, by touch).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todomd/core/day.dart';
import 'package:todomd/core/store.dart';
import 'package:todomd/core/task.dart';
import 'package:todomd/main.dart';
import 'package:todomd/ui/dialogs.dart';
import 'package:todomd/ui/home.dart';
import 'package:todomd/ui/settings.dart';
import 'package:todomd/ui/task_list.dart';

const initial = '- [ ] a\n- [ ] b\n  - [ ] b1\n- [ ] c\n';

late Directory tmp;
late TaskStore store;

String get file => '${tmp.path}/t.md';
String contents() => File(file).readAsStringSync();
const today = '2026-10-31';

Future<HomePageState> boot(WidgetTester tester, {String data = initial}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  todayFn = () => dayOf(2026, 10, 31);
  tmp = Directory(normalizeRoot(Directory.systemTemp.createTempSync('todomd_app').resolveSymbolicLinksSync()));
  File(file).writeAsStringSync(data);
  SharedPreferences.setMockInitialValues({
    'directories': [tmp.path],
  });
  final settings = await Settings.load();
  store = TaskStore()..watching = false;
  await tester.runAsync(() => store.setRoots([tmp.path]));
  await tester.pumpWidget(TodoApp(settings: settings, store: store));
  await tester.pumpAndSettle();
  addTearDown(() {
    store.dispose();
    tmp.deleteSync(recursive: true);
  });
  return tester.state<HomePageState>(find.byType(HomePage));
}

Finder rowText(String text) => find.descendant(of: find.byType(TaskRow), matching: find.text(text));

Offset checkbox(WidgetTester tester, String text) {
  final row = find.ancestor(of: rowText(text), matching: find.byType(TaskRow));
  final r = tester.getRect(row);
  final t = tester.getRect(rowText(text));
  return Offset(t.left - 19, r.center.dy); // the checkbox sits just left of the text
}

void main() {
  testWidgets('layout: file header, tasks, subtask indented, progress pill', (tester) async {
    final home = await boot(tester);
    expect(home.list.rows.length, 5);
    expect(home.list.rows[3].depth, 2);
    expect(find.text('t.md'), findsOneWidget);
    expect(find.text('0/4'), findsOneWidget); // file
    expect(find.text('0/1'), findsOneWidget); // b
  });

  testWidgets('checkbox toggles a task and its subtasks; undo restores', (tester) async {
    await boot(tester);
    await tester.tapAt(checkbox(tester, 'b'));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a\n- [x] b x$today\n  - [x] b1 x$today\n- [ ] c\n');
    await tester.tap(find.byTooltip('Undo Mark done'));
    await tester.pumpAndSettle();
    expect(contents(), initial);
  });

  testWidgets('chevrons collapse and expand', (tester) async {
    final home = await boot(tester);
    await tester.tap(find.byIcon(Icons.chevron_right).at(1)); // b
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 4);
    await tester.tap(find.text('t.md')); // the header toggles too
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 1);
    await tester.tap(find.text('t.md'));
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 4);
  });

  testWidgets('long press + drag selects a range; bulk done includes subtasks', (tester) async {
    await boot(tester);
    final g = await tester.startGesture(tester.getCenter(rowText('a')));
    await tester.pump(const Duration(milliseconds: 600)); // long press
    await g.moveTo(tester.getCenter(rowText('b')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('c')); // tap adds while selecting
    await tester.pump();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-Done')));
    await tester.pumpAndSettle();
    expect(contents(), '- [x] a x$today\n- [x] b x$today\n  - [x] b1 x$today\n- [x] c x$today\n');
    await tester.tap(find.byTooltip('Done selecting'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsNothing);
  });

  testWidgets('state on a parent applies to subtasks, from the task sheet', (tester) async {
    await boot(tester);
    await tester.tap(rowText('b'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<TaskState>), matching: find.text('Doing')));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a\n- [/] b\n  - [/] b1\n- [ ] c\n');
  });

  testWidgets('ETA dialog: number + unit, then a preset', (tester) async {
    await boot(tester);
    await tester.tap(rowText('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-eta')));
    await tester.pumpAndSettle();
    expect(find.byType(EtaDialog), findsOneWidget);
    await tester.enterText(find.byKey(const Key('etaAmount')), '45');
    await tester.tap(find.byKey(const Key('etaUnit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hours').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a ~45h\n- [ ] b\n  - [ ] b1\n- [ ] c\n');

    await tester.tap(rowText('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-eta')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('etaAmount'))).controller!.text, '45');
    await tester.tap(find.text('15m'));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a ~15m\n- [ ] b\n  - [ ] b1\n- [ ] c\n');
  });

  testWidgets('add subtask stamps the created date', (tester) async {
    await boot(tester);
    await tester.tap(rowText('b'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-addSubtask')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addText')), 'b2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a\n- [ ] b\n  - [ ] b1\n  - [ ] b2 +$today\n- [ ] c\n');
    expect(rowText('b2'), findsOneWidget);
  });

  testWidgets('+ adds to todo.md in the folder (created if missing), with a due date', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(find.text('todo.md'), findsNWidgets(2)); // app title, and where it goes: no file prompt
    await tester.enterText(find.byKey(const Key('addText')), 'd ~5m');
    await tester.tap(find.byKey(const ValueKey('due-Tomorrow')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    expect(File('${tmp.path}/todo.md').readAsStringSync(), '- [ ] d ~5m !2026-11-01 +$today\n');
    expect(contents(), initial);
    expect(rowText('d'), findsOneWidget);

    // Again: appended to the same file, picking a date from the grid.
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addText')), 'e');
    await tester.tap(find.byKey(const ValueKey('due-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-2026-10-29')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    expect(
      File('${tmp.path}/todo.md').readAsStringSync(),
      '- [ ] d ~5m !2026-11-01 +$today\n- [ ] e !2026-10-29 +$today\n',
    );
  });

  testWidgets('the undo snackbar goes away by itself', (tester) async {
    await boot(tester);
    await tester.tapAt(checkbox(tester, 'a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mark done: 1 line changed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Mark done: 1 line changed'), findsNothing);
  });

  testWidgets('swipe right toggles done, swipe left opens the due picker', (tester) async {
    await boot(tester);
    await tester.drag(rowText('c'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a\n- [ ] b\n  - [ ] b1\n- [x] c x$today\n');
    await tester.drag(rowText('a'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('due-Tomorrow')));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a !2026-11-01\n- [ ] b\n  - [ ] b1\n- [x] c x$today\n');
  });

  testWidgets('filter box, state chips and ETA preset narrow the list', (tester) async {
    final home = await boot(tester, data: '- [ ] wash ~2m\n- [x] done\n- [ ] movie ~2h\n  - [ ] popcorn\n');
    expect(home.list.rows.length, 4); // done hidden by default
    await tester.tap(find.byKey(const ValueKey('state-Done')));
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 5);
    await tester.enterText(find.byKey(const Key('search')), 'popcorn');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(home.list.rows.map((r) => r.task?.text), [null, 'movie', 'popcorn']); // parent kept
    home.setFilter('');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('etaFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('eta-1')));
    await tester.pumpAndSettle();
    expect(home.list.rows.map((r) => r.task?.text), [null, 'wash']);
  });

  testWidgets('calendar: day list, tile filters, reveal in Tasks', (tester) async {
    final home = await boot(tester, data: '- [ ] late !2026-10-30\n- [ ] now !2026-10-31\n- [/] doing\n');
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('now'), findsOneWidget); // today's list
    await tester.tap(find.byKey(const ValueKey('day-2026-10-30')));
    await tester.pumpAndSettle();
    expect(find.text('late'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tile-overdue')));
    await tester.pumpAndSettle();
    expect(home.tab, 0);
    expect(home.search.text, 'due:overdue');
    expect(home.list.rows.map((r) => r.task?.text), [null, 'late']);

    home.setFilter('');
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('late'));
    await tester.pumpAndSettle();
    expect(home.tab, 0); // revealed in the Tasks tab
  });

  testWidgets('agenda groups by day with relative labels', (tester) async {
    await boot(tester, data: '- [ ] p !2026-11-01\n  - [ ] c\n- [ ] q !2026-11-05\n');
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tomorrow', findRichText: true), findsOneWidget);
    expect(find.textContaining('in 5 days', findRichText: true), findsOneWidget);
    expect(rowText('c'), findsOneWidget); // subtasks under their parent
  });

  testWidgets('delete asks, removes subtasks too, and undoes', (tester) async {
    await boot(tester);
    await tester.tap(rowText('b'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] a\n- [ ] c\n');
    store.undo();
    await tester.pumpAndSettle();
    expect(contents(), initial);
  });
}
