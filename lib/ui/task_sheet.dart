// Tapping a task opens this sheet: edit the text, set the state, due date,
// ETA, tags, add a task or subtask, open the file, delete. Actions on a parent
// include its subtasks, as everywhere else (tags excepted: they're per task).
// It follows the store, so adding or removing a tag updates it in place.

import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/store.dart';
import '../core/task.dart';
import 'tags.dart';
import 'theme.dart';

enum SheetAction { due, eta, addBelow, addSubtask, open, delete, select }

class TaskSheet extends StatefulWidget {
  const TaskSheet({
    super.key,
    required this.store,
    required this.taskKey,
    required this.onState,
    required this.onSave,
    required this.onAction,
    this.tags = const [],
    this.onTag,
    this.onAddTag,
    this.onRemoveTag,
  });

  final TaskStore store;
  final LineKey taskKey;
  final List<String> tags; // every tag in use, for suggestions
  final ValueChanged<TaskState> onState;
  final ValueChanged<String> onSave;
  final ValueChanged<SheetAction> onAction;
  final ValueChanged<String>? onTag; // show everything with this tag
  final ValueChanged<String>? onAddTag, onRemoveTag; // these keep the sheet open

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late Task _task = widget.store.taskFor(widget.taskKey)!;
  late final TextEditingController _text = TextEditingController(text: _task.content);
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _text.dispose();
    super.dispose();
  }

  void _onStore() {
    final t = widget.store.taskFor(widget.taskKey);
    if (t == null) {
      Navigator.maybePop(context); // gone (deleted elsewhere)
      return;
    }
    setState(() {
      if (!_dirty && t.content != _text.text) _text.text = t.content;
      _task = t;
    });
  }

  Future<void> _addTag() async {
    final tag = await pickTag(context, tags: widget.tags, exclude: {for (final t in _task.tags) t.toLowerCase()});
    if (tag != null) widget.onAddTag?.call(tag);
  }

  void _save() {
    if (_dirty) widget.onSave(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    final theme = Theme.of(context);
    final colors = context.colors;
    final subs = t.children.isEmpty ? '' : ' (and ${t.subTotal} subtask${t.subTotal == 1 ? '' : 's'})';
    Widget action(IconData icon, String label, SheetAction a, {String? detail, Color? color}) => ListTile(
      key: ValueKey('sheet-${a.name}'),
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      subtitle: detail == null ? null : Text(detail),
      onTap: () => widget.onAction(a),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  '${t.file.relPath}:${t.line + 1}',
                  style: theme.textTheme.bodySmall!.copyWith(color: colors.dim),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  key: const Key('sheetText'),
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (v) {
                    final d = v != t.content;
                    if (d != _dirty) setState(() => _dirty = d);
                  },
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: 'Task text  (!2026-12-25  ~15m  #tag …)',
                    suffixIcon: _dirty
                        ? IconButton(tooltip: 'Save', icon: const Icon(Icons.check), onPressed: _save)
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TagSuggestions(controller: _text, tags: widget.tags),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in t.tags)
                      TagPill(
                        tag: tag,
                        onTap: () => widget.onTag?.call(tag),
                        onRemove: widget.onRemoveTag == null || _dirty ? null : () => widget.onRemoveTag!(tag),
                      ),
                    if (widget.onAddTag != null && !_dirty)
                      GestureDetector(
                        key: const Key('addTag'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _addTag,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(colors.radius),
                            border: Border.all(color: colors.guide),
                          ),
                          child: Text('+ Tag', style: TextStyle(fontSize: 13, color: colors.pillText)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: SegmentedButton<TaskState>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TaskState.todo, label: Text('Todo')),
                    ButtonSegment(value: TaskState.doing, label: Text('Doing')),
                    ButtonSegment(value: TaskState.done, label: Text('Done')),
                    ButtonSegment(value: TaskState.cancelled, label: Text('Cancel')),
                  ],
                  selected: {t.state},
                  onSelectionChanged: (s) => widget.onState(s.first),
                ),
              ),
              if (subs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Applies to this task$subs', style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 4),
              action(Icons.event, 'Due date', SheetAction.due, detail: t.due == null ? 'None' : isoDay(t.due!)),
              action(Icons.timer_outlined, 'ETA', SheetAction.eta, detail: t.eta > 0 ? '~${t.etaText}' : 'None'),
              action(Icons.add, 'Add task below', SheetAction.addBelow),
              action(Icons.subdirectory_arrow_right, 'Add subtask', SheetAction.addSubtask),
              action(Icons.checklist, 'Select', SheetAction.select, detail: 'Then tap or drag to select more'),
              action(Icons.open_in_new, 'Open file', SheetAction.open),
              action(Icons.delete_outline, 'Delete', SheetAction.delete, color: colors.overdue),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
