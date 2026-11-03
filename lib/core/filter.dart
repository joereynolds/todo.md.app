// What the search box, state toggles and ETA preset select. Mirrors
// TaskFilter in src/models.cpp. A task matches when its state is visible and
// every term holds:
//   word            occurs in the raw content or the file path (case-insensitive)
//   ~<=15m ~<1h ~>2h ~>=1d ~30m ~none ~any            ETA conditions
//   due:overdue due:today due:week due:none due:any   (week = next 7 days)
//   is:todo is:doing is:done is:cancelled is:open
//   done:today done:week   finished today / in the last 7 days; these show
//                          even when the Done state toggle is off
//   #tag            has that tag, or one under it (#work matches #work/admin)
// OR (capitals, on its own) between terms gives alternatives: "a b OR c" is
// (a and b) or c. A saved view's filter (setView) works the same way and is
// combined with the search box: both must match.

import 'day.dart';
import 'parser.dart' as parser;
import 'task.dart';

enum EtaOp { lt, le, gt, ge, eq, none, any }

class EtaCond {
  const EtaCond(this.op, [this.minutes = 0]);
  final EtaOp op;
  final int minutes;

  bool holds(int eta) => switch (op) {
    EtaOp.none => eta == 0,
    EtaOp.any => eta > 0,
    EtaOp.lt => eta > 0 && eta < minutes,
    EtaOp.le => eta > 0 && eta <= minutes,
    EtaOp.gt => eta > 0 && eta > minutes,
    EtaOp.ge => eta > 0 && eta >= minutes,
    EtaOp.eq => eta > 0 && eta == minutes,
  };

  static EtaCond? parse(String term) {
    if (!term.startsWith('~')) return null;
    var rest = term.substring(1);
    final lower = rest.toLowerCase();
    if (lower == 'none') return const EtaCond(EtaOp.none);
    if (lower == 'any') return const EtaCond(EtaOp.any);
    var op = EtaOp.eq;
    if (rest.startsWith('<=')) {
      op = EtaOp.le;
      rest = rest.substring(2);
    } else if (rest.startsWith('>=')) {
      op = EtaOp.ge;
      rest = rest.substring(2);
    } else if (rest.startsWith('<')) {
      op = EtaOp.lt;
      rest = rest.substring(1);
    } else if (rest.startsWith('>')) {
      op = EtaOp.gt;
      rest = rest.substring(1);
    } else if (rest.startsWith('=')) {
      rest = rest.substring(1);
    }
    final m = parser.parseEta(rest);
    return m < 0 ? null : EtaCond(op, m);
  }
}

class EtaPreset {
  const EtaPreset(this.label, this.conds);
  final String label;
  final List<EtaCond> conds;
}

const etaPresets = [
  EtaPreset('Any ETA', []),
  EtaPreset('≤ 2m (do it now)', [EtaCond(EtaOp.le, 2)]),
  EtaPreset('≤ 15m (quick)', [EtaCond(EtaOp.le, 15)]),
  EtaPreset('≤ 1h', [EtaCond(EtaOp.le, 60)]),
  EtaPreset('1h – 1d', [EtaCond(EtaOp.gt, 60), EtaCond(EtaOp.le, 60 * 24)]),
  EtaPreset('> 1d (involved)', [EtaCond(EtaOp.gt, 60 * 24)]),
  EtaPreset('Has ETA', [EtaCond(EtaOp.any)]),
  EtaPreset('No ETA', [EtaCond(EtaOp.none)]),
];

/// [tag] in lower case, without '#'. "#work" also matches "#work/admin".
bool hasTag(Task t, String tag) {
  for (final x in t.tags) {
    final l = x.toLowerCase();
    if (l == tag || (l.length > tag.length && l.startsWith(tag) && l.codeUnitAt(tag.length) == 0x2f)) return true;
  }
  return false;
}

/// The filter text for a tag (what tapping a tag sets).
String tagTerm(String tag) => '#${tag.toLowerCase()}';

enum _Due { overdue, today, week, none, any }

const _dueNames = {'overdue': _Due.overdue, 'today': _Due.today, 'week': _Due.week, 'none': _Due.none, 'any': _Due.any};

int stateBit(TaskState s) => 1 << s.index;

final _isNames = {
  'todo': stateBit(TaskState.todo),
  'doing': stateBit(TaskState.doing),
  'done': stateBit(TaskState.done),
  'cancelled': stateBit(TaskState.cancelled),
  'open': stateBit(TaskState.todo) | stateBit(TaskState.doing),
};

/// One alternative of a filter expression: every term must hold.
class _Clause {
  final List<String> terms = []; // lower case
  final List<EtaCond> eta = [];
  final List<_Due> due = [];
  final List<String> tags = []; // lower case, without '#'
  int isMask = 0; // from is: terms, 0 = no constraint
  int doneWithin = 0; // done:today = 1, done:week = 7 (days, today included); 0 = none

