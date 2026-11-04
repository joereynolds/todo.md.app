// Owns every parsed file under the root directories, keeps them in sync with
// disk and is the only thing that writes to disk. Mirrors src/store.cpp.
//
// Several roots can be tracked; a file under more than one is held once.
// Every mutation ends in notifyListeners(); Task objects from before a change
// must not be used after it (look them up again by path + line). Files are
// sorted by relPath and only files with at least one task are held.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'edits.dart';
import 'parser.dart' as parser;
import 'task.dart';

const _maxUndo = 200;
const _maxWatchedDirs = 4000; // inotify watches are a shared, limited resource

bool isMarkdown(String name) {
  final l = name.toLowerCase();
  return l.endsWith('.md') || l.endsWith('.markdown');
}

bool isIgnoredDir(String name) => name.startsWith('.') || name == 'node_modules';

String _baseName(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

String normalizeRoot(String dir) {
  var d = Directory(dir).absolute.path.replaceAll('\\', '/');
  final parts = <String>[];
  for (final p in d.split('/')) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(p);
  }
  d = '/${parts.join('/')}';
  return d;
}

/// Display path: relative to its innermost root, prefixed with the root's
/// name when there are several roots.
String relPathFor(String path, List<String> roots) {
  String? best;
  for (final r in roots) {
    final rr = r == '/' ? '' : r;
    if (path.length > rr.length &&
        path.startsWith(rr) &&
        path.codeUnitAt(rr.length) == 0x2f &&
        (best == null || r.length > best.length)) {
      best = r;
    }
  }
  if (best == null) return path;
  final rel = path.substring(best == '/' ? 1 : best.length + 1);
  if (roots.length == 1) return rel;
  final name = _baseName(best);
  return '${name.isEmpty ? best : name}/$rel';
}

int comparePaths(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
}

String readText(String path) => utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);

TaskFile? parseFile(String path, String relPath) {
  try {
    return parser.parse(path, relPath, readText(path));
  } on FileSystemException {
    return null;
  }
}

typedef FileStat = ({int mtime, int size});

class _Scan {
  _Scan(this.files, this.dirs);
  final Map<String, FileStat> files; // every markdown file
  final List<String> dirs;
}

_Scan _scanTree(List<String> roots) {
  final files = <String, FileStat>{};
  final dirs = <String>[];
  final seenDirs = <String>{};
  void walk(String dir) {
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      final path = e.path;
      final name = _baseName(path);
      if (e is Directory) {
        if (isIgnoredDir(name) || seenDirs.contains(path)) continue;
        seenDirs.add(path);
        dirs.add(path);
        walk(path);
      } else if (e is File && isMarkdown(name) && !files.containsKey(path)) {
        try {
          final st = e.statSync();
          files[path] = (mtime: st.modified.microsecondsSinceEpoch, size: st.size);
        } on FileSystemException {
          // vanished while scanning
        }
      }
    }
  }

  for (final r in roots) {
    if (seenDirs.contains(r)) continue; // nested inside an earlier root
    seenDirs.add(r);
    dirs.add(r);
    walk(r);
  }
  return _Scan(files, dirs);
}

List<TaskFile> _parseChunk(List<String> paths, List<String> roots) {
  final out = <TaskFile>[];
  for (final p in paths) {
    final f = parseFile(p, relPathFor(p, roots));
    if (f != null && f.tasks.isNotEmpty) out.add(f);
  }
  return out;
}

// Separate functions so the isolate closures capture nothing but their
// arguments (a closure shares its context with its siblings in the enclosing
// function, which could drag the store itself along).
Future<List<TaskFile>> _parseInIsolate(List<String> paths, List<String> roots) =>
    Isolate.run(() => _parseChunk(paths, roots));

Future<_Scan> _scanInIsolate(List<String> roots) => Isolate.run(() => _scanTree(roots));

/// Parses in parallel isolates; results come back by Isolate.exit (no copy).
Future<List<TaskFile>> _parseAll(List<String> paths, List<String> roots) async {
  if (paths.isEmpty) return [];
  if (paths.length < 64) return _parseChunk(paths, roots);
  final workers = math.min(math.max(1, Platform.numberOfProcessors), 8);
  final per = (paths.length / workers).ceil();
  final chunks = [for (var i = 0; i < paths.length; i += per) paths.sublist(i, math.min(i + per, paths.length))];
  final results = await Future.wait([for (final c in chunks) _parseInIsolate(c, roots)]);
  return [for (final r in results) ...r];
}

