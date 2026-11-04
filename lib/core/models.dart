// A tree presented as a flat list: per group (a file, an agenda day) a header
// row followed by its tasks and their subtasks in depth-first order. A node's
// descendants are a contiguous run of rows, so collapse/expand is a single
// remove/insert. Mirrors FlatTaskModel in src/models.cpp.
//
// Filtering is built in: a matching task keeps its ancestors visible. While
// the filter narrows, the remembered collapse state is ignored so every match
// shows; toggles made then are temporary.

import 'package:flutter/foundation.dart';

import 'day.dart';
import 'filter.dart';
import 'store.dart';
import 'task.dart';

class Group {
  Group(this.key, {this.file, this.date});
  final String key; // collapse key of the header
  final TaskFile? file; // file groups
  final Day? date; // day groups
  final List<Task> roots = [];
  bool keepWhenEmpty = false; // shown even with no visible tasks (unless filtering)
}

class ListRow {
  ListRow(this.task, this.group, this.depth, this.hasChildren, this.expanded);
  final Task? task; // null for the group header
  final int group;
  final int depth; // 0 = header
  bool hasChildren;
  bool expanded;
  bool get isHeader => task == null;
}

abstract class FlatModel extends ChangeNotifier {
  FlatModel(this.store) {
    store.addListener(_onStore);
  }

  final TaskStore store;
  final TaskFilter filter = TaskFilter();
  final List<Group> groups = [];
  final List<ListRow> rows = [];
  Set<String> _collapsed = {}; // group keys and path + '\x1f' + task text
  final Set<String> _tempCollapsed = {}; // while the filter narrows
  bool _all = true;

  /// Without headers (a template's own list), groups just run on and can't
  /// be collapsed; tasks keep depth 1 and up.
  bool get showHeaders => _showHeaders;
  bool _showHeaders = true;
  set showHeaders(bool v) {
    if (v == _showHeaders) return;
    _showHeaders = v;
    reset();
  }

  /// Called when the persistent collapse state changes.
  void Function(List<String> keys)? onCollapsedChanged;

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() => reset();

  @protected
  void collectGroups(List<Group> out);
  @protected
  void clearIndex();
  @protected
  void reindex(int first);
  ListRow? rowOf(Task t);
  int indexOf(Task t);

  Set<String> get _active => filter.narrows ? _tempCollapsed : _collapsed;

  static String taskKey(Task t) => '${t.file.path}\x1f${t.text}';
  String rowKey(ListRow r) => r.task != null ? taskKey(r.task!) : groups[r.group].key;

  bool _isCollapsed(String key) {
    final c = _active;
    return c.isNotEmpty && c.contains(key);
  }

  void reset() {
    _rebuild();
    notifyListeners();
  }

  /// Call after changing [filter].
  void refilter() {
    _tempCollapsed.clear();
    reset();
  }

  void _rebuild() {
    groups.clear();
    collectGroups(groups);
    rows.clear();
    clearIndex();
    _all = filter.showsEverything;
    for (var g = 0; g < groups.length; g++) {
      _appendGroupRows(g, rows);
    }
    reindex(0);
  }

  void _appendGroupRows(int g, List<ListRow> out) {
    final group = groups[g];
    final mark = out.length;
    final open = !_showHeaders || !_isCollapsed(group.key);
    if (_showHeaders) out.add(ListRow(null, g, 0, false, open));
    var any = false;
    for (final t in group.roots) {
      any |= _appendTask(t, g, 1, !open, out);
    }
    if (!any && !(group.keepWhenEmpty && !filter.narrows)) {
      out.length = mark;
      return;
    }
    if (_showHeaders) out[mark].hasChildren = any;
  }

  // Appends t and its visible descendants (unless `hidden`, under a collapsed
  // node, where only visibility is computed). Returns whether t is visible:
  // it matches, sits under a task that matches (`under`; its state must still
  // be shown), or has a visible descendant. So a view of #house shows the
  // subtasks of a #house task even though they don't carry the tag.
  //
  // `inView`: an ancestor matches the view's filter, which then holds for t
  // too, so the search box can find untagged subtasks within a #house view.
  bool _appendTask(
    Task t,
    int g,
    int depth,
    bool hidden,
    List<ListRow> out, [
    bool under = false,
    bool inView = false,
  ]) {
    if (_all) {
      if (hidden) return true;
      final kids = t.children.isNotEmpty;
      final open = !kids || !_isCollapsed(taskKey(t));
      out.add(ListRow(t, g, depth, kids, open));
      if (open) {
        for (final c in t.children) {
          _appendTask(c, g, depth + 1, false, out);
        }
      }
      return true;
    }
    final mark = out.length;
    if (!hidden) out.add(ListRow(t, g, depth, false, true));
    final open = t.children.isEmpty || !_isCollapsed(taskKey(t));
    final viewed = inView || filter.viewMatches(t);
    final shown = (under && filter.stateVisible(t.state)) || filter.matches(t, inView: viewed);
    var anyChild = false;
    for (final c in t.children) {
      anyChild |= _appendTask(c, g, depth + 1, hidden || !open, out, shown, viewed);
    }
    if (!anyChild && !shown) {
      if (!hidden) out.length = mark;
      return false;
    }
    if (!hidden) {
      out[mark].hasChildren = anyChild;
      out[mark].expanded = open || !anyChild;
    }
    return true;
  }

