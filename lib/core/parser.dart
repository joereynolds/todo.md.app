// Parsing of the task syntax (see the desktop app's docs/task-syntax.md),
// plus pure transformations of single task lines. Mirrors src/parser.cpp.

import 'day.dart';
import 'task.dart';

const int _space = 0x20, _tab = 0x09, _cr = 0x0d;
const int _dash = 0x2d, _star = 0x2a, _plus = 0x2b, _lbr = 0x5b, _rbr = 0x5d;
const int _bang = 0x21, _x = 0x78, _bigX = 0x58, _slash = 0x2f, _tilde = 0x7e, _tick = 0x60;
const int _zero = 0x30, _nine = 0x39;

bool _isSpace(int c) => c == _space || c == _tab;

TaskState? _stateFromChar(int c) {
  switch (c) {
    case _space:
      return TaskState.todo;
    case _slash:
      return TaskState.doing;
    case _x:
    case _bigX:
      return TaskState.done;
    case _dash:
      return TaskState.cancelled;
  }
  return null;
}

String stateChar(TaskState s) => switch (s) {
  TaskState.todo => ' ',
  TaskState.doing => '/',
  TaskState.done => 'x',
  TaskState.cancelled => '-',
};

/// "90m", "2h", "7d", "5w", "85y" -> minutes; -1 if not an ETA.
int parseEta(String t, [int start = 0, int? end]) {
  end ??= t.length;
  final n = end - start;
  if (n < 2 || n > 10) return -1;
  var v = 0;
  for (var i = start; i < end - 1; i++) {
    final c = t.codeUnitAt(i);
    if (c < _zero || c > _nine) return -1;
    v = v * 10 + (c - _zero);
  }
  switch (t.codeUnitAt(end - 1)) {
    case 0x6d: // m
      return v;
    case 0x68: // h
      return v * 60;
    case 0x64: // d
      return v * 60 * 24;
    case 0x77: // w
      return v * 60 * 24 * 7;
    case 0x79: // y
      return v * 60 * 24 * 365;
  }
  return -1;
}

int _digit(String s, int i) {
  final c = s.codeUnitAt(i);
  return c >= _zero && c <= _nine ? c - _zero : -1;
}

/// "!2026-12-25", "+…", "x…", "-…": returns (kind, day) or null.
(int, Day)? _dateToken(String s, int st, int end) {
  if (end - st != 11) return null;
  final k = s.codeUnitAt(st);
  if (k != _bang && k != _plus && k != _x && k != _dash) return null;
  if (s.codeUnitAt(st + 5) != _dash || s.codeUnitAt(st + 8) != _dash) return null;
  var y = 0, m = 0, d = 0;
  for (final i in const [1, 2, 3, 4]) {
    final v = _digit(s, st + i);
    if (v < 0) return null;
    y = y * 10 + v;
  }
  for (final i in const [6, 7]) {
    final v = _digit(s, st + i);
    if (v < 0) return null;
    m = m * 10 + v;
  }
  for (final i in const [9, 10]) {
    final v = _digit(s, st + i);
    if (v < 0) return null;
    d = d * 10 + v;
  }
  final day = validDay(y, m, d);
  return day == null ? null : (k, day);
}

bool _isEtaToken(String s, int st, int end) =>
    end - st >= 3 && s.codeUnitAt(st) == _tilde && parseEta(s, st + 1, end) >= 0;

/// Fills text, dates and ETA from task.content.
void parseMeta(Task t) {
  final c = t.content;
  final n = c.length;
  final text = StringBuffer();
  for (var i = 0; i < n;) {
    while (i < n && _isSpace(c.codeUnitAt(i))) {
      i++;
    }
    final st = i;
    while (i < n && !_isSpace(c.codeUnitAt(i))) {
      i++;
    }
    if (st == i) break;
    if (i - st >= 3 && c.codeUnitAt(st) == _tilde) {
      final eta = parseEta(c, st + 1, i);
      if (eta >= 0) {
        t.eta = eta;
        t.etaText = c.substring(st + 1, i);
        continue;
      }
    }
    final date = _dateToken(c, st, i);
    if (date != null) {
      switch (date.$1) {
        case _bang:
          t.due = date.$2;
        case _plus:
          t.created = date.$2;
        case _x:
          t.completed = date.$2;
        case _dash:
          t.cancelled = date.$2;
      }
      continue;
    }
    if (text.isNotEmpty) text.writeCharCode(_space);
    text.write(c.substring(st, i));
  }
  t.text = text.toString();
}

