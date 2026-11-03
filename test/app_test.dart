// Drives the real home screen (the desktop's tests/test_window.cpp, by touch).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('messages show beside the title (no snackbar) and go away by themselves', (tester) async {
    await boot(tester);
    await tester.tapAt(checkbox(tester, 'a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Mark done: 1 line changed')),
      findsOneWidget,
    );
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
    await tester.ensureVisible(find.byKey(const ValueKey('state-Done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('state-Done')));
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 5);
    await tester.enterText(find.byKey(const Key('search')), 'popcorn');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(home.list.rows.map((r) => r.task?.text), [null, 'movie', 'popcorn']); // parent kept
    home.setFilter('');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('etaFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('etaFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('eta-1')));
    await tester.pumpAndSettle();
    expect(home.list.rows.map((r) => r.task?.text), [null, 'wash']);
  });

  testWidgets('tags show in the row; tapping one filters to it, again clears', (tester) async {
    final home = await boot(tester, data: '- [ ] at work #office\n- [ ] at home\n- [ ] meeting #office ~1h\n- [x] gone #old\n');
    expect(rowText('at work'), findsOneWidget); // the tag is out of the title
    expect(find.byKey(const ValueKey('tag-office')), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('tag-office')).first);
    await tester.pumpAndSettle();
    expect(home.search.text, '#office');
    expect(home.list.rows.map((r) => r.task?.text), [null, 'at work', 'meeting']);
    await tester.tap(find.byKey(const ValueKey('tag-office')).first);
    await tester.pumpAndSettle();
    expect(home.search.text, '');
    expect(home.list.rows.length, 4); // the done one is hidden

    // The tag list in the filter bar.
    await tester.tap(find.byKey(const Key('tagFilter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pill-old')), findsNothing); // only on a done task
    await tester.tap(find.byKey(const ValueKey('pill-office')));
    await tester.pumpAndSettle();
    expect(home.search.text, '#office');

    // And from the task sheet.
    home.setFilter('');
    await tester.pumpAndSettle();
    await tester.tap(rowText('meeting'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pill-office')));
    await tester.pumpAndSettle();
    expect(home.search.text, '#office');
  });

  testWidgets('share → copy: selected tasks as a bullet list of their text', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final home = await boot(tester, data: '- [ ] a !2026-11-01 #x\n- [ ] b ~5m\n  - [ ] b1\n  - [ ] b2\n- [ ] c\n');
    home.selected = {for (final t in store.files.first.tasks) if (t.text != 'b2' && t.text != 'a') keyOf(t)};
    home.setFilter(''); // rebuild
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-copy')));
    await tester.pumpAndSettle();
    expect(copied, '- b\n  - b1\n- c\n');
    expect(home.selected, isEmpty);
  });

  testWidgets('typing # suggests existing tags; tapping one completes it', (tester) async {
    await boot(tester, data: '- [ ] a #office\n- [ ] b #home #offsite\n');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tagSuggestions')), findsNothing);
    await tester.enterText(find.byKey(const Key('addText')), 'call bob #of');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pill-office')), findsOneWidget);
    expect(find.byKey(const ValueKey('pill-offsite')), findsOneWidget);
    expect(find.byKey(const ValueKey('pill-home')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pill-office')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const Key('addText')));
    expect(field.controller!.text, 'call bob #office ');
    expect(find.byKey(const Key('tagSuggestions')), findsNothing);
  });

  testWidgets('task sheet: add a tag (picker) and remove one; sheet stays open', (tester) async {
    await boot(tester, data: '- [ ] call #mum, then\n- [ ] b #home\n');
    await tester.tap(rowText('call then'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addTag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pill-home'))); // an existing tag
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] call #mum, then #home\n- [ ] b #home\n');
    expect(find.byKey(const Key('sheetText')), findsOneWidget); // still open
    expect(find.byKey(const ValueKey('untag-home')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('untag-mum')));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] call, then #home\n- [ ] b #home\n');
    final field = tester.widget<TextField>(find.byKey(const Key('sheetText')));
    expect(field.controller!.text, 'call, then #home'); // follows the file

    // A new tag, typed.
    await tester.tap(find.byKey(const Key('addTag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tagText')), '#work/admin');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tagAdd')));
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] call, then #home #work/admin\n- [ ] b #home\n');
    store.undo();
    await tester.pumpAndSettle();
    expect(contents(), '- [ ] call, then #home\n- [ ] b #home\n');
  });

  testWidgets('views: create from the editor, switch, edit, delete; kept in settings', (tester) async {
    final home = await boot(
      tester,
      data: '- [ ] song #music\n- [ ] film #video\n- [ ] photo #photography\n- [ ] soon !2026-11-02\n- [ ] other\n',
    );
    List<String?> shown() => [for (final r in home.list.rows) if (r.task != null) r.task!.text];
    expect(find.text('todo.md'), findsOneWidget);

    await tester.tap(find.byKey(const Key('viewTitle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newView')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('viewName')), 'Media');
    // Tag pills append, joined with OR.
    for (final t in ['music', 'video', 'photography']) {
      await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.byKey(ValueKey('pill-$t'))).last);
      await tester.pump();
    }
    final filter = tester.widget<TextField>(find.byKey(const Key('viewFilter')));
    expect(filter.controller!.text, '#music OR #video OR #photography');
    // Tapping a chosen one takes it out again.
    await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.byKey(const ValueKey('pill-video'))).last);
    await tester.pump();
    expect(filter.controller!.text, '#music OR #photography');
    await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.byKey(const ValueKey('pill-video'))).last);
    await tester.pump();
    expect(filter.controller!.text, '#music OR #photography OR #video');
    expect(find.text('3 tasks match'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveView')));
    await tester.pumpAndSettle();
    expect(home.view?.name, 'Media');
    expect(find.text('Media'), findsOneWidget); // the title
    expect(shown(), ['song', 'film', 'photo']); // in file order
    // The search box narrows within the view.
    home.setFilter('film');
    await tester.pumpAndSettle();
    expect(shown(), ['film']);
    home.setFilter('');
    await tester.pumpAndSettle();

    // A second one, then switch between them.
    await tester.tap(find.byKey(const Key('viewTitle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newView')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('viewName')), 'media'); // taken (any case)
    await tester.pump();
    expect(find.textContaining('already a view'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('viewName')), 'Week');
    await tester.tap(find.byKey(const ValueKey('quick-due:week')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveView')));
    await tester.pumpAndSettle();
    expect(shown(), ['soon']);
    await tester.tap(find.byKey(const Key('viewTitle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-Media')));
    await tester.pumpAndSettle();
    expect(shown(), ['song', 'film', 'photo']);

    // Edit the active one: it updates in place.
    await tester.tap(find.byKey(const Key('viewTitle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editView-Media')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('viewFilter')), '#music');
    await tester.tap(find.byKey(const Key('saveView')));
    await tester.pumpAndSettle();
    expect(shown(), ['song']);
    final settings = await Settings.load();
    expect([for (final v in settings.views) '${v.name}=${v.filter}'], ['Media=#music', 'Week=due:week']);
    expect(settings.currentView, 'Media');

    // Delete it: back to all tasks.
    await tester.tap(find.byKey(const Key('viewTitle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editView-Media')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteView')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last); // confirm
    await tester.pumpAndSettle();
    expect(home.view, isNull);
    expect(shown().length, 5);
    expect((await Settings.load()).views.map((v) => v.name), ['Week']);
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

    // A tile at 0 does nothing: nothing to show.
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-quick (≤ 2m)')));
    await tester.pumpAndSettle();
    expect(home.tab, 2);
    expect(home.search.text, '');
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
