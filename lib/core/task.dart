import 'day.dart';

enum TaskState { todo, doing, done, cancelled }

class Task {
  Task({required this.line, required this.indent, required this.state, required this.prefix, required this.content});

  late TaskFile file;
  Task? parent;
  final List<Task> children = [];

  final int line; // 0-based line number in the file
  final int indent; // leading whitespace in columns (tab stops of 4)
  int depth = 0; // 0 for top-level tasks
  int listRow = -1; // row in TaskListModel, -1 when filtered out (owned by that model)
  final TaskState state;

  final String prefix; // "  - [ ] ": everything up to and including the space after ']'
  final String content; // raw text after the prefix, metadata tokens included
  String text = ''; // content with date and ETA tokens stripped, for display

  Day? due, created, completed, cancelled;
  int eta = 0; // estimate in minutes, 0 = none
  String etaText = ''; // as written, without the '~' (e.g. "90m")

  int subDone = 0; // completed descendants
  int subTotal = 0; // non-cancelled descendants

  String? _lower;
  String get contentLower => _lower ??= content.toLowerCase();

  String get raw => prefix + content;
  bool get isOpen => state == TaskState.todo || state == TaskState.doing;
}

class TaskFile {
  TaskFile(this.path, this.relPath);

  final String path; // absolute, '/' separated
  final String relPath; // relative to its root (prefixed with the root's name when there are several)
  List<Task> tasks = []; // in line order
  List<Task> roots = [];
  int done = 0; // completed tasks in the file
  int total = 0; // non-cancelled tasks in the file
  int hash = 0; // of the file contents, to skip no-op reloads
  int row = 0; // index in TaskStore.files

  String? _lower;
  String get relPathLower => _lower ??= relPath.toLowerCase();
}

/// A task's identity across reloads.
typedef LineKey = ({String path, int line});