/// Parses a whole file. Tasks inside fenced code blocks are ignored; a
/// non-blank line closes every open task indented at or deeper than it.
TaskFile parse(String path, String relPath, String data) {
  final file = TaskFile(path, relPath);
  file.hash = Object.hash(data.length, data.hashCode);

  final stackIndent = <int>[];
  final stackIdx = <int>[];
  final parentIdx = <int>[];
  final tasks = file.tasks;
  final n = data.length;
  var fence = 0, fenceLen = 0;
  var s = 0;
  for (var lineNo = 0; s < n; lineNo++) {
    final nl = data.indexOf('\n', s);
    final next = nl < 0 ? n : nl + 1;
    var e = nl < 0 ? n : nl;
    if (e > s && data.codeUnitAt(e - 1) == _cr) e--;

    var q = s, col = 0;
    while (q < e) {
      final c = data.codeUnitAt(q);
      if (c == _space) {
        col++;
      } else if (c == _tab) {
        col += 4 - (col % 4);
      } else {
        break;
      }
      q++;
    }
    if (q == e) {
      s = next; // blank line: keeps nesting
      continue;
    }

    final c0 = data.codeUnitAt(q);
    // Fenced code blocks: tasks inside them are examples, not tasks.
    if ((c0 == _tick || c0 == _tilde) && e - q >= 3 && data.codeUnitAt(q + 1) == c0 && data.codeUnitAt(q + 2) == c0) {
      var r = q;
      while (r < e && data.codeUnitAt(r) == c0) {
        r++;
      }
      if (fence == 0) {
        fence = c0;
        fenceLen = r - q;
      } else if (c0 == fence && r - q >= fenceLen) {
        fence = 0;
      }
      s = next;
      continue;
    }
    if (fence != 0) {
      s = next;
      continue;
    }

    while (stackIndent.isNotEmpty && stackIndent.last >= col) {
      stackIndent.removeLast();
      stackIdx.removeLast();
    }

    if ((c0 == _dash || c0 == _star || c0 == _plus) &&
        e - q >= 6 &&
        data.codeUnitAt(q + 1) == _space &&
        data.codeUnitAt(q + 2) == _lbr &&
        data.codeUnitAt(q + 4) == _rbr &&
        data.codeUnitAt(q + 5) == _space) {
      final st = _stateFromChar(data.codeUnitAt(q + 3));
      if (st != null) {
        final t = Task(
          line: lineNo,
          indent: col,
          state: st,
          prefix: data.substring(s, q + 6),
          content: data.substring(q + 6, e),
        );
        parseMeta(t);
        parentIdx.add(stackIdx.isEmpty ? -1 : stackIdx.last);
        stackIndent.add(col);
        stackIdx.add(tasks.length);
        tasks.add(t);
      }
    }
    s = next;
  }

  for (var i = 0; i < tasks.length; i++) {
    final t = tasks[i];
    t.file = file;
    final p = parentIdx[i];
    if (p >= 0) {
      final parent = tasks[p];
      t.parent = parent;
      t.depth = parent.depth + 1;
      parent.children.add(t);
    } else {
      file.roots.add(t);
    }
  }
  // Children always follow their parent, so a reverse pass accumulates bottom-up.
  for (var i = tasks.length - 1; i >= 0; i--) {
    final t = tasks[i];
    if (t.state != TaskState.cancelled) {
      file.total++;
      if (t.state == TaskState.done) file.done++;
    }
    final p = t.parent;
    if (p == null || t.state == TaskState.cancelled) continue;
    p.subTotal += 1 + t.subTotal;
    p.subDone += (t.state == TaskState.done ? 1 : 0) + t.subDone;
  }
  return file;
}

// ---------------------------------------------------------------- line transforms

class TaskLine {
  const TaskLine(this.prefixLen, this.indent, this.state);
  final int prefixLen; // up to and including the space after ']'
  final int indent;
  final TaskState state;
}

