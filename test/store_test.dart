// Store and models against real temp directories. Ported in spirit from the
// desktop app's tests/test_store.cpp.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todomd/core/day.dart';
import 'package:todomd/core/edits.dart';
import 'package:todomd/core/models.dart';
import 'package:todomd/core/parser.dart' as parser;
import 'package:todomd/core/store.dart';
import 'package:todomd/core/task.dart';

late Directory tmp;

String p(String rel) => '${tmp.path}/$rel';

void write(String rel, String content) {
  final f = File(p(rel));
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

String read(String rel) => File(p(rel)).readAsStringSync();

/// Waits until [cond] holds, polling (the watcher is asynchronous).
Future<void> until(bool Function() cond, {int ms = 3000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('todomd_test');
    tmp = Directory(normalizeRoot(tmp.resolveSymbolicLinksSync()));
    todayFn = () => dayOf(2026, 10, 31);
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
    todayFn = () => dayFromDate(DateTime.now());
  });

  test('scan skips hidden dirs, node_modules and taskless files; sorted by path', () async {
    write('b.md', '- [ ] b\n');
    write('A/x.markdown', '- [ ] x\n');
    write('.hidden/h.md', '- [ ] hidden\n');
    write('node_modules/n.md', '- [ ] nm\n');
    write('notes.md', 'no tasks here\n');
    write('t.txt', '- [ ] not markdown\n');
    final s = TaskStore();
    await s.setRoots([tmp.path]);
    expect(s.files.map((f) => f.relPath), ['A/x.markdown', 'b.md']);
    expect(s.taskCount, 2);
    s.dispose();
  });

  test('parallel parse of many files', () async {
    for (var i = 0; i < 300; i++) {
      write('d${i % 7}/f$i.md', '- [ ] a$i\n  - [x] b$i\n');
    }
    final s = TaskStore();
    await s.setRoots([tmp.path]);
    expect(s.files.length, 300);
    expect(s.taskCount, 600);
    expect(s.files.first.tasks[1].parent, same(s.files.first.tasks[0]));
    s.dispose();
  });

  test('multiple roots: prefixed display paths, a nested root held once', () async {
    write('work/w.md', '- [ ] w\n');
    write('home/h.md', '- [ ] h\n');
    final s = TaskStore();
    await s.setRoots([p('work'), p('home'), tmp.path]);
    expect(s.files.map((f) => f.relPath).toList(), ['home/h.md', 'work/w.md']);
    expect(s.files.length, 2);
    expect(relPathFor('/a/b/c.md', ['/a']), 'b/c.md');
    expect(relPathFor('/a/b/c.md', ['/a', '/a/b']), 'b/c.md');
    s.dispose();
  });

  test('apply, conflicts, undo and redo', () async {
    write('t.md', '- [ ] a\n- [ ] b\n');
    final s = TaskStore();
    final messages = <String>[];
    s.onMessage = messages.add;
    await s.setRoots([tmp.path]);
    final a = s.taskAt(p('t.md'), 0)!;
    expect(
      s.apply([
        Edit(a.file.path, 0, [a.raw], [parser.setState(a.raw, TaskState.done, today())]),
      ], 'Mark done'),
      1,
    );
    expect(read('t.md'), '- [x] a x2026-10-31\n- [ ] b\n');
    expect(s.taskAt(p('t.md'), 0)!.state, TaskState.done);
    expect(s.undoLabel, 'Mark done');

    s.undo();
    expect(read('t.md'), '- [ ] a\n- [ ] b\n');
    expect(s.canRedo, isTrue);
    s.redo();
    expect(read('t.md'), '- [x] a x2026-10-31\n- [ ] b\n');

    // A stale edit is skipped, never forced.
    expect(
      s.apply([
        Edit(p('t.md'), 1, ['- [ ] stale'], ['- [x] stale']),
      ], 'Mark done'),
      0,
    );
    expect(read('t.md'), '- [x] a x2026-10-31\n- [ ] b\n');
    expect(messages.last, contains('changed on disk'));
    s.dispose();
  });

  test('watcher picks up edits, new files, new dirs and deletes', () async {
    write('t.md', '- [ ] a\n');
    final s = TaskStore();
    await s.setRoots([tmp.path]);
    await until(() => s.watchCount > 0);

    write('t.md', '- [ ] a\n- [ ] b\n');
    await until(() => s.taskCount == 2);
    write('u.md', '- [ ] u\n');
    await until(() => s.files.length == 2);
    Directory(p('sub')).createSync();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    write('sub/s.md', '- [ ] s\n');
    await until(() => s.files.length == 3);
    File(p('u.md')).deleteSync();
    await until(() => s.files.length == 2);
    Directory(p('sub')).deleteSync(recursive: true);
    await until(() => s.files.length == 1);
    s.dispose();
  });

  test('refresh catches up while not watching', () async {
    write('t.md', '- [ ] a\n');
    final s = TaskStore();
    s.watching = false;
    await s.setRoots([tmp.path]);
    write('t.md', '- [ ] a\n- [ ] b\n');
    write('n/new.md', '- [ ] n\n');
    expect(s.taskCount, 1);
    await s.refresh();
    expect(s.taskCount, 3);
    s.dispose();
  });

  test('list model: filter keeps ancestors, collapse and expand, reveal', () async {
    write('t.md', '- [ ] a\n- [ ] b\n  - [ ] b1\n    - [ ] deep match\n- [ ] c\n');
    final s = TaskStore();
    s.watching = false;
    await s.setRoots([tmp.path]);
    final m = TaskListModel(s);
    // header, a, b, b1, deep, c
    expect(m.rows.length, 6);
    expect(m.rows[3].depth, 2);
    expect(m.rows[2].hasChildren, isTrue);

    m.setExpanded(2, false);
    expect(m.rows.length, 4);
    m.setExpanded(2, true);
    expect(m.rows.length, 6);
    m.setExpanded(0, false);
    expect(m.rows.length, 1);
    expect(m.collapsedKeys, [p('t.md')]);

    final deep = s.taskAt(p('t.md'), 3)!;
    expect(m.reveal(deep), 4);
    expect(m.rows.length, 6);

    m.filter.setText('match');
    m.refilter();
    expect(m.rows.map((r) => r.task?.text), [null, 'b', 'b1', 'deep match']);
    // Collapsing while filtered is temporary.
    m.setExpanded(1, false);
    m.filter.setText('');
    m.refilter();
    expect(m.rows.length, 6);
    m.dispose();
    s.dispose();
  });

  test('list model: subtasks of a matching task show (their state still filtered)', () async {
    write(
      't.md',
      '- [ ] Get building insurance #house\n'
          '  - [ ] get quotes\n'
          '    - [ ] ring brokers\n'
          '  - [x] find policy number\n'
          '  - [ ] pay #money\n'
          '- [ ] other\n'
          '  - [ ] sub\n',
    );
    final s = TaskStore();
    s.watching = false;
    await s.setRoots([tmp.path]);
    final m = TaskListModel(s);
    m.filter.states = 0x3; // done hidden
    List<String?> shown() => [for (final r in m.rows) r.task?.text];

    m.filter.setView('#house');
    m.refilter();
    expect(shown(), [null, 'Get building insurance', 'get quotes', 'ring brokers', 'pay']);
    expect(m.rows[1].hasChildren, isTrue);
    // The search box narrows within the view (finding untagged subtasks); a
    // match still brings its subtasks.
    m.filter.setText('quotes');
    m.refilter();
    expect(shown(), [null, 'Get building insurance', 'get quotes', 'ring brokers']);
    // A match deeper down keeps its ancestors but not their other subtasks.
    m.filter.setView('');
    m.filter.setText('#money');
    m.refilter();
    expect(shown(), [null, 'Get building insurance', 'pay']);
    // Done ones show once the Done toggle is on.
    m.filter.setText('');
    m.filter.setView('#house');
    m.filter.states = 0xF;
    m.refilter();
    expect(shown(), contains('find policy number'));
    m.dispose();
    s.dispose();
  });

  test('agenda: days, nesting under same-day ancestor, empty days, labels', () async {
    write(
      't.md',
      '- [ ] p !2026-11-01\n  - [ ] c !2026-11-01\n  - [ ] c2 !2026-11-05\n'
          '- [x] done !2026-11-01\n- [ ] old !2026-10-01\n- [ ] far !2027-03-01\n',
    );
    final s = TaskStore();
    s.watching = false;
    await s.setRoots([tmp.path]);
    final m = AgendaModel(s);
    expect(m.groups.map((g) => isoDay(g.date!)), ['2026-10-01', '2026-11-01', '2026-11-05', '2027-03-01']);
    expect(m.groups[1].roots.map((t) => t.text), ['p']); // c shows under p
    expect(m.relativeLabel(m.groups[0]), ''); // beyond two weeks: date only
    expect(m.relativeLabel(m.groups[1]), 'tomorrow');
    expect(m.relativeLabel(m.groups[2]), 'in 5 days');
    expect(m.dayLabel(m.groups[1]), 'Sun 2026-11-01');

    m.showEmptyDays = true;
    // old + every day from today to 2027-03-01
    expect(m.groups.length, 1 + (dayOf(2027, 3, 1) - today() + 1));

    final day = AgendaModel(s, day: dayOf(2026, 10, 20));
    expect(day.groups.length, 1);
    expect(day.rows.length, 1); // header kept for an empty day
    expect(day.relativeLabel(day.groups[0]), '11 days ago');
    m.dispose();
    day.dispose();
    s.dispose();
  });

  test('atomic write leaves no temp file and keeps CRLF', () async {
    write('t.md', '- [ ] a\r\n');
    final s = TaskStore();
    s.watching = false;
    await s.setRoots([tmp.path]);
    final a = s.files.first.tasks.first;
    s.apply([
      Edit(a.file.path, 0, [a.raw], [parser.setDue(a.raw, dayOf(2026, 12, 25))]),
    ], 'Set due date');
    expect(read('t.md'), '- [ ] a !2026-12-25\r\n');
    expect(tmp.listSync().map((e) => e.path.split('/').last), ['t.md']);
    s.dispose();
  });
}
