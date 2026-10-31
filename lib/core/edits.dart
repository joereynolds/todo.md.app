// Line edits with verified `before` lines and exact inverses for undo.
// Mirrors src/edits.cpp.
//
//   replace: before = [old],    after = [new]
//   insert:  before = [anchor], after = [anchor, new]
//   delete:  before = [old],    after = []
//   append:  line = -1, before = [], after = [new]

class Edit {
  Edit(this.path, this.line, this.before, this.after);
  final String path;
  int line;
  final List<String> before;
  final List<String> after;

  @override
  String toString() => 'Edit($path:$line $before -> $after)';
}

/// File contents split into lines, preserving line endings.
class LineBuffer {
  LineBuffer(this.lines, {this.crlf = false, this.trailingNewline = true});

  final List<String> lines; // without '\n'; a trailing '\r' is kept
  bool crlf; // the file uses CRLF; applied to new lines
  bool trailingNewline;

  factory LineBuffer.fromString(String data) {
    if (data.isEmpty) return LineBuffer([]);
    final lines = data.split('\n');
    var trailing = true;
    if (data.endsWith('\n')) {
      lines.removeLast();
    } else {
      trailing = false;
    }
    final crlf = lines.isNotEmpty && lines.first.endsWith('\r');
    return LineBuffer(lines, crlf: crlf, trailingNewline: trailing);
  }

  @override
  String toString() {
    final out = lines.join('\n');
    return trailingNewline && lines.isNotEmpty ? '$out\n' : out;
  }
}

class ApplyResult {
  int applied = 0;
  int conflicts = 0; // edits whose `before` did not match
  final List<Edit> inverse = []; // undoes the applied edits (positions valid afterwards)
}

String _lineText(String l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l;

/// Applies the edits for a single file. Overlapping edits after the first
/// are counted as conflicts.
ApplyResult applyEdits(LineBuffer buf, List<Edit> input) {
  final res = ApplyResult();
  final edits = [for (final e in input) Edit(e.path, e.line < 0 ? buf.lines.length : e.line, e.before, e.after)];
  // Bottom-up, so earlier line numbers stay valid while applying. At the same
  // line, edits that consume lines go before pure insertions, and insertions
  // go last-first so they end up in list order.
  final order = List<int>.generate(edits.length, (i) => i);
  order.sort((a, b) {
    final x = edits[a], y = edits[b];
    if (x.line != y.line) return y.line.compareTo(x.line);
    if (x.before.length != y.before.length) return y.before.length.compareTo(x.before.length);
    return b.compareTo(a);
  });

  final applied = <Edit>[];
  var limit = buf.lines.length;
  for (final i in order) {
    final e = edits[i];
    final k = e.before.length;
    var ok = e.line + k <= limit;
    for (var j = 0; ok && j < k; j++) {
      ok = _lineText(buf.lines[e.line + j]) == e.before[j];
    }
    if (!ok) {
      res.conflicts++;
      continue;
    }
    buf.lines.replaceRange(e.line, e.line + k, [for (final a in e.after) buf.crlf ? '$a\r' : a]);
    limit = e.line;
    applied.add(e);
  }

  // An edit's final position is shifted by the size changes of every edit above it.
  var shift = 0;
  for (final e in applied.reversed) {
    res.inverse.add(Edit(e.path, e.line + shift, e.after, e.before));
    shift += e.after.length - e.before.length;
  }
  res.applied = applied.length;
  return res;
}