  void _persist() {
    if (!filter.narrows) onCollapsedChanged?.call(_collapsed.toList());
  }

  void setExpanded(int row, bool expand) {
    if (row < 0 || row >= rows.length) return;
    final r = rows[row];
    if (!r.hasChildren || r.expanded == expand) return;
    if (expand) {
      _active.remove(rowKey(r));
    } else {
      _active.add(rowKey(r));
    }
    r.expanded = expand;
    if (!expand) {
      var end = row + 1;
      while (end < rows.length && rows[end].depth > r.depth) {
        end++;
      }
      if (end > row + 1) {
        rows.removeRange(row + 1, end);
        clearIndex();
        reindex(0);
      }
    } else {
      // Regenerate the group's rows and take the run below the node.
      final groupRows = <ListRow>[];
      _appendGroupRows(r.group, groupRows);
      final i = groupRows.indexWhere((x) => x.task == r.task && x.depth == r.depth);
      if (i >= 0) {
        var last = i + 1;
        while (last < groupRows.length && groupRows[last].depth > r.depth) {
          last++;
        }
        if (last > i + 1) {
          rows.insertAll(row + 1, groupRows.sublist(i + 1, last));
          reindex(row + 1);
        }
      }
    }
    _persist();
    notifyListeners();
  }

  void toggle(int row) {
    if (row >= 0 && row < rows.length) setExpanded(row, !rows[row].expanded);
  }

  void expandAll() {
    _active.clear();
    _persist();
    reset();
  }

  /// Collapses the groups, leaving only their headers.
  void collapseAll() {
    for (final g in groups) {
      _active.add(g.key);
    }
    _persist();
    reset();
  }

  int parentRow(int row) {
    if (row <= 0 || row >= rows.length) return -1;
    final depth = rows[row].depth;
    for (var r = row - 1; r >= 0; r--) {
      if (rows[r].depth < depth) return r;
    }
    return -1;
  }

  /// End (exclusive) of the rows of the group whose header is at [row].
  int groupEnd(int row) {
    var end = row + 1;
    while (end < rows.length && !rows[end].isHeader) {
      end++;
    }
    return end;
  }

  List<String> get collapsedKeys => _collapsed.toList();
  set collapsedKeys(List<String> keys) {
    _collapsed = keys.toSet();
    reset();
  }

  @protected
  void forgetCollapsed(String key) {
    _collapsed.remove(key);
    _tempCollapsed.remove(key);
  }

  TaskFile? fileAtRow(int row) {
    final r = rows[row];
    return r.task?.file ?? groups[r.group].file;
  }
}

/// Every file with tasks. Task.listRow is this model's row lookup.
class TaskListModel extends FlatModel {
  TaskListModel(super.store) {
    reset();
  }

  @override
  void collectGroups(List<Group> out) {
    for (final f in store.files) {
      out.add(Group(f.path, file: f)..roots.addAll(f.roots));
    }
  }

  @override
  void clearIndex() {
    for (final f in store.files) {
      for (final t in f.tasks) {
        t.listRow = -1;
      }
    }
  }

  @override
  void reindex(int first) {
    for (var i = first; i < rows.length; i++) {
      final t = rows[i].task;
      if (t != null) t.listRow = i;
    }
  }

  @override
  int indexOf(Task t) => t.listRow;

  @override
  ListRow? rowOf(Task t) => t.listRow >= 0 ? rows[t.listRow] : null;

  /// Expands the task's file and ancestors so it gets a row; returns that
  /// row (-1 if the filter hides it).
  int reveal(Task t) {
    if (t.listRow < 0) {
      forgetCollapsed(t.file.path);
      for (var a = t.parent; a != null; a = a.parent) {
        forgetCollapsed(FlatModel.taskKey(a));
      }
      _persist();
      reset();
    }
    return t.listRow;
  }
}

