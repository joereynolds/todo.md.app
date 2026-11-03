// The edits behind every action. Bulk actions always include the subtasks of
// every selected task (MainWindow's actions in src/mainwindow.cpp).

import 'day.dart';
import 'edits.dart';
import 'parser.dart' as parser;
import 'store.dart';
import 'task.dart';
import 'templates.dart';

const stateLabels = {
  TaskState.todo: 'Mark todo',
  TaskState.doing: 'Mark in progress',
  TaskState.done: 'Mark done',
  TaskState.cancelled: 'Mark cancelled',
};

/// The tasks in visual (file, line) order, each followed by its descendants
/// when [withSubtasks]; no duplicates.
List<Task> expand(Iterable<Task> tasks, {bool withSubtasks = true}) {
  final sorted = tasks.toList()
    ..sort((a, b) => a.file != b.file ? a.file.row.compareTo(b.file.row) : a.line.compareTo(b.line));
  final out = <Task>[];
  final seen = <Task>{};
  void add(Task t) {
    if (!seen.add(t)) return;
    out.add(t);
    if (withSubtasks) {
      for (final c in t.children) {
        add(c);
      }
    }
  }

  sorted.forEach(add);
  return out;
}

/// The tasks as a markdown bullet list of their text only (no checkbox,
/// dates, ETA or tags), in visual order, for pasting elsewhere. Only the given
/// tasks, not their subtasks; a task is indented under the selected tasks
/// above it in the tree.
String bulletList(Iterable<Task> tasks) {
  final picked = expand(tasks, withSubtasks: false);
  final set = picked.toSet();
  final b = StringBuffer();
  for (final t in picked) {
    var level = 0;
    for (var p = t.parent; p != null; p = p.parent) {
      if (set.contains(p)) level++;
    }
    b.writeln('${'  ' * level}- ${t.text}');
  }
  return b.toString();
}

Task lastDescendant(Task t) {
  while (t.children.isNotEmpty) {
    t = t.children.last;
  }
  return t;
}

/// Indentation step used for nesting in this file, guessed from existing subtasks.
String indentUnit(TaskFile f) {
  for (final t in f.tasks) {
    final p = t.parent;
    if (p == null) continue;
    final child = parser.leadingWhitespace(t.prefix);
    final parent = parser.leadingWhitespace(p.prefix);
    if (child.startsWith(parent) && child.length > parent.length) return child.substring(parent.length);
  }
  return '  ';
}

class TaskActions {
  TaskActions(this.store, {this.stampCreated = true});
  final TaskStore store;

  /// New tasks get +today (off for templates, where inserting adds it).
  final bool stampCreated;

  int _run(List<Edit> edits, String label) => store.apply(edits, label);

  Edit _line(Task t, String after) => Edit(t.file.path, t.line, [t.raw], [after]);

  /// A new task line: the picked due date (replacing a typed one) and +today.
  String _newLine(String line, Day? due) {
    if (due != null) line = parser.setDue(line, due);
    return stampCreated ? parser.setCreated(line, today()) : line;
  }

  /// Where new top-level tasks go: todo.md in the first folder.
  String get inboxPath => '${store.roots.first}/todo.md';

  int setState(Iterable<Task> selected, TaskState state) {
    final now = today();
    final edits = [
      for (final t in expand(selected))
        if (t.state != state) _line(t, parser.setState(t.raw, state, now)),
    ];
    return _run(edits, stateLabels[state]!);
  }

  /// Done unless every selected task (not counting subtasks) is done already.
  int toggleDone(Iterable<Task> selected) {
    final list = selected.toList();
    final allDone = list.isNotEmpty && list.every((t) => t.state == TaskState.done);
    return setState(list, allDone ? TaskState.todo : TaskState.done);
  }

  /// Checkbox: done <-> todo for this task and all its subtasks.
  int toggleTask(Task task) => setState([task], task.state == TaskState.done ? TaskState.todo : TaskState.done);

  int setDue(Iterable<Task> selected, Day? due) {
    final edits = [
      for (final t in expand(selected))
        if (t.due != due) _line(t, parser.setDue(t.raw, due)),
    ];
    return _run(edits, due == null ? 'Clear due date' : 'Set due date');
  }

  int setEta(Iterable<Task> selected, String eta) {
    final edits = [
      for (final t in expand(selected))
        if (t.etaText != eta) _line(t, parser.setEta(t.raw, eta)),
    ];
    return _run(edits, eta.isEmpty ? 'Clear ETA' : 'Set ETA');
  }