class _Step {
  _Step(this.label, this.edits);
  final String label;
  final List<Edit> edits; // applying these performs the step
}

class _Outcome {
  int applied = 0, conflicts = 0;
  final List<String> errors = [];
  final List<Edit> inverse = [];
}

class LoadStats {
  const LoadStats(this.files, this.tasks, this.ms);
  final int files, tasks, ms;
}

class TaskStore extends ChangeNotifier {
  List<String> _roots = [];
  List<TaskFile> _files = [];
  final Map<String, TaskFile> _byPath = {};
  Map<String, FileStat> _known = {}; // every markdown file seen, with or without tasks
  Set<String> _dirs = {};
  final Map<String, StreamSubscription<FileSystemEvent>> _watches = {};
  final Set<String> _pending = {}, _pendingDirs = {};
  Timer? _flushTimer;
  int _generation = 0;
  bool _loading = false;
  bool _watching = true;
  final List<_Step> _undo = [], _redo = [];
  LoadStats? lastLoad;

  /// Status messages (conflicts, write errors, undo labels).
  void Function(String message)? onMessage;

  List<String> get roots => List.unmodifiable(_roots);
  List<TaskFile> get files => _files;
  bool get loading => _loading;
  TaskFile? fileByPath(String path) => _byPath[path];

