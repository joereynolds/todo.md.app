// Drives the real home screen (the desktop's tests/test_window.cpp, by touch).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todomd/core/day.dart';
import 'package:todomd/core/models.dart';
import 'package:todomd/core/store.dart';
import 'package:todomd/core/task.dart';
import 'package:todomd/main.dart';
import 'package:todomd/ui/dialogs.dart';
import 'package:todomd/ui/help_page.dart';
import 'package:todomd/ui/templates_page.dart';
import 'package:todomd/ui/home.dart';
import 'package:todomd/ui/settings.dart';
import 'package:todomd/ui/task_list.dart';
import 'package:todomd/ui/views.dart';

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

/// The template page's own store loads in an isolate; let it finish.
Future<void> templateLoaded(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 100; i++) {
    final st = tester.state(find.byType(TemplateEditorPage)) as dynamic;
    if (!(st.store as TaskStore).loading) break;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  test('RowLayout: short headers, offsets and hit rows by binary search', () {
    ListRow h() => ListRow(null, 0, 0, true, true);
    ListRow t() =>
        ListRow(Task(line: 0, indent: 0, state: TaskState.todo, prefix: '- [ ] ', content: 'x'), 0, 1, false, true);
    final l = RowLayout([h(), t(), t(), h(), t()]);
    expect(
      [for (var i = 0; i <= 5; i++) l.offsetOf(i)],
      [
        0,
        headerExtent,
        headerExtent + rowExtent,
        headerExtent + 2 * rowExtent,
        2 * headerExtent + 2 * rowExtent,
        2 * headerExtent + 3 * rowExtent,
      ],
    );
    expect(l.total, 2 * headerExtent + 3 * rowExtent);
    expect([l.extentOf(0), l.extentOf(1), l.extentOf(3)], [headerExtent, rowExtent, headerExtent]);
    expect(l.indexAt(0), 0);
    expect(l.indexAt(headerExtent - 1), 0);
    expect(l.indexAt(headerExtent), 1);
    expect(l.indexAt(headerExtent + 2 * rowExtent + 1), 3);
    expect(l.indexAt(1e9), 4); // clamped
    expect(RowLayout(const []).indexAt(10), 0);
  });

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
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Mark done: 1 line changed')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Mark done: 1 line changed'), findsNothing);
  });

  testWidgets('rows don\'t swipe: a sideways drag changes nothing', (tester) async {
    await boot(tester);
    await tester.drag(rowText('c'), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.drag(rowText('a'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(contents(), initial);
    expect(find.byKey(const ValueKey('due-Tomorrow')), findsNothing); // no due picker
    // And no pull-to-refresh: dragging down at the top does nothing.
    final g = await tester.startGesture(tester.getCenter(rowText('a')));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('search box, and the filter sheet\'s states and ETA preset, narrow the list', (tester) async {
    final home = await boot(tester, data: '- [ ] wash ~2m\n- [x] done\n- [ ] movie ~2h\n  - [ ] popcorn\n');
    expect(home.list.rows.length, 4); // done hidden by default
    final field = tester.widget<TextField>(find.byKey(const Key('search')));
    expect(field.decoration!.hintText, 'Search');
    expect(find.byKey(const ValueKey('state-Done')), findsNothing); // not on the main screen
    await tester.tap(find.byKey(const Key('filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('state-Done')));
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 5);
    await tester.tapAt(const Offset(200, 40)); // close the sheet
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search')), 'popcorn');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(home.list.rows.map((r) => r.task?.text), [null, 'movie', 'popcorn']); // parent kept
    home.setFilter('');
    await tester.pumpAndSettle();
    // The help sheet (from the filter sheet): tapping an example applies it.
    await tester.tap(find.byKey(const Key('filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filterTips')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('help-~<=15m')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('help-~<=15m')));
    await tester.pumpAndSettle();
    expect(home.search.text, '~<=15m');
    expect(home.list.rows.map((r) => r.task?.text), [null, 'wash']);
    home.setFilter('');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('eta-1')));
    await tester.pumpAndSettle();
    expect(home.list.rows.map((r) => r.task?.text), [null, 'wash']);
    expect((await Settings.load()).etaPreset, 1);
    // Reset puts the states and ETA back.
    await tester.tap(find.byKey(const Key('filtersReset')));
    await tester.pumpAndSettle();
    expect(home.list.rows.length, 4);
    expect(find.byKey(const Key('filtersReset')), findsNothing);
  });

  testWidgets('tags show in the row; tapping one filters to it, again clears', (tester) async {
    final home = await boot(
      tester,
      data: '- [ ] at work #office\n- [ ] at home\n- [ ] meeting #office ~1h\n- [x] gone #old\n',
    );
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

    // The tag list in the filter sheet.
    await tester.tap(find.byKey(const Key('filters')));
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
    home.selected = {
      for (final t in store.files.first.tasks)
        if (t.text != 'b2' && t.text != 'a') keyOf(t),
    };
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
    List<String?> shown() => [
      for (final r in home.list.rows)
        if (r.task != null) r.task!.text,
    ];
    expect(find.byKey(const Key('viewStrip')), findsNothing); // no views yet

    Future<void> menuNewView() async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New view…'));
      await tester.pumpAndSettle();
    }

    await menuNewView();
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
    expect(find.byKey(const ValueKey('view-Media')), findsOneWidget); // a tab along the top
    expect(shown(), ['song', 'film', 'photo']); // in file order
    // The search box narrows within the view.
    home.setFilter('film');
    await tester.pumpAndSettle();
    expect(shown(), ['film']);
    home.setFilter('');
    await tester.pumpAndSettle();

    // A second one (the strip's +), then switch between them by tab.
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
    await tester.tap(find.byKey(const ValueKey('view-Media')));
    await tester.pumpAndSettle();
    expect(shown(), ['song', 'film', 'photo']);
    await tester.tap(find.byKey(const ValueKey('view-all')));
    await tester.pumpAndSettle();
    expect(home.view, isNull);
    expect(shown().length, 5);

    // Swiping left steps to the next view, right goes back; no further than the ends.
    Future<void> swipe(double dx) async {
      // Many small moves, like a finger (not a fling).
      await tester.timedDrag(rowText('soon'), Offset(dx, 0), const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    await tester.fling(find.byKey(const Key('list')), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(home.view?.name, 'Media');
    await tester.fling(find.byKey(const Key('list')), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(home.view?.name, 'Week');
    await swipe(-300); // the last one
    expect(home.view?.name, 'Week');
    await swipe(300);
    expect(home.view?.name, 'Media');
    expect(contents(), contains('- [ ] soon !2026-11-02\n')); // rows untouched
    // A mostly-vertical drag (scrolling) never switches views, nor moves the
    // list sideways (a lost gesture used to replay the last swipe's offset).
    double shift() => tester
        .widget<Transform>(find.descendant(of: find.byType(ViewSwiper), matching: find.byType(Transform)).first)
        .transform
        .getTranslation()
        .x;
    final g = await tester.startGesture(tester.getCenter(rowText('song')));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(2, -12)); // scrolling, a little diagonal
      await tester.pump(const Duration(milliseconds: 16));
      expect(shift(), 0);
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(home.view?.name, 'Media');
    // A sideways swipe that drifts down a little is still a swipe.
    await tester.timedDrag(rowText('song'), const Offset(-300, 60), const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(home.view?.name, 'Week');
    await swipe(300);
    expect(home.view?.name, 'Media');

    // Tapping the active tab edits it: it updates in place.
    await tester.tap(find.byKey(const ValueKey('view-Media')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('viewFilter')), '#music');
    await tester.tap(find.byKey(const Key('saveView')));
    await tester.pumpAndSettle();
    expect(shown(), ['song']);
    final settings = await Settings.load();
    expect([for (final v in settings.views) '${v.name}=${v.filter}'], ['Media=#music', 'Week=due:week']);
    expect(settings.currentView, 'Media');

    // Delete it (long press opens the editor too): back to all tasks.
    await tester.longPress(find.byKey(const ValueKey('view-Media')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteView')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last); // confirm
    await tester.pumpAndSettle();
    expect(home.view, isNull);
    expect(shown().length, 5);
    expect((await Settings.load()).views.map((v) => v.name), ['Week']);
  });

  testWidgets('+ in a view starts the task with its tags, so it shows there', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final home = await boot(tester, data: '- [ ] song #music\n- [ ] other\n');
    final settings = await Settings.load();
    settings.views = const [
      SavedView('Music', '#Music OR #video'),
      SavedView('Today', 'due:today'),
      SavedView('Week', 'due:week'),
    ];
    home.views = settings.views;
    home.setView(home.views[0]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(find.text('New task in Music'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('addText')));
    expect(field.controller!.text, ' #Music');
    expect(field.controller!.selection.baseOffset, 0); // typing goes before the tag
    field.controller!.text = 'tune${field.controller!.text}';
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    final inbox = File('${tmp.path}/todo.md').readAsStringSync();
    expect(inbox, '- [ ] tune #Music +$today\n');
    expect(
      [
        for (final r in home.list.rows)
          if (r.task != null) r.task!.text,
      ],
      ['song', 'tune'],
    );

    // due:today: due today. A view adding can't satisfy (due:week) says so.
    home.setView(home.views[1]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addText')), 'now');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    expect(File('${tmp.path}/todo.md').readAsStringSync(), endsWith('- [ ] now !$today +$today\n'));
    home.setView(home.views[2]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addText')), 'later');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('"Week" doesn\'t show it'), findsOneWidget);
  });

  testWidgets('menu → Help explains the app; its filter link opens the filter sheet', (tester) async {
    final home = await boot(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('Your tasks are in your notes'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('helpFilter')), 300);
    await tester.tap(find.byKey(const Key('helpFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('help-due:today')));
    await tester.pumpAndSettle();
    expect(home.search.text, 'due:today');
    expect(find.byType(HelpPage), findsNothing); // back on the list
  });

  testWidgets('templates: save from a selection, insert (todo.md, below, as subtasks), edit, rename, delete', (
    tester,
  ) async {
    final home = await boot(
      tester,
      data: '- [x] Pack x2026-10-01 #trip\n  - [ ] Passport ~5m !2026-11-02\n- [ ] Holiday\n',
    );
    final dir = '${tmp.path}/.templates';

    // Save "Pack" (with its subtask) as a template.
    home.selected = {keyOf(store.files.first.tasks.first)};
    home.setFilter('');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as template…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('promptField')), 'Trip');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(File('$dir/Trip.md').readAsStringSync(), '- [ ] Pack #trip\n  - [ ] Passport ~5m\n');
    expect(home.selected, isEmpty);
    expect(home.list.rows.where((r) => r.task != null).length, 3); // nothing from .templates (it isn't scanned)

    // + → Template… → into todo.md; the new tasks end up selected.
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addFromTemplate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pickTemplate-Trip')));
    await tester.pumpAndSettle();
    expect(File('${tmp.path}/todo.md').readAsStringSync(), '- [ ] Pack #trip +$today\n  - [ ] Passport ~5m +$today\n');
    expect(home.selected.length, 2);
    home.selected = {};

    // Task sheet → Insert template… → as subtasks of "Holiday".
    home.setFilter('');
    await tester.pumpAndSettle();
    await tester.tap(rowText('Holiday'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-template')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tplSubtasks')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pickTemplate-Trip')));
    await tester.pumpAndSettle();
    expect(
      contents(),
      '- [x] Pack x2026-10-01 #trip\n  - [ ] Passport ~5m !2026-11-02\n- [ ] Holiday\n'
      '  - [ ] Pack #trip +$today\n    - [ ] Passport ~5m +$today\n',
    );
    store.undo(); // one step
    await tester.pumpAndSettle();
    expect(contents(), '- [x] Pack x2026-10-01 #trip\n  - [ ] Passport ~5m !2026-11-02\n- [ ] Holiday\n');
    home.selected = {};
    home.setFilter('');
    await tester.pumpAndSettle();

    // ⋮ → Templates: a template opens as a task list; edit, add, rename, delete.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    expect(find.text('2 tasks'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('template-Trip')));
    await templateLoaded(tester);
    expect(rowText('Pack'), findsOneWidget);
    expect(rowText('Passport'), findsOneWidget);
    // + adds a task (no created date in a template); tap → sheet → ETA etc. as usual.
    await tester.tap(find.byKey(const Key('addTemplateTask')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addText')), 'Book train');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSubmit')));
    await tester.pumpAndSettle();
    expect(File('$dir/Trip.md').readAsStringSync(), '- [ ] Pack #trip\n  - [ ] Passport ~5m\n- [ ] Book train\n');
    await tester.tap(rowText('Passport'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sheet-template')), findsNothing); // not here
    await tester.tap(find.byKey(const ValueKey('sheet-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(File('$dir/Trip.md').readAsStringSync(), '- [ ] Pack #trip\n- [ ] Book train\n');
    await tester.tap(find.byTooltip('Undo Delete'));
    await tester.pumpAndSettle();
    expect(File('$dir/Trip.md').readAsStringSync(), '- [ ] Pack #trip\n  - [ ] Passport ~5m\n- [ ] Book train\n');

    // Rename (tap the title), then delete the template.
    await tester.tap(find.byKey(const Key('templateTitle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('promptField')), 'Weekend trip');
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await templateLoaded(tester);
    expect(File('$dir/Trip.md').existsSync(), isFalse);
    expect(File('$dir/Weekend trip.md').existsSync(), isTrue);
    expect(rowText('Book train'), findsOneWidget);
    await tester.tap(find.byKey(const Key('templateMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(File('$dir/Weekend trip.md').existsSync(), isFalse);
    expect(find.textContaining('No templates yet'), findsOneWidget);
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

  testWidgets('calendar: "done today" shows what was finished today, Done toggle off or not', (tester) async {
    final home = await boot(tester, data: '- [x] finished x2026-10-31\n- [x] older x2026-10-20\n- [ ] open\n');
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-done today')));
    await tester.pumpAndSettle();
    expect(home.tab, 0);
    expect(home.search.text, 'done:today');
    expect(home.list.rows.map((r) => r.task?.text), [null, 'finished']);
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
