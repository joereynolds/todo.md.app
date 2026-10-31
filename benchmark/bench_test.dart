// Load + model timings on a generated corpus (200k tasks / 5,000 files).
//   flutter test benchmark/            (JIT, so slower than a release build)
//   BENCH_DIR=~/notes flutter test benchmark/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todomd/core/models.dart';
import 'package:todomd/core/store.dart';

void main() {
  test('bench', () async {
    var dir = Platform.environment['BENCH_DIR'];
    Directory? tmp;
    if (dir == null) {
      tmp = Directory.systemTemp.createTempSync('todomd_bench');
      dir = tmp.path;
      for (var f = 0; f < 5000; f++) {
        final b = StringBuffer('# File $f\n\nSome prose.\n\n');
        for (var i = 0; i < 10; i++) {
          b.writeln(
            '- [${i % 3 == 0 ? 'x' : ' '}] Task $f.$i with words !2026-${(i % 12 + 1).toString().padLeft(2, '0')}-1$i ~${i + 1}m',
          );
          for (var j = 0; j < 3; j++) {
            b.writeln('  - [ ] Sub $j of $i +2026-01-0${j + 1}');
          }
        }
        Directory('$dir/d${f % 50}').createSync(recursive: true);
        File('$dir/d${f % 50}/f$f.md').writeAsStringSync(b.toString());
      }
    }
    final s = TaskStore()..watching = false;
    var sw = Stopwatch()..start();
    await s.setRoots([dir]);
    final load = sw.elapsedMilliseconds;
    sw = Stopwatch()..start();
    final list = TaskListModel(s);
    final listMs = sw.elapsedMilliseconds;
    sw = Stopwatch()..start();
    final agenda = AgendaModel(s);
    final agendaMs = sw.elapsedMilliseconds;
    sw = Stopwatch()..start();
    list.filter.setText('words 7');
    list.refilter();
    final filterMs = sw.elapsedMilliseconds;
    sw = Stopwatch()..start();
    list.filter.setText('~<=5m');
    list.refilter();
    final etaMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'files ${s.files.length}, tasks ${s.taskCount}: load ${load}ms, list ${listMs}ms '
      '(${list.rows.length} rows), agenda ${agendaMs}ms, text filter ${filterMs}ms, eta filter ${etaMs}ms',
    );
    list.dispose();
    agenda.dispose();
    s.dispose();
    tmp?.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