  int setContent(Task t, String content) {
    content = content.replaceAll('\n', ' ');
    if (content == t.content) return 0;
    return _run([_line(t, parser.setContent(t.raw, content))], 'Edit');
  }

  /// Tags belong to one task, so these don't touch subtasks.
  int addTag(Task t, String tag) {
    final line = parser.addTag(t.raw, tag);
    return line == t.raw ? 0 : _run([_line(t, line)], 'Add #$tag');
  }

  int removeTag(Task t, String tag) {
    final line = parser.removeTag(t.raw, tag);
    return line == t.raw ? 0 : _run([_line(t, line)], 'Remove #$tag');
  }

  int replace(Iterable<Task> selected, String Function(String content) fn) {
    final edits = <Edit>[];
    for (final t in expand(selected)) {
      final c = fn(t.content);
      if (c != t.content) edits.add(_line(t, parser.setContent(t.raw, c)));
    }
    return _run(edits, 'Replace');
  }

  int delete(Iterable<Task> selected) {
    final edits = [
      for (final t in expand(selected)) Edit(t.file.path, t.line, [t.raw], []),
    ];
    return _run(edits, 'Delete');
  }

  /// Adds after [anchor]'s last descendant, as a sibling or (subtask) its last
  /// child. Returns the new task's key, or null if nothing was written.
  LineKey? addAfter(Task anchor, String text, {required bool subtask, Day? due}) {
    text = text.replaceAll('\n', ' ');
    final file = anchor.file;
    final lead = parser.leadingWhitespace(anchor.prefix);
    final bullet = anchor.prefix[lead.length];
    var indent = lead;
    if (subtask) {
      indent = anchor.children.isEmpty
          ? lead + indentUnit(file)
          : parser.leadingWhitespace(anchor.children.first.prefix);
    }
    final after = lastDescendant(anchor);
    final line = _newLine('$indent$bullet [ ] $text', due);
    final n = _run([
      Edit(file.path, after.line, [after.raw], [after.raw, line]),
    ], subtask ? 'Add subtask' : 'Add task');
    return n > 0 ? (path: file.path, line: after.line + 1) : null;
  }

  /// Appends a top-level task to the end of [path] (created if missing).
  /// Returns the new task's key, or null if nothing was written.
  LineKey? append(String path, String text, {Day? due}) {
    text = text.replaceAll('\n', ' ');
    final line = _newLine('- [ ] $text', due);
    store.createFile(path);
    final n = _run([
      Edit(path, -1, [], [line]),
    ], 'Add task');
    if (n == 0) return null;
    final f = store.fileByPath(path);
    return f == null || f.tasks.isEmpty ? null : (path: path, line: f.tasks.last.line);
  }

  /// Inserts the tasks of a template (its file's text): after [anchor]'s
  /// subtree at its level, or as its last subtasks, or (no anchor) at the end
  /// of [path]. Re-indented with the file's indent unit, all todo, created
  /// today. Returns the keys of the new tasks (empty if nothing was written).
  List<LineKey> insertTemplate(String name, String data, {Task? anchor, bool asSubtasks = false, String? path}) {
    final now = today();
    if (anchor != null) {
      final file = anchor.file;
      final unit = indentUnit(file);
      var lead = parser.leadingWhitespace(anchor.prefix);
      if (asSubtasks) {
        lead = anchor.children.isEmpty ? lead + unit : parser.leadingWhitespace(anchor.children.first.prefix);
      }
      final lines = instantiateTemplate(data, lead: lead, unit: unit, today: now);
      if (lines.isEmpty) return [];
      final after = lastDescendant(anchor);
      final n = _run([
        Edit(file.path, after.line, [after.raw], [after.raw, ...lines]),
      ], 'Insert "$name"');
      return n == 0 ? [] : [for (var i = 0; i < lines.length; i++) (path: file.path, line: after.line + 1 + i)];
    }
    final target = path ?? inboxPath;
    final existing = store.fileByPath(target);
    final unit = existing == null ? '  ' : indentUnit(existing);
    final lines = instantiateTemplate(data, lead: '', unit: unit, today: now);
    if (lines.isEmpty) return [];
    store.createFile(target);
    final before = store.fileByPath(target)?.tasks.length ?? 0;
    final n = _run([
      Edit(target, -1, [], lines),
    ], 'Insert "$name"');
    final f = store.fileByPath(target);
    if (n == 0 || f == null) return [];
    return [for (final t in f.tasks.skip(before)) (path: target, line: t.line)];
  }
}
