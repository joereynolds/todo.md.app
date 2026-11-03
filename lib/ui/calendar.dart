// The desktop sidebar as a tab, same order (requested by the user):
// calendar (dots under days with open due tasks), the selected day's tasks,
// then the filter tiles.

import 'package:flutter/material.dart';

import '../core/day.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/task.dart';
import 'task_list.dart';
import 'theme.dart';

class Stats {
  int overdue = 0, dueToday = 0, week = 0, doing = 0, quick = 0, doneToday = 0;
  final Map<Day, int> counts = {}; // open tasks due per day

  static Stats of(TaskStore store) {
    final s = Stats();
    final now = today();
    for (final f in store.files) {
      for (final t in f.tasks) {
        if (t.state == TaskState.done && t.completed == now) s.doneToday++;
        if (!t.isOpen) continue;
        if (t.state == TaskState.doing) s.doing++;
        if (t.eta > 0 && t.eta <= 2) s.quick++;
        final due = t.due;
        if (due == null) continue;
        s.counts[due] = (s.counts[due] ?? 0) + 1;
        if (due < now) {
          s.overdue++;
        } else if (due == now) {
          s.dueToday++;
        }
        if (due >= now && due < now + 7) s.week++;
      }
    }
    return s;
  }
}

const statTiles = [
  ('overdue', 'due:overdue'),
  ('due today', 'due:today'),
  ('next 7 days', 'due:week'),
  ('in progress', 'is:doing'),
  ('quick (≤ 2m)', '~<=2m is:open'),
  ('done today', ''),
];

class CalendarPane extends StatefulWidget {
  const CalendarPane({
    super.key,
    required this.store,
    required this.dayModel,
    required this.filterText,
    required this.onFilter,
    required this.onReveal,
    required this.onToggle,
    required this.onSwipe,
    this.onTag,
  });

  final TaskStore store;
  final AgendaModel dayModel;
  final String filterText;
  final ValueChanged<String> onFilter;
  final ValueChanged<Task> onReveal;
  final ValueChanged<Task> onToggle;
  final void Function(Task, bool right) onSwipe;
  final ValueChanged<String>? onTag;

  @override
  State<CalendarPane> createState() => _CalendarPaneState();
}

class _CalendarPaneState extends State<CalendarPane> {
  late Day _month = _firstOfMonth(widget.dayModel.singleDay ?? today());
  bool _weekOnly = false; // folded to the selected day's week, for small screens

  static Day _firstOfMonth(Day d) {
    final dt = dateOf(d);
    return dayOf(dt.year, dt.month, 1);
  }