/// Recognises `<ws>- [c] rest`.
TaskLine? splitTaskLine(String line) {
  final n = line.length;
  var i = 0, col = 0;
  while (i < n && _isSpace(line.codeUnitAt(i))) {
    col += line.codeUnitAt(i) == _tab ? 4 - (col % 4) : 1;
    i++;
  }
  if (n - i < 6) return null;
  final b = line.codeUnitAt(i);
  if ((b != _dash && b != _star && b != _plus) ||
      line.codeUnitAt(i + 1) != _space ||
      line.codeUnitAt(i + 2) != _lbr ||
      line.codeUnitAt(i + 4) != _rbr ||
      line.codeUnitAt(i + 5) != _space) {
    return null;
  }
  final st = _stateFromChar(line.codeUnitAt(i + 3));
  return st == null ? null : TaskLine(i + 6, col, st);
}

/// Removes tokens matching `pred`, along with the whitespace before them.
String _removeTokens(String content, bool Function(String s, int st, int end) pred) {
  final spans = <(int, int)>[];
  final n = content.length;
  for (var i = 0; i < n;) {
    while (i < n && _isSpace(content.codeUnitAt(i))) {
      i++;
    }
    final st = i;
    while (i < n && !_isSpace(content.codeUnitAt(i))) {
      i++;
    }
    if (st == i) break;
    if (pred(content, st, i)) spans.add((st, i));
  }
  if (spans.isEmpty) return content;
  var out = content;
  for (final (start, end) in spans.reversed) {
    var a = start, b = end;
    if (a > 0) {
      while (a > 0 && _isSpace(out.codeUnitAt(a - 1))) {
        a--;
      }
    } else {
      while (b < out.length && _isSpace(out.codeUnitAt(b))) {
        b++;
      }
    }
    out = out.substring(0, a) + out.substring(b);
  }
  return out;
}

bool Function(String, int, int) _dateKinds(String kinds) => (s, st, end) {
  final d = _dateToken(s, st, end);
  return d != null && kinds.codeUnits.contains(d.$1);
};

String _appendToken(String content, String token) {
  if (content.isEmpty || _isSpace(content.codeUnitAt(content.length - 1))) return content + token;
  return '$content $token';
}

String setState(String line, TaskState state, Day today) {
  final tl = splitTaskLine(line);
  if (tl == null || tl.state == state) return line;
  final pl = tl.prefixLen;
  final prefix = line.substring(0, pl - 3) + stateChar(state) + line.substring(pl - 2, pl);
  var content = _removeTokens(line.substring(pl), _dateKinds('x-'));
  if (state == TaskState.done) {
    content = _appendToken(content, 'x${isoDay(today)}');
  } else if (state == TaskState.cancelled) {
    content = _appendToken(content, '-${isoDay(today)}');
  }
  return prefix + content;
}

/// A null due removes it.
String setDue(String line, Day? due) {
  final tl = splitTaskLine(line);
  if (tl == null) return line;
  var content = _removeTokens(line.substring(tl.prefixLen), _dateKinds('!'));
  if (due != null) content = _appendToken(content, '!${isoDay(due)}');
  return line.substring(0, tl.prefixLen) + content;
}

/// "30m"; empty removes it.
String setEta(String line, String eta) {
  final tl = splitTaskLine(line);
  if (tl == null) return line;
  var content = _removeTokens(line.substring(tl.prefixLen), _isEtaToken);
  if (eta.isNotEmpty) content = _appendToken(content, '~$eta');
  return line.substring(0, tl.prefixLen) + content;
}

/// Adds +date unless the line already has one (keeps a date the user typed).
String setCreated(String line, Day date) {
  final tl = splitTaskLine(line);
  if (tl == null) return line;
  final t = Task(line: 0, indent: 0, state: tl.state, prefix: '', content: line.substring(tl.prefixLen));
  parseMeta(t);
  if (t.created != null) return line;
  return line.substring(0, tl.prefixLen) + _appendToken(t.content, '+${isoDay(date)}');
}

String setContent(String line, String content) {
  final tl = splitTaskLine(line);
  if (tl == null) return line;
  return line.substring(0, tl.prefixLen) + content;
}

String leadingWhitespace(String line) {
  var i = 0;
  while (i < line.length && _isSpace(line.codeUnitAt(i))) {
    i++;
  }
  return line.substring(0, i);
}
