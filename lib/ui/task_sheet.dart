// Tapping a task opens this sheet: edit the text, set the state, due date,
// ETA, add a task or subtask, open the file, delete. Actions on a parent
// include its subtasks, as everywhere else.

import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/store.dart';
import '../core/task.dart';
import 'theme.dart';

enum SheetAction { due, eta, addBelow, addSubtask, open, delete, select }

class TaskSheet extends StatefulWidget {
  const TaskSheet({super.key, required this.task, required this.onState, required this.onSave, required this.onAction, this.onTag});

  final Task task;
  final ValueChanged<TaskState> onState;
  final ValueChanged<String> onSave;
  final ValueChanged<SheetAction> onAction;
  final ValueChanged<String>? onTag; // show everything with this tag

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.task.content);
  bool _dirty = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_dirty) widget.onSave(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
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
              if (t.tags.isNotEmpty && widget.onTag != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final tag in t.tags) TagPill(tag: tag, onTap: () => widget.onTag!(tag))],
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

/// A tag as a tappable outlined pill ("#office").
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.tag, required this.onTap, this.selected = false, this.trailing});
  final String tag;
  final VoidCallback onTap;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      key: ValueKey('pill-$tag'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.selection : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? colors.tag : colors.guide),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '#$tag',
                style: TextStyle(color: colors.tag, fontWeight: FontWeight.w600),
              ),
              if (trailing != null)
                TextSpan(
                  text: '  $trailing',
                  style: TextStyle(color: colors.dim),
                ),
            ],
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

/// Every tag in use, to filter by one. Pops with the tag, or '' to clear the
/// filter.
class TagSheet extends StatelessWidget {
  const TagSheet({super.key, required this.tags, this.active});
  final List<TagCount> tags;
  final String? active; // "#office", lower case

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
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(child: Text('Tags', style: theme.textTheme.titleMedium)),
                  if (active != null)
                    TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Clear filter')),
                ],
              ),
            ),
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'No tags yet. Add one anywhere in a task, like  #office',
                  style: TextStyle(color: colors.dim),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in tags)
                        TagPill(
                          tag: t.name,
                          trailing: '${t.open}', // open tasks
                          selected: active == '#${t.name.toLowerCase()}',
                          onTap: () => Navigator.pop(context, t.name),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