  Task? taskAt(String path, int line) {
    final f = _byPath[path];
    if (f == null) return null;
    var lo = 0, hi = f.tasks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (f.tasks[mid].line < line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < f.tasks.length && f.tasks[lo].line == line ? f.tasks[lo] : null;
  }

  Task? taskFor(LineKey k) => taskAt(k.path, k.line);

  int get taskCount {
    var n = 0;
    for (final f in _files) {
      n += f.tasks.length;
    }
    return n;
  }

  /// Every tag in use, case-insensitively merged (shown as first written),
  /// with how many open and how many tasks in all carry it. Sorted by name.
  List<TagCount> tags() {
    final byKey = <String, TagCount>{};
    for (final f in _files) {
      for (final t in f.tasks) {
        if (t.tags.isEmpty) continue;
        for (final tag in t.tags) {
          final c = byKey.putIfAbsent(tag.toLowerCase(), () => TagCount(tag));
          c.total++;
          if (t.isOpen) c.open++;
        }
      }
    }
    return byKey.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void dispose() {
    _stopWatching();
    _flushTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ loading

  /// Full asynchronous load of [roots].
  Future<void> setRoots(List<String> roots) async {
    final normalized = <String>[];
    for (final r in roots) {
      final n = normalizeRoot(r);
      if (!normalized.contains(n)) normalized.add(n);
    }
    _roots = normalized;
    final gen = ++_generation;
    _loading = true;
    _pending.clear();
    _pendingDirs.clear();
    _stopWatching();
    notifyListeners();

    final sw = Stopwatch()..start();
    final scan = await _scanInIsolate(normalized);
    if (gen != _generation) return;
    final parsed = await _parseAll(scan.files.keys.toList(), normalized);
    if (gen != _generation) return; // superseded by a newer setRoots()

    parsed.sort((a, b) => comparePaths(a.relPath, b.relPath));
    _files = parsed;
    _byPath
      ..clear()
      ..addEntries(parsed.map((f) => MapEntry(f.path, f)));
    _renumber();
    _known = scan.files;
    _dirs = scan.dirs.toSet();
    _loading = false;
    lastLoad = LoadStats(_files.length, taskCount, sw.elapsedMilliseconds);
    if (_watching) _startWatching();
    notifyListeners();
  }

  Future<void> reload() => setRoots(_roots);

  /// Incremental: re-reads only files whose mtime or size changed, picks up
  /// new and removed files. Used on app resume.
  Future<void> refresh() async {
    if (_loading || _roots.isEmpty) return;
    final gen = _generation;
    final roots = _roots;
    final scan = await _scanInIsolate(roots);
    if (gen != _generation || _loading) return;
    final changed = <String>[];
    scan.files.forEach((path, st) {
      if (_known[path] != st) changed.add(path);
    });
    final removed = [
      for (final p in _known.keys)
        if (!scan.files.containsKey(p)) p,
    ];
    final parsed = await _parseAll(changed, roots);
    if (gen != _generation || _loading) return;
    var touched = false;
    final fresh = {for (final f in parsed) f.path: f};
    for (final p in changed) {
      touched |= _replace(p, fresh[p]);
    }
    for (final p in removed) {
      touched |= _replace(p, null);
    }
    _known = scan.files;
    final newDirs = scan.dirs.toSet();
    final dirsChanged = newDirs.length != _dirs.length || !newDirs.containsAll(_dirs);
    _dirs = newDirs;
    if (dirsChanged && _watching) _startWatching();
    if (touched) notifyListeners();
  }

  void _renumber() {
    for (var i = 0; i < _files.length; i++) {
      _files[i].row = i;
    }
  }

  /// Swaps in [fresh] (null = no tasks / gone) for [path]. Returns whether
  /// anything changed. Does not notify.
  bool _replace(String path, TaskFile? fresh) {
    if (fresh != null && fresh.tasks.isEmpty) fresh = null;
    final old = _byPath[path];
    if (old == null && fresh == null) return false;
    if (old != null && fresh != null && old.hash == fresh.hash) return false;
    if (old != null) {
      _files.removeAt(old.row);
      _byPath.remove(path);
    }
    if (fresh != null) {
      var lo = 0, hi = _files.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (comparePaths(_files[mid].relPath, fresh.relPath) < 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      _files.insert(lo, fresh);
      _byPath[path] = fresh;
    }
    _renumber();
    return true;
  }

  bool _reloadFile(String path) {
    TaskFile? fresh;
    final f = File(path);
    if (f.existsSync()) {
      fresh = parseFile(path, relPathFor(path, _roots));
      try {
        final st = f.statSync();
        _known[path] = (mtime: st.modified.microsecondsSinceEpoch, size: st.size);
      } on FileSystemException {
        _known.remove(path);
      }
    } else {
      _known.remove(path);
    }
    return _replace(path, fresh);
  }

  // ------------------------------------------------------------ watching
  // Dart can't watch recursively on Linux/Android, so (like the desktop app)
  // every directory gets its own watch. Changes are debounced and re-parsed
  // per file; unchanged content is skipped by hash.

  /// Stop watching (app in background) or start again (resumed: also catches
  /// up with whatever changed meanwhile).
  set watching(bool on) {
    if (on == _watching) return;
    _watching = on;
    if (on) {
      _startWatching();
      refresh();
    } else {
      _stopWatching();
    }
  }

  void _startWatching() {
    _stopWatching();
    for (final d in _dirs.take(_maxWatchedDirs)) {
      _watch(d);
    }
  }

  void _watch(String dir) {
    if (_watches.containsKey(dir) || _watches.length >= _maxWatchedDirs) return;
    try {
      _watches[dir] = Directory(dir).watch().listen(_onEvent, onError: (_) => _unwatch(dir));
    } on FileSystemException {
      // not watchable (permissions, platform): refresh() still catches up
    }
  }

  void _unwatch(String dir) => _watches.remove(dir)?.cancel();

  void _stopWatching() {
    for (final s in _watches.values) {
      s.cancel();
    }
    _watches.clear();
  }

  void _onEvent(FileSystemEvent e) {
    final name = _baseName(e.path);
    if (e.isDirectory) {
      if (!isIgnoredDir(name)) _pendingDirs.add(e.path);
    } else if (isMarkdown(name)) {
      _pending.add(e.path);
    } else if (e.type == FileSystemEvent.delete || e.type == FileSystemEvent.move) {
      _pendingDirs.add(e.path); // could have been a directory
    } else {
      return;
    }
    if (e is FileSystemMoveEvent && e.destination != null) {
      final dest = e.destination!;
      if (isMarkdown(_baseName(dest))) {
        _pending.add(dest);
      } else {
        _pendingDirs.add(dest);
      }
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 120), _flush);
  }

  void _flush() {
    if (_loading) {
      _flushTimer = Timer(const Duration(milliseconds: 120), _flush);
      return;
    }
    var touched = false;
    final dirs = _pendingDirs.toList();
    final files = _pending.toList();
    _pendingDirs.clear();
    _pending.clear();
    for (final d in dirs) {
      touched |= _rescanDir(d);
    }
    for (final f in files) {
      touched |= _reloadFile(f);
    }
    if (touched) notifyListeners();
  }

  bool _rescanDir(String dir) {
    var touched = false;
    final prefix = '$dir/';
    if (!Directory(dir).existsSync()) {
      if (!_dirs.contains(dir)) return false;
      // Removed: drop everything beneath it.
      _dirs.removeWhere((d) => d == dir || d.startsWith(prefix));
      for (final d in _watches.keys.where((d) => d == dir || d.startsWith(prefix)).toList()) {
        _unwatch(d);
      }
      for (final f in _known.keys.where((f) => f.startsWith(prefix)).toList()) {
        touched |= _reloadFile(f);
      }
      return touched;
    }
    if (_dirs.contains(dir)) return false;
    final scan = _scanTree([dir]);
    for (final d in scan.dirs) {
      _dirs.add(d);
      _watch(d);
    }
    for (final f in scan.files.keys) {
      touched |= _reloadFile(f);
    }
    return touched;
  }

  // ------------------------------------------------------------ writing

  _Outcome _applyRaw(List<Edit> edits) {
    final byFile = <String, List<Edit>>{};
    for (final e in edits) {
      (byFile[e.path] ??= []).add(e);
    }
    final out = _Outcome();
    byFile.forEach((path, fileEdits) {
      final LineBuffer buf;
      try {
        buf = LineBuffer.fromString(readText(path));
      } on FileSystemException {
        out.errors.add(path);
        return;
      }
      final r = applyEdits(buf, fileEdits);
      out.conflicts += r.conflicts;
      if (r.applied > 0) {
        try {
          _atomicWrite(path, buf.toString());
          out.applied += r.applied;
          out.inverse.addAll(r.inverse);
        } on FileSystemException {
          out.errors.add(path);
        }
      }
      _reloadFile(path);
    });
    return out;
  }

  /// Creates an empty markdown file (and its folders) if it doesn't exist,
  /// so tasks can be appended to it.
  void createFile(String path) {
    final f = File(path);
    if (!f.existsSync()) f.createSync(recursive: true);
  }

  static void _atomicWrite(String path, String data) {
    final slash = path.lastIndexOf('/');
    // Hidden name, so neither this app nor sync tools pick up the temp file.
    final tmp = '${path.substring(0, slash + 1)}.${path.substring(slash + 1)}.todomd~';
    final f = File(tmp);
    try {
      f.writeAsBytesSync(utf8.encode(data), flush: true);
      f.renameSync(path);
    } on FileSystemException {
      // Some storage providers refuse rename-over; fall back to an in-place write.
      if (f.existsSync()) f.deleteSync();
      File(path).writeAsBytesSync(utf8.encode(data), flush: true);
    }
  }

  void _report(_Outcome o, String label) {
    final parts = <String>[];
    if (o.conflicts > 0) {
      parts.add('${o.conflicts} line${o.conflicts == 1 ? '' : 's'} changed on disk and were skipped');
    }
    if (o.errors.isNotEmpty) parts.add('could not write ${o.errors.join(', ')}');
    if (parts.isNotEmpty) onMessage?.call('$label: ${parts.join('; ')}');
  }

  /// Writes edits to disk, reloads the touched files and records an undo
  /// step. Returns the number of edits applied.
  int apply(List<Edit> edits, String label) {
    if (edits.isEmpty) return 0;
    final o = _applyRaw(edits);
    _report(o, label);
    if (o.applied > 0) {
      _undo.add(_Step(label, o.inverse));
      if (_undo.length > _maxUndo) _undo.removeAt(0);
      _redo.clear();
    }
    notifyListeners();
    return o.applied;
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  void undo() {
    if (_undo.isEmpty) return;
    final step = _undo.removeLast();
    final o = _applyRaw(step.edits);
    onMessage?.call('Undid: ${step.label}');
    _report(o, 'Undo ${step.label}');
    if (o.applied > 0) _redo.add(_Step(step.label, o.inverse));
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final step = _redo.removeLast();
    final o = _applyRaw(step.edits);
    onMessage?.call('Redid: ${step.label}');
    _report(o, 'Redo ${step.label}');
    if (o.applied > 0) _undo.add(_Step(step.label, o.inverse));
    notifyListeners();
  }

  @visibleForTesting
  int get watchCount => _watches.length;
}

class TagCount {
  TagCount(this.name);
  final String name;
  int open = 0, total = 0;
}
