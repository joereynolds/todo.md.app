// Ported from the desktop app's tests/test_core.cpp.

import 'package:flutter_test/flutter_test.dart';
import 'package:todomd/core/day.dart';
import 'package:todomd/core/edits.dart';
import 'package:todomd/core/filter.dart';
import 'package:todomd/core/parser.dart' as parser;
import 'package:todomd/core/task.dart';

TaskFile parse(String s) => parser.parse('/a.md', 'a.md', s);

void main() {
  test('states', () {
    final f = parse(
      '- [ ] todo\n- [-] cancelled\n- [/] doing\n- [x] done\n- [X] done2\n'
      '- [] not a task\n- [ ]no space\n- [?] unknown\n* [ ] star\n+ [ ] plus\n',
    );
    expect(f.tasks.length, 7);
    expect(f.tasks.map((t) => t.state).take(5), [
      TaskState.todo,
      TaskState.cancelled,
      TaskState.doing,
      TaskState.done,
      TaskState.done,
    ]);
    expect(f.tasks[5].text, 'star');
    expect(f.tasks[6].line, 9);
  });

  test('dates', () {
    final f = parse(
      '- [ ] Buy !2026-12-25 gifts +2026-12-01 x2026-12-24 -2026-12-23\n'
      '- [ ] bad !2026-13-01 and a-2026-12-25 and !2026-02-30\n',
    );
    final t = f.tasks[0];
    expect(t.due, dayOf(2026, 12, 25));
    expect(t.created, dayOf(2026, 12, 1));
    expect(t.completed, dayOf(2026, 12, 24));
    expect(t.cancelled, dayOf(2026, 12, 23));
    expect(t.text, 'Buy gifts');
    final b = f.tasks[1];
    expect(b.due, isNull);
    expect(b.text, 'bad !2026-13-01 and a-2026-12-25 and !2026-02-30');
  });

  test('nesting', () {
    final f = parse(
      '# Kitchen\n'
      '- [ ] Sort the kitchen\n'
      '  - [x] Fix the tap\n'
      '    - [x] Call a plumber\n'
      '\n'
      '  - [ ] clean counter tops\n'
      '  - [-] take bins out\n'
      '\tsome note\n'
      '  - [ ] last\n'
      'Paragraph\n'
      '  - [ ] root after paragraph\n',
    );
    expect(f.tasks.length, 7);
    final root = f.tasks[0];
    expect(root.children.length, 4);
    expect(root.subTotal, 4); // 5 descendants, one cancelled
    expect(root.subDone, 2);
    expect(f.tasks[1].subTotal, 1);
    expect(f.tasks[1].subDone, 1);
    expect(f.roots.length, 2);
    expect(f.tasks[6].parent, isNull);
    expect(f.total, 6);
    expect(f.done, 2);
  });

  test('fences', () {
    final f = parse('```\n- [ ] example\n```\n- [ ] real\n~~~~\n```\n- [ ] still code\n~~~~\n- [ ] real2\n');
    expect(f.tasks.map((t) => t.text), ['real', 'real2']);
  });

  test('crlf and utf8', () {
    final f = parse('- [ ] café ☕ !2026-01-02\r\n- [x] b\r\n');
    expect(f.tasks.length, 2);
    expect(f.tasks[0].content, 'café ☕ !2026-01-02');
    expect(f.tasks[0].due, dayOf(2026, 1, 2));
  });

  test('line transforms', () {
    final today = dayOf(2026, 10, 31);
    expect(parser.setState('  - [ ] a !2026-11-01', TaskState.done, today), '  - [x] a !2026-11-01 x2026-10-31');
    expect(parser.setState('- [x] a x2026-10-30', TaskState.todo, today), '- [ ] a');
    expect(parser.setState('- [x] a x2026-10-30', TaskState.cancelled, today), '- [-] a -2026-10-31');
    expect(parser.setState('- [/] a', TaskState.doing, today), '- [/] a');
    expect(parser.setState('x2026-10-30 not a task', TaskState.done, today), 'x2026-10-30 not a task');
    expect(parser.setDue('- [ ] a !2026-01-01 b', dayOf(2026, 2, 2)), '- [ ] a b !2026-02-02');
    expect(parser.setDue('- [ ] !2026-01-01 a', null), '- [ ] a');
    expect(parser.setContent('\t* [/] old', 'new'), '\t* [/] new');
    expect(parser.setCreated('  - [ ] new !2026-11-02', today), '  - [ ] new !2026-11-02 +2026-10-31');
    expect(parser.setCreated('- [ ] typed +2026-01-01', today), '- [ ] typed +2026-01-01');
  });

  test('apply and undo', () {
    const original = '# T\r\n- [ ] a\r\n- [ ] b\r\n  - [ ] c\r\n';
    final buf = LineBuffer.fromString(original);
    expect(buf.crlf, isTrue);
    final r = applyEdits(buf, [
      Edit('/a.md', 1, ['- [ ] a'], ['- [x] a']),
      Edit('/a.md', 2, ['- [ ] b'], ['- [ ] b', '- [ ] new']), // insert
      Edit('/a.md', 3, ['  - [ ] c'], []), // delete
      Edit('/a.md', -1, [], ['- [ ] appended']),
      Edit('/a.md', 0, ['# wrong'], ['# X']), // conflict
    ]);
    expect(r.applied, 4);
    expect(r.conflicts, 1);
    expect(buf.toString(), '# T\r\n- [x] a\r\n- [ ] b\r\n- [ ] new\r\n- [ ] appended\r\n');

    final u = applyEdits(buf, r.inverse);
    expect(u.applied, 4);
    expect(u.conflicts, 0);
    expect(buf.toString(), original);

    final redo = applyEdits(buf, u.inverse);
    expect(redo.applied, 4);
    expect(buf.toString(), '# T\r\n- [x] a\r\n- [ ] b\r\n- [ ] new\r\n- [ ] appended\r\n');
  });

  test('undo contiguous delete', () {
    const original = 'a\nb\nc\nd\ne\n';
    final buf = LineBuffer.fromString(original);
    final r = applyEdits(buf, [
      Edit('/a.md', 1, ['b'], []),
      Edit('/a.md', 2, ['c'], []),
      Edit('/a.md', 3, ['d'], []),
    ]);
    expect(buf.toString(), 'a\ne\n');
    applyEdits(buf, r.inverse);
    expect(buf.toString(), original);

    // Insertions at the same line land in list order.
    final ins = LineBuffer.fromString('a\nz\n');
    final i = applyEdits(ins, [
      Edit('/a.md', 1, [], ['b']),
      Edit('/a.md', 1, [], ['c']),
      Edit('/a.md', 1, ['z'], ['y']),
    ]);
    expect(ins.toString(), 'a\nb\nc\ny\n');
    applyEdits(ins, i.inverse);
    expect(ins.toString(), 'a\nz\n');
  });

  test('eta', () {
    final f = parse(
      '- [ ] Wash hands ~2m\n- [ ] Movie ~90m !2026-12-01\n- [ ] Wales ~7d\n'
      '- [ ] UK ~5w\n- [ ] Life ~85y\n- [ ] not ~2x ~ ~m a~2m\n',
    );
    expect(f.tasks[0].eta, 2);
    expect(f.tasks[0].text, 'Wash hands');
    expect(f.tasks[1].eta, 90);
    expect(f.tasks[1].etaText, '90m');
    expect(f.tasks[1].text, 'Movie');
    expect(f.tasks[2].eta, 7 * 24 * 60);
    expect(f.tasks[3].eta, 5 * 7 * 24 * 60);
    expect(f.tasks[4].eta, 85 * 365 * 24 * 60);
    expect(f.tasks[5].eta, 0);
    expect(f.tasks[5].text, 'not ~2x ~ ~m a~2m');
    expect(parser.setEta('- [ ] a ~2m b', '1h'), '- [ ] a b ~1h');
    expect(parser.setEta('- [ ] ~2m a', ''), '- [ ] a');
  });

  test('depth', () {
    final f = parse('- [ ] a\n  - [ ] b\n    - [ ] c\n  - [ ] d\n- [ ] e\n');
    expect(f.tasks.map((t) => t.depth), [0, 1, 2, 1, 0]);
  });

  test('no trailing newline', () {
    final buf = LineBuffer.fromString('- [ ] a');
    applyEdits(buf, [
      Edit('/a.md', -1, [], ['- [ ] b']),
    ]);
    expect(buf.toString(), '- [ ] a\n- [ ] b');
    final empty = LineBuffer.fromString('');
    applyEdits(empty, [
      Edit('/a.md', -1, [], ['- [ ] b']),
    ]);
    expect(empty.toString(), '- [ ] b\n');
  });

  test('filter', () {
    todayFn = () => dayOf(2026, 10, 31);
    addTearDown(() => todayFn = () => dayFromDate(DateTime.now()));
    final f = parse(
      '- [ ] Wash ~2m !2026-10-30\n- [/] Movie ~2h !2026-10-31\n- [x] Done thing\n- [ ] Later !2026-11-20\n',
    );
    List<String> run(String text, {int states = 0xF}) {
      final flt = TaskFilter()..states = states;
      flt.setText(text);
      return [
        for (final t in f.tasks)
          if (flt.matches(t)) t.text,
      ];
    }

    expect(run('~<=15m'), ['Wash']);
    expect(run('~>1h'), ['Movie']);
    expect(run('~none'), ['Done thing', 'Later']);
    expect(run('due:overdue'), ['Wash']);
    expect(run('due:today'), ['Movie']);
    expect(run('due:week'), ['Movie']);
    expect(run('due:none'), ['Done thing']);
    expect(run('is:doing'), ['Movie']);
    expect(run('is:open MOVIE'), ['Movie']);
    expect(run('a.md thing'), ['Done thing']); // path or content
    expect(run('', states: 0x3), ['Wash', 'Movie', 'Later']);
    expect(EtaCond.parse('~bad'), isNull);

    // OR between terms; lower-case "or" is a plain word.
    expect(run('due:overdue OR due:today'), ['Wash', 'Movie']);
    expect(run('is:open ~<=15m OR later'), ['Wash', 'Later']);
    expect(run('OR wash OR'), ['Wash']);
    expect(run('wash or'), isEmpty);
    // A view combines with the search box: both must match.
    final flt = TaskFilter()..setView('due:overdue OR due:today');
    flt.setText('movie');
    expect([for (final t in f.tasks) if (flt.matches(t)) t.text], ['Movie']);
    flt.setText('');
    expect([for (final t in f.tasks) if (flt.matches(t)) t.text], ['Wash', 'Movie']);
    expect(flt.narrows, isTrue);
    expect(flt.searchNarrows, isFalse);

    // done:today / done:week, shown even with the Done toggle off.
    final g = parse('- [x] a x2026-10-31\n- [x] b x2026-10-26\n- [x] c x2026-10-20\n- [ ] d\n- [x] e\n');
    List<String> done(String text, {int states = 0x3}) {
      final flt = TaskFilter()..states = states;
      flt.setText(text);
      return [for (final t in g.tasks) if (flt.matches(t)) t.text];
    }
    expect(done('done:today'), ['a']);
    expect(done('done:week'), ['a', 'b']);
    expect(done(''), ['d']); // done hidden as usual
    expect(done('done:today OR d'), ['a', 'd']);
  });

  test('tags', () {
    expect(parser.tagToken('#office'), 'office');
    expect(parser.tagToken('#work/admin'), 'work/admin');
    expect(parser.tagToken('#office,'), 'office');
    expect(parser.tagToken('#café'), 'café');
    expect(parser.tagToken('#42'), isNull); // issue numbers aren't tags
    expect(parser.tagToken('#'), isNull);
    expect(parser.tagToken('##x'), isNull);
    expect(parser.tagToken('#a.b'), isNull);
    final f = parse(
      '- [ ] Do the thing at work #office ~15m\n'
      '- [ ] Call #mum, then #Office again #office\n'
      '- [ ] issue#3 and #42 and a#b\n'
      '- [ ] file it #work/admin\n',
    );
    expect(f.tasks[0].text, 'Do the thing at work');
    expect(f.tasks[0].tags, ['office']);
    expect(f.tasks[0].eta, 15);
    expect(f.tasks[1].text, 'Call then again');
    expect(f.tasks[1].tags, ['mum', 'Office']); // case-insensitive, first spelling kept
    expect(f.tasks[2].tags, isEmpty);
    expect(f.tasks[2].text, 'issue#3 and #42 and a#b');

    List<String> run(String text) {
      final flt = TaskFilter()..setText(text);
      return [
        for (final t in f.tasks)
          if (flt.matches(t)) t.text,
      ];
    }

    expect(run('#office'), ['Do the thing at work', 'Call then again']);
    expect(run('#OFFICE #mum'), ['Call then again']);
    expect(run('#work'), ['file it']); // a parent tag matches its children
    expect(run('#work/admin'), ['file it']);
    expect(run('#wor'), isEmpty); // whole tags, not prefixes
    expect(run('#42'), ['issue#3 and #42 and a#b']); // not a tag: a plain word
    expect(tagTerm('Office'), '#office');
  });

  test('add and remove tags', () {
    expect(parser.removeTag('- [ ] Call #mum, then #Mum again', 'mum'), '- [ ] Call, then again');
    expect(parser.removeTag('- [ ] #home sort', 'home'), '- [ ] sort');
    expect(parser.removeTag('- [ ] a #x ~5m', 'x'), '- [ ] a ~5m');
    expect(parser.removeTag('- [ ] a #xy', 'x'), '- [ ] a #xy');
    expect(parser.addTag('- [ ] a #x', 'X'), '- [ ] a #x'); // already there
    expect(parser.addTag('- [ ] a', 'new/one'), '- [ ] a #new/one');
    expect(parser.addTag('- [ ] a ', 'b'), '- [ ] a #b');
    expect(parser.addTag('- [ ] a', 'bad tag'), '- [ ] a'); // not a tag
    expect(parser.addTag('- [ ] a', '42'), '- [ ] a');
  });

  test('addMonths clamps', () {
    expect(isoDay(addMonths(dayOf(2026, 1, 31), 1)), '2026-02-28');
    expect(isoDay(addMonths(dayOf(2026, 1, 15), -1)), '2025-12-15');
  });
}