  bool get isEmpty => terms.isEmpty && eta.isEmpty && due.isEmpty && tags.isEmpty && isMask == 0 && doneWithin == 0;

  void add(String term) {
    final c = EtaCond.parse(term);
    if (c != null) {
      eta.add(c);
      return;
    }
    final lower = term.toLowerCase();
    final tag = parser.tagToken(lower);
    if (tag != null) {
      tags.add(tag);
      return;
    }
    if (lower.startsWith('due:')) {
      final d = _dueNames[lower.substring(4)];
      if (d != null) {
        due.add(d);
        return;
      }
    } else if (lower == 'done:today' || lower == 'done:week') {
      final days = lower == 'done:today' ? 1 : 7;
      doneWithin = doneWithin == 0 ? days : (days < doneWithin ? days : doneWithin);
      return;
    } else if (lower.startsWith('is:')) {
      final bits = _isNames[lower.substring(3)];
      if (bits != null) {
        isMask |= bits;
        return;
      }
    }
    terms.add(lower);
  }

  bool matches(Task t, Day today) {
    if (isMask != 0 && isMask & stateBit(t.state) == 0) return false;
    if (doneWithin > 0) {
      final c = t.completed;
      if (t.state != TaskState.done || c == null || c > today || c <= today - doneWithin) return false;
    }
    for (final c in eta) {
      if (!c.holds(t.eta)) return false;
    }
    for (final d in due) {
      final v = t.due;
      final ok = switch (d) {
        _Due.overdue => t.isOpen && v != null && v < today,
        _Due.today => v == today,
        _Due.week => v != null && v >= today && v < today + 7,
        _Due.none => v == null,
        _Due.any => v != null,
      };
      if (!ok) return false;
    }
    for (final tag in tags) {
      if (!hasTag(t, tag)) return false;
    }
    for (final term in terms) {
      if (!t.contentLower.contains(term) && !t.file.relPathLower.contains(term)) return false;
    }
    return true;
  }
}

/// Clauses joined by OR; empty = no constraint.
List<_Clause> _parse(String text) {
  final out = <_Clause>[];
  var c = _Clause();
  for (final term in text.split(RegExp(r'\s+'))) {
    if (term.isEmpty) continue;
    if (term == 'OR') {
      if (!c.isEmpty) out.add(c);
      c = _Clause();
      continue;
    }
    c.add(term);
  }
  if (!c.isEmpty) out.add(c);
  return out;
}

bool _any(List<_Clause> expr, Task t, Day today) {
  if (expr.isEmpty) return true;
  for (final c in expr) {
    if (c.matches(t, today)) return true;
  }
  return false;
}

/// Whether a done: clause matches: asking for finished tasks shows them even
/// with the Done toggle off.
bool _anyDone(List<_Clause> expr, Task t, Day today) {
  for (final c in expr) {
    if (c.doneWithin > 0 && c.matches(t, today)) return true;
  }
  return false;
}

class TaskFilter {
  List<_Clause> _search = const [];
  List<_Clause> _view = const [];
  List<EtaCond> _presetConds = const [];
  int states = 0xF;
  Day _today = today();
  String _text = '', _viewText = '';

  String get text => _text;
  String get viewText => _viewText;

  void setText(String text) {
    _text = text;
    _search = _parse(text);
    _done = _hasDone;
    _today = today();
  }

  /// The active view's filter ('' for none), combined with [setText]'s.
  void setView(String text) {
    _viewText = text;
    _view = _parse(text);
    _done = _hasDone;
    _today = today();
  }

  void setStateVisible(TaskState s, bool visible) {
    states = visible ? (states | stateBit(s)) : (states & ~stateBit(s));
  }

  bool stateVisible(TaskState s) => states & stateBit(s) != 0;

  set etaPreset(List<EtaCond> conds) => _presetConds = conds;

  /// True when terms or ETA conditions narrow the result (state toggles aside).
  bool get narrows => _search.isNotEmpty || _view.isNotEmpty || _presetConds.isNotEmpty;

  /// The search box narrows (not counting the view or the ETA preset).
  bool get searchNarrows => _search.isNotEmpty;

  bool get showsEverything => states == 0xF && !narrows;

  bool get _hasDone => _search.any((c) => c.doneWithin > 0) || _view.any((c) => c.doneWithin > 0);
  bool _done = false; // cached _hasDone

  bool matches(Task t) {
    final visible = states & stateBit(t.state) != 0;
    if (!visible && !_done) return false;
    for (final c in _presetConds) {
      if (!c.holds(t.eta)) return false;
    }
    if (!_any(_view, t, _today) || !_any(_search, t, _today)) return false;
    return visible || _anyDone(_search, t, _today) || _anyDone(_view, t, _today);
  }
}
