// Templates: the list (⋮ → Templates), one template's tasks as an ordinary
// task list (its own TaskStore rooted at .templates, as the desktop's
// Templates tab), and the picker used to insert one. Creating, renaming and
// deleting a template file is plain file IO, as on the desktop; edits to its
// tasks go through that store, so they're undoable. Inserting one is a normal,
// undoable edit of the tasks.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/actions.dart';
import '../core/models.dart';
import '../core/parser.dart' as parser;
import '../core/store.dart';
import '../core/task.dart';
import '../core/templates.dart';
import 'add_task.dart';
import 'dialogs.dart';
import 'task_list.dart';
import 'task_sheet.dart';
import 'theme.dart';

/// How many tasks a template file holds.
int templateTaskCount(String dir, String name) {
  try {
    return parser.parse('', '', File(templatePath(dir, name)).readAsStringSync()).tasks.length;
  } on FileSystemException {
    return 0;
  }
}

/// Asks for a template name; checks it's usable and not taken (other than
/// [current]). Null if cancelled or refused (with a message shown).
Future<String?> askTemplateName(BuildContext context, String dir, {String? current}) async {
  final name = (await promptText(
    context,
    title: current == null ? 'New template' : 'Rename template',
    initial: current ?? '',
    hint: 'e.g. Packing list',
    action: current == null ? 'Create' : 'Rename',
  ))?.trim();
  if (name == null || name.isEmpty || name == current || !context.mounted) return null;
  String? problem;
  if (!isValidTemplateName(name)) {
    problem = 'A name can\'t contain "/" or start with "."';
  } else if (File(templatePath(dir, name)).existsSync() && name.toLowerCase() != current?.toLowerCase()) {
    problem = 'There is already a template called "$name"';
  }
  if (problem != null) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(problem!),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    return null;
  }
  return name;
}

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key, required this.dir, required this.onInsert, this.tags = const []});
  final String dir;
  final List<String> tags; // for suggestions while typing

  /// Insert the template into the tasks (todo.md); the page closes first.
  final ValueChanged<String> onInsert;

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  late List<String> _names = templateNames(widget.dir);

  void _reload() => setState(() => _names = templateNames(widget.dir));

  Future<void> _open(String name) async {
    final insert = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => TemplateEditorPage(dir: widget.dir, name: name, tags: widget.tags),
      ),
    );
    _reload();
    if (insert != null && mounted) {
      Navigator.pop(context);
      widget.onInsert(insert);
    }
  }

  Future<void> _create() async {
    final name = await askTemplateName(context, widget.dir);
    if (name == null || !mounted) return;
    if (!saveTemplate(templatePath(widget.dir, name), const [])) return;
    _reload();
    await _open(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      floatingActionButton: FloatingActionButton(
        key: const Key('newTemplate'),
        tooltip: 'New template',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: _names.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No templates yet.\n\nA template is a set of tasks you can insert again and again, '
                  'like a packing list. Tap + to make one, or select tasks and choose '
                  '"Save as template" from the ⋮ menu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.dim),
                ),
              ),
            )
          : ListView(
              children: [
                for (final n in _names)
                  ListTile(
                    key: ValueKey('template-$n'),
                    leading: const Icon(Icons.content_paste_outlined),
                    title: Text(n),
                    subtitle: Text(() {
                      final c = templateTaskCount(widget.dir, n);
                      return '$c task${c == 1 ? '' : 's'}';
                    }()),
                    trailing: IconButton(
                      key: ValueKey('insertTemplate-$n'),
                      tooltip: 'Insert into tasks',
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onInsert(n);
                      },
                    ),
                    onTap: () => _open(n),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  child: Text(
                    'Tap a template to see and change its tasks. They\'re kept in a hidden .templates folder in '
                    '"${widget.dir.split('/').reversed.skip(1).firstOrNull ?? ''}", shared with the desktop app.',
                    style: TextStyle(color: colors.dim, fontSize: 12.5),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One template's tasks, as a task list: tap a task for its sheet, tick and
/// swipe as anywhere, + adds a task, undo/redo. Pops with the template's name
/// when "Insert into tasks" is chosen, else null.
class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({super.key, required this.dir, required this.name, this.tags = const []});
  final String dir;
  final String name;
  final List<String> tags;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  final store = TaskStore()..watching = false;
  late final actions = TaskActions(store, stampCreated: false);
  late String name = widget.name;
  late final FileModel model = FileModel(store, templatePath(widget.dir, name));
  String? _status;
  Timer? _statusTimer;

  String get path => templatePath(widget.dir, name);

  @override
  void initState() {
    super.initState();
    store.onMessage = _say;
    store.addListener(_changed);
    store.setRoots([widget.dir]);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    store.removeListener(_changed);
    model.dispose();
    store.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _say(String text) {
    if (!mounted) return;
    _statusTimer?.cancel();
    setState(() => _status = text);
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _status = null);
    });
  }

  Future<void> _add() async {
    final t = await showAddTask(context, title: 'New task', where: 'in "$name"', tags: widget.tags);
    if (t == null) return;
    actions.append(path, t.text, due: t.due);
  }

  Future<void> _due(Task t) async {
    final choice = await pickDue(context, initial: t.due, count: expand([t]).length);
    if (choice != null) actions.setDue([t], choice.day);
  }

  Future<void> _eta(Task t) async {
    final eta = await pickEta(context, current: t.etaText, count: expand([t]).length);
    if (eta != null) actions.setEta([t], eta);
  }

  Future<void> _addNear(Task anchor, {required bool subtask}) async {
    final t = await showAddTask(
      context,
      title: subtask ? 'New subtask' : 'New task',
      where: subtask ? 'under "${anchor.text}"' : 'after "${anchor.text}"',
      tags: widget.tags,
    );
    if (t == null) return;
    final fresh = store.taskFor(keyOf(anchor));
    if (fresh != null) actions.addAfter(fresh, t.text, subtask: subtask, due: t.due);
  }

  Future<void> _delete(Task t) async {
    final n = expand([t]).length;
    final ok = await confirm(
      context,
      'Delete tasks',
      'Delete $n task line${n == 1 ? '' : 's'} (including subtasks)? You can undo this.',
      action: 'Delete',
    );
    if (ok) actions.delete([t]);
  }

  void _openTask(Task t) {
    final key = keyOf(t);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        void close() => Navigator.pop(sheet);
        Task? fresh() => store.taskFor(key);
        return TaskSheet(
          store: store,
          taskKey: key,
          tags: widget.tags,
          hidden: const {SheetAction.template, SheetAction.open, SheetAction.select},
          onState: (s) {
            close();
            if (fresh() case final t?) actions.setState([t], s);
          },
          onSave: (text) {
            close();
            if (fresh() case final t?) actions.setContent(t, text);
          },
          onAddTag: (tag) {
            if (fresh() case final t?) actions.addTag(t, tag);
          },
          onRemoveTag: (tag) {
            if (fresh() case final t?) actions.removeTag(t, tag);
          },
          onAction: (a) {
            close();
            final t = fresh();
            if (t == null) return;
            switch (a) {
              case SheetAction.due:
                _due(t);
              case SheetAction.eta:
                _eta(t);
              case SheetAction.addBelow:
                _addNear(t, subtask: false);
              case SheetAction.addSubtask:
                _addNear(t, subtask: true);
              case SheetAction.delete:
                _delete(t);
              case SheetAction.template || SheetAction.open || SheetAction.select:
                break;
            }
          },
        );
      },
    );
  }

  Future<void> _rename() async {
    final to = await askTemplateName(context, widget.dir, current: name);
    if (to == null || !mounted) return;
    try {
      // A plain rename, so a case-only change works on case-insensitive storage.
      File(path).renameSync(templatePath(widget.dir, to));
    } on FileSystemException {
      _say('Could not rename to "$to"');
      return;
    }
    setState(() => name = to);
    model.path = path;
    await store.setRoots([widget.dir]);
  }

  Future<void> _deleteTemplate() async {
    final ok = await confirm(
      context,
      'Delete template',
      'Delete "$name"? Your tasks are not touched.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // already gone
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              flex: 3,
              child: GestureDetector(
                key: const Key('templateTitle'),
                onTap: _rename,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(width: 10),
              Flexible(
                flex: 2,
                child: Text(
                  _status!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w400, color: colors.dim),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: store.canUndo ? 'Undo ${store.undoLabel}' : 'Undo',
            onPressed: store.canUndo ? store.undo : null,
            icon: const Icon(Icons.undo),
          ),
          PopupMenuButton<String>(
            key: const Key('templateMenu'),
            onSelected: (v) {
              switch (v) {
                case 'insert':
                  Navigator.pop(context, name);
                case 'rename':
                  _rename();
                case 'delete':
                  _deleteTemplate();
                case 'redo':
                  store.redo();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'insert', child: Text('Insert into tasks')),
              const PopupMenuItem(value: 'rename', child: Text('Rename…')),
              if (store.canRedo) PopupMenuItem(value: 'redo', child: Text('Redo ${store.redoLabel}')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete template')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addTemplateTask'),
        tooltip: 'Add task',
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: store.loading && model.rows.isEmpty
          ? const SizedBox()
          : TaskListView(
              model: model,
              selected: const {},
              allowSelection: false,
              onSelectionChanged: (_) {},
              onTapTask: _openTask,
              onToggle: actions.toggleTask,
              onSwipe: (t, right) => right ? actions.toggleTask(t) : _due(t),
              empty: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No tasks in "$name" yet. Tap + to add one.\n\n'
                    'They\'ll all start as todo when the template is inserted.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.dim),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Which template to insert; [subtasks] is offered when there's a task to put
/// them under. Null if cancelled.
typedef TemplateChoice = ({String name, bool subtasks});

Future<TemplateChoice?> pickTemplate(
  BuildContext context, {
  required String dir,
  String? under, // the task's text, when "as subtasks" can be chosen
}) {
  return showModalBottomSheet<TemplateChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TemplatePicker(dir: dir, under: under),
  );
}

class _TemplatePicker extends StatefulWidget {
  const _TemplatePicker({required this.dir, this.under});
  final String dir;
  final String? under;

  @override
  State<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<_TemplatePicker> {
  late final _names = templateNames(widget.dir);
  bool _subtasks = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Insert template', style: theme.textTheme.titleMedium),
            ),
            if (widget.under != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    Pick(
                      key: const Key('tplBelow'),
                      label: 'Below this task',
                      selected: !_subtasks,
                      onTap: () => setState(() => _subtasks = false),
                    ),
                    Pick(
                      key: const Key('tplSubtasks'),
                      label: 'As its subtasks',
                      selected: _subtasks,
                      onTap: () => setState(() => _subtasks = true),
                    ),
                  ],
                ),
              ),
            if (_names.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'No templates yet. Make one in ⋮ → Templates, or select tasks and choose "Save as template".',
                  style: TextStyle(color: colors.dim),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final n in _names)
                      ListTile(
                        key: ValueKey('pickTemplate-$n'),
                        leading: const Icon(Icons.content_paste_outlined),
                        title: Text(n),
                        subtitle: Text(() {
                          final c = templateTaskCount(widget.dir, n);
                          return '$c task${c == 1 ? '' : 's'}';
                        }()),
                        onTap: () => Navigator.pop(context, (name: n, subtasks: _subtasks)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