  void _select(Day d) {
    setState(() {
      widget.dayModel.singleDay = d;
      _month = _firstOfMonth(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final stats = Stats.of(widget.store);
        return Column(
          children: [
            MonthView(
              month: _month,
              selected: widget.dayModel.singleDay ?? today(),
              counts: stats.counts,
              onSelect: _select,
              onMonth: (m) => setState(() => _month = m),
              weekOnly: _weekOnly,
              onToggleWeek: () => setState(() => _weekOnly = !_weekOnly),
            ),
            const Divider(),
            Expanded(
              child: TaskListView(
                model: widget.dayModel,
                selected: const {},
                allowSelection: false,
                onSelectionChanged: (_) {},
                onTapTask: widget.onReveal,
                onToggle: widget.onToggle,
                onSwipe: widget.onSwipe,
                onTag: widget.onTag,
              ),
            ),
            const Divider(),
            _Tiles(stats: stats, active: widget.filterText.trim(), onFilter: widget.onFilter),
          ],
        );
      },
    );
  }
}

class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.month,
    required this.selected,
    this.counts = const {},
    required this.onSelect,
    required this.onMonth,
    this.weekOnly = false,
    this.onToggleWeek,
  });

  final bool weekOnly;
  final VoidCallback? onToggleWeek; // null: no fold button
  final Day month; // first of the month
  final Day selected;
  final Map<Day, int> counts;
  final ValueChanged<Day> onSelect;
  final ValueChanged<Day> onMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final now = today();
    final m = dateOf(weekOnly ? selected : month);
    // Monday on or before the 1st (or of the selected week when folded).
    final start = weekOnly ? selected - (weekdayOf(selected) - 1) : month - (weekdayOf(month) - 1);
    final title = '${monthNames[m.month - 1]} ${m.year}';

    Widget cell(Day d) {
      final inMonth = weekOnly || dateOf(d).month == m.month;
      final isSel = d == selected;
      final isToday = d == now;
      final n = counts[d] ?? 0;
      final dot = d < now ? colors.overdue : (isToday ? colors.today : colors.checkBorder);
      final textColor = isSel
          ? theme.colorScheme.onPrimary
          : !inMonth
          ? colors.dim.withValues(alpha: 0.6)
          : theme.colorScheme.onSurface;
      return InkWell(
        key: ValueKey('day-${isoDay(d)}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelect(d),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSel ? theme.colorScheme.primary : null,
                border: isToday && !isSel ? Border.all(color: colors.today, width: 1.5) : null,
              ),
              child: Text(
                '${dateOf(d).day}',
                style: TextStyle(
                  fontSize: 13.5,
                  color: textColor,
                  fontWeight: isToday || isSel ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < (n > 3 ? 3 : n); i++)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      // Swipe left/right for the next/previous month.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 200) return;
        if (weekOnly) {
          onSelect(selected + (v < 0 ? 7 : -7));
        } else {
          onMonth(addMonths(month, v < 0 ? 1 : -1));
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: weekOnly ? 'Previous week' : 'Previous month',
                  onPressed: () => weekOnly ? onSelect(selected - 7) : onMonth(addMonths(month, -1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: weekOnly ? 'Next week' : 'Next month',
                  onPressed: () => weekOnly ? onSelect(selected + 7) : onMonth(addMonths(month, 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
                if (onToggleWeek != null)
                  IconButton(
                    tooltip: weekOnly ? 'Show the month' : 'Show one week',
                    onPressed: onToggleWeek,
                    icon: Icon(weekOnly ? Icons.unfold_more : Icons.unfold_less),
                  ),
                TextButton(onPressed: () => onSelect(now), child: const Text('Today')),
              ],
            ),
            Row(
              children: [
                for (final w in weekdayNames)
                  Expanded(
                    child: Center(
                      child: Text(w.substring(0, 2), style: TextStyle(fontSize: 11.5, color: colors.dim)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            for (var week = 0; week < (weekOnly ? 1 : 6); week++)
              SizedBox(
                height: 38,
                child: Row(children: [for (var i = 0; i < 7; i++) Expanded(child: cell(start + week * 7 + i))]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact, deliberately neutral one-line tiles; tap sets the filter, tap
/// again clears it. The active one is outlined.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats, required this.active, required this.onFilter});
  final Stats stats;
  final String active;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final values = [stats.overdue, stats.dueToday, stats.week, stats.doing, stats.quick, stats.doneToday];
    Widget tile(int i) {
      final (label, filter) = statTiles[i];
      final on = filter.isNotEmpty && active == filter;
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: on ? colors.pill : colors.band,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(colors.radius + 2),
            side: on ? BorderSide(color: colors.checkBorder) : BorderSide.none,
          ),
          child: InkWell(
            key: ValueKey('tile-$label'),
            borderRadius: BorderRadius.circular(colors.radius + 2),
            // Nothing to show at 0, unless it's the active filter (tap clears it).
            onTap: filter.isEmpty || (values[i] == 0 && !on) ? null : () => onFilter(on ? '' : filter),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${values[i]}',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: values[i] == 0 ? colors.dim : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 12, color: colors.pillText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 4, 5, 6),
        child: Column(
          children: [
            for (var r = 0; r < 2; r++) Row(children: [for (var c = 0; c < 3; c++) Expanded(child: tile(r * 3 + c))]),
          ],
        ),
      ),
    );
  }
}