/// The tasks of one file (a template), without a header row.
class FileModel extends TaskListModel {
  FileModel(super.store, this.path) {
    showHeaders = false;
  }
  String path;

  @override
  void collectGroups(List<Group> out) {
    final f = store.fileByPath(path);
    if (f != null) out.add(Group(f.path, file: f)..roots.addAll(f.roots));
  }
}

/// Open tasks with a due date, one group per day, each with its subtasks.
/// In single-day mode (the calendar's day list) only the chosen day is shown.
class AgendaModel extends FlatModel {
  AgendaModel(super.store, {Day? day}) : _day = day {
    reset();
  }

  Day? _day;
  bool _showEmpty = false;
  Day todayCached = today();
  final Map<Task, int> _rowOf = {};

  Day? get singleDay => _day;
  set singleDay(Day? d) {
    if (d == _day) return;
    _day = d;
    reset();
  }

  bool get showEmptyDays => _showEmpty;
  set showEmptyDays(bool on) {
    if (on == _showEmpty) return;
    _showEmpty = on;
    reset();
  }

  void refreshIfDateChanged() {
    if (today() != todayCached) reset();
  }

  @override
  void clearIndex() => _rowOf.clear();

  @override
  void reindex(int first) {
    _rowOf.clear();
    for (var i = 0; i < rows.length; i++) {
      final t = rows[i].task;
      if (t != null) _rowOf.putIfAbsent(t, () => i);
    }
  }

  @override
  int indexOf(Task t) => _rowOf[t] ?? -1;

  @override
  ListRow? rowOf(Task t) {
    final i = _rowOf[t];
    return i == null ? null : rows[i];
  }

  static Group _makeDay(Day d) => Group('day:${isoDay(d)}', date: d);

  @override
  void collectGroups(List<Group> out) {
    todayCached = today();
    final day = _day;
    final due = <Task>[];
    for (final f in store.files) {
      for (final t in f.tasks) {
        final d = t.due;
        if (d != null && t.isOpen && (day == null || d == day)) due.add(t);
      }
    }
    due.sort((a, b) {
      if (a.due != b.due) return a.due!.compareTo(b.due!);
      if (a.file != b.file) return a.file.row.compareTo(b.file.row);
      return a.line.compareTo(b.line);
    });

    var days = <Group>[];
    for (var i = 0; i < due.length;) {
      final g = _makeDay(due[i].due!);
      // A subtask due the same day as an ancestor already shows under it.
      final inDay = <Task>{};
      var j = i;
      for (; j < due.length && due[j].due == g.date; j++) {
        inDay.add(due[j]);
      }
      for (var k = i; k < j; k++) {
        var nested = false;
        for (var a = due[k].parent; a != null && !nested; a = a.parent) {
          nested = inDay.contains(a);
        }
        if (!nested) g.roots.add(due[k]);
      }
      days.add(g);
      i = j;
    }

    final now = todayCached;
    if (day != null) {
      if (days.isEmpty) days.add(_makeDay(day));
      days.first.keepWhenEmpty = true;
    } else if (_showEmpty) {
      // Every day from today to the last due date (at least two weeks ahead,
      // at most a year). Overdue days still only appear when they have tasks.
      var last = now + 13;
      if (days.isNotEmpty) {
        final l = days.last.date!;
        last = (l > last ? l : last);
        if (last > now + 366) last = now + 366;
      }
      final filled = <Group>[];
      var i = 0;
      for (; i < days.length && days[i].date! < now; i++) {
        filled.add(days[i]);
      }
      for (var d = now; d <= last; d++) {
        if (i < days.length && days[i].date == d) {
          filled.add(days[i++]);
        } else {
          filled.add(_makeDay(d)..keepWhenEmpty = true);
        }
      }
      for (; i < days.length; i++) {
        filled.add(days[i]);
      }
      days = filled;
    }
    out.addAll(days);
  }

  /// Relative wording only within two weeks; "overdue" only when the day
  /// actually has open tasks (an empty past day is just past).
  String relativeLabel(Group g) {
    final n = g.date! - todayCached;
    final empty = g.roots.isEmpty;
    if (n == 0) return 'today';
    if (n == 1) return 'tomorrow';
    if (n == -1) return empty ? 'yesterday' : '1 day overdue';
    if (n < 0 && n >= -14) return empty ? '${-n} days ago' : '${-n} days overdue';
    if (n > 0 && n <= 14) return 'in $n days';
    return '';
  }

  String dayLabel(Group g) {
    final d = g.date!;
    return '${weekdayNames[weekdayOf(d) - 1]} ${isoDay(d)}';
  }
}
