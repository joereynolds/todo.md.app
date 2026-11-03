// List templates: reusable sets of tasks, kept as markdown files in a hidden
// ".templates" directory inside a root (hidden directories aren't scanned, so
// template tasks never show up as real tasks). Inserting a template copies its
// tasks in as new todo tasks. Mirrors src/templates.cpp; same files, so the
// desktop and the phone share them.

import 'dart:io';

import 'day.dart';
import 'parser.dart' as parser;
import 'task.dart';

/// ".templates" in the first root that has one, else in the first root; null
/// when there are no roots. The directory may not exist yet.
String? templatesDir(List<String> roots) {
  for (final r in roots) {
    if (Directory('$r/.templates').existsSync()) return '$r/.templates';
  }
  return roots.isEmpty ? null : '${roots.first}/.templates';
}

/// File names without ".md", sorted case-insensitively.
List<String> templateNames(String? dir) {
  if (dir == null || !Directory(dir).existsSync()) return [];
  final out = [
    for (final e in Directory(dir).listSync())
      if (e is File && e.path.endsWith('.md')) e.uri.pathSegments.last.replaceFirst(RegExp(r'\.md$'), ''),
  ]..removeWhere((n) => n.isEmpty || n.startsWith('.'));
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

String templatePath(String dir, String name) => '$dir/$name.md';

/// Usable as a file name: not empty, no '/' or '\', doesn't start with '.'.
bool isValidTemplateName(String name) =>
    name.trim().isNotEmpty && !name.startsWith('.') && !name.contains('/') && !name.contains('\\');

/// Template lines for [tasks] (in display order, subtasks included as wanted):
/// state reset to todo, dates removed (ETAs and tags kept), indented two
/// spaces per ancestor that is also in the list.
List<String> templateFromTasks(List<Task> tasks) {
  final inList = tasks.toSet();
  return [
    for (final t in tasks)
      () {
        var level = 0;
        for (var a = t.parent; a != null; a = a.parent) {
          if (inList.contains(a)) level++;
        }
        var line = parser.setState(t.raw, TaskState.todo, today());
        line = parser.removeDates(line, '!+x-');
        return '${'  ' * level}${line.substring(parser.leadingWhitespace(line).length)}';
      }(),
  ];
}

/// The task lines of a template file, ready to insert: todo, created [today]
/// (other dates in the file are dropped, except a hand-written !due), each
/// indented [lead] + [unit] per nesting level. Non-task lines are dropped.
List<String> instantiateTemplate(String data, {required String lead, required String unit, required Day today}) {
  final file = parser.parse('', '', data);
  return [
    for (final t in file.tasks)
      () {
        var line = parser.setState(t.raw, TaskState.todo, today);
        line = parser.removeDates(line, '+x-'); // created today, whatever the file says
        line = lead + unit * t.depth + line.substring(parser.leadingWhitespace(line).length);
        return parser.setCreated(line, today);
      }(),
  ];
}

/// Writes a template (creating the directory). False on failure.
bool saveTemplate(String path, List<String> lines) {
  try {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync('${lines.join('\n')}\n');
    return true;
  } on FileSystemException {
    return false;
  }
}
