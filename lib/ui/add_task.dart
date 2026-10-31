// Adding a task: a plain sheet with the text and an optional due date.
// Also the due-date row shared with the due picker (quick picks plus an
// inline month grid, instead of Material's date picker).

import 'package:flutter/material.dart';

import '../core/day.dart';
import 'calendar.dart';
import 'tags.dart';
import 'theme.dart';

/// Small bordered toggle; the app's own, not a Material chip.
class Pick extends StatelessWidget {
  const Pick({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.selection : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? theme.colorScheme.primary : colors.guide),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? theme.colorScheme.onSurface : colors.pillText,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Quick due-date picks (None, Today, Tomorrow, next Monday, +1 week,
/// +1 month) and "Pick…" which opens a month grid inline.
class DueRow extends StatefulWidget {
  const DueRow({super.key, required this.value, required this.onChanged, this.allowNone = true});
  final Day? value;
  final ValueChanged<Day?> onChanged;
  final bool allowNone;

  @override
  State<DueRow> createState() => _DueRowState();
}

class _DueRowState extends State<DueRow> {
  bool _grid = false;
  late Day _month = _first(widget.value ?? today());

  static Day _first(Day d) {
    final dt = dateOf(d);
    return dayOf(dt.year, dt.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final now = today();
    final monday = now + (8 - weekdayOf(now));
    final quick = <(String, Day)>[
      ('Today', now),
      ('Tomorrow', now + 1),
      ('Mon ${dateOf(monday).day}', monday),
      ('+1 week', now + 7),
      ('+1 month', addMonths(now, 1)),
    ];
    final v = widget.value;
    final custom = v != null && !quick.any((q) => q.$2 == v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (widget.allowNone) Pick(label: 'None', selected: v == null, onTap: () => widget.onChanged(null)),
            for (final (label, day) in quick)
              Pick(key: ValueKey('due-$label'), label: label, selected: v == day, onTap: () => widget.onChanged(day)),
            Pick(
              key: const ValueKey('due-pick'),
              label: custom ? isoDay(v) : 'Pick…',
              selected: custom || _grid,
              onTap: () => setState(() => _grid = !_grid),
            ),
          ],
        ),
        if (_grid)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MonthView(
              month: _month,
              selected: v ?? -1,
              onSelect: (d) {
                setState(() {
                  _grid = false;
                  _month = _first(d);
                });
                widget.onChanged(d);
              },
              onMonth: (m) => setState(() => _month = m),
            ),
          ),
      ],
    );
  }
}

typedef NewTask = ({String text, Day? due});

/// Returns null if cancelled. [context] says where it goes ("todo.md",
/// "under …").
Future<NewTask?> showAddTask(
  BuildContext context, {
  required String title,
  required String where,
  Day? due,
  List<String> tags = const [],
}) {
  return showModalBottomSheet<NewTask>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddTaskSheet(title: title, where: where, due: due, tags: tags),
  );
}

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({required this.title, required this.where, this.due, this.tags = const []});
  final String title, where;
  final List<String> tags;
  final Day? due;

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _text = TextEditingController();
  late Day? _due = widget.due;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_text.text.trim().isEmpty) return;
    Navigator.pop(context, (text: _text.text.trim(), due: _due));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(widget.title, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.where,
                      style: TextStyle(color: colors.dim, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('addText'),
                controller: _text,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: 'What needs doing?  (~15m, #tag)'),
                onSubmitted: (_) => _submit(),
              ),
              TagSuggestions(controller: _text, tags: widget.tags),
              const SizedBox(height: 14),
              Text('Due', style: TextStyle(color: colors.dim, fontSize: 12.5)),
              const SizedBox(height: 6),
              DueRow(value: _due, onChanged: (d) => setState(() => _due = d)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  ListenableBuilder(
                    listenable: _text,
                    builder: (_, _) => FilledButton(
                      key: const Key('addSubmit'),
                      onPressed: _text.text.trim().isEmpty ? null : _submit,
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
