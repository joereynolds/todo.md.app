// What the search box, state toggles and ETA preset select. Mirrors
// TaskFilter in src/models.cpp. A task matches when its state is visible and
// every term holds:
//   word            occurs in the raw content or the file path (case-insensitive)
//   ~<=15m ~<1h ~>2h ~>=1d ~30m ~none ~any            ETA conditions
//   due:overdue due:today due:week due:none due:any   (week = next 7 days)
//   is:todo is:doing is:done is:cancelled is:open

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

class TaskFilter {
  final List<String> _terms = []; // lower case
  final List<EtaCond> _textConds = [];
  List<EtaCond> _presetConds = const [];
  final List<_Due> _due = [];
  int _isMask = 0; // from is: terms, 0 = no constraint
  int states = 0xF;
  Day _today = today();
  String _text = '';

  String get text => _text;

  void setText(String text) {
    _text = text;
    _terms.clear();
    _textConds.clear();
    _due.clear();
    _isMask = 0;
    _today = today();
    for (final term in text.split(' ')) {
      if (term.isEmpty) continue;
      final c = EtaCond.parse(term);
      if (c != null) {
        _textConds.add(c);
        continue;
      }
      final lower = term.toLowerCase();
      if (lower.startsWith('due:')) {
        final d = _dueNames[lower.substring(4)];
        if (d != null) {
          _due.add(d);
          continue;
        }
      } else if (lower.startsWith('is:')) {
        final bits = _isNames[lower.substring(3)];
        if (bits != null) {
          _isMask |= bits;
          continue;
        }
      }
      _terms.add(lower);
    }
  }

  void setStateVisible(TaskState s, bool visible) {
    states = visible ? (states | stateBit(s)) : (states & ~stateBit(s));
  }

  bool stateVisible(TaskState s) => states & stateBit(s) != 0;

  set etaPreset(List<EtaCond> conds) => _presetConds = conds;

  /// True when terms or ETA conditions narrow the result (state toggles aside).
  bool get narrows =>
      _terms.isNotEmpty || _textConds.isNotEmpty || _presetConds.isNotEmpty || _due.isNotEmpty || _isMask != 0;

  bool get showsEverything => states == 0xF && !narrows;

  bool matches(Task t) {
    final bit = stateBit(t.state);
    if (states & bit == 0 || (_isMask != 0 && _isMask & bit == 0)) return false;
    for (final c in _presetConds) {
      if (!c.holds(t.eta)) return false;
    }
    for (final c in _textConds) {
      if (!c.holds(t.eta)) return false;
    }
    for (final d in _due) {
      final due = t.due;
      final ok = switch (d) {
        _Due.overdue => t.isOpen && due != null && due < _today,
        _Due.today => due == _today,
        _Due.week => due != null && due >= _today && due < _today + 7,
        _Due.none => due == null,
        _Due.any => due != null,
      };
      if (!ok) return false;
    }
    for (final term in _terms) {
      if (!t.contentLower.contains(term) && !t.file.relPathLower.contains(term)) return false;
    }
    return true;
  }
}
