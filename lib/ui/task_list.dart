// The flat tree list shared by the Tasks tab, the Agenda and the calendar's
// day list. Fixed row extent, so 200k rows scroll and jump in O(1).
//
// Gestures:
//   tap row          open the task sheet (or toggle selection while selecting)
//   tap checkbox     done <-> todo, with subtasks
//   tap chevron      collapse / expand (tap on a header does the same)
//   (no swipes on rows: horizontal swipes switch views, see ViewSwiper)
//   long press       start selecting; keep the finger down and drag to select
//                    a range (auto-scrolls at the edges), like a photo gallery

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../core/models.dart';
import '../core/task.dart';
import 'theme.dart';

const double rowExtent = 48;
const double _indentStep = 16;
const double _chevronWidth = 22;
const double _checkWidth = 30;
const double _leftPad = 0;

LineKey keyOf(Task t) => (path: t.file.path, line: t.line);

class TaskListView extends StatefulWidget {
  const TaskListView({
    super.key,
    required this.model,
    required this.selected,
    required this.onSelectionChanged,
    required this.onTapTask,
    required this.onToggle,
    this.onHeaderLongPress,
    this.onRefresh,
    this.controller,
    this.allowSelection = true,
    this.empty,
    this.highlight,
    this.onTag,
  });

  /// Briefly highlighted row (a task just added or revealed).
  final LineKey? highlight;

  final FlatModel model;
  final Set<LineKey> selected; // empty = not selecting
  final ValueChanged<Set<LineKey>> onSelectionChanged;
  final ValueChanged<Task> onTapTask;
  final ValueChanged<Task> onToggle;
  final ValueChanged<String>? onTag; // tapping a tag
  final ValueChanged<int>? onHeaderLongPress; // row index
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final bool allowSelection;
  final Widget? empty;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  final _listKey = GlobalKey();
  ScrollController? _own;
  ScrollController get _ctrl => widget.controller ?? (_own ??= ScrollController());

  // Drag selection.
  int? _anchor;
  bool _dragAdd = true;
  Set<LineKey> _dragBase = {};
  double _dragY = 0;
  Timer? _autoScroll;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _own?.dispose();
    super.dispose();
  }

  FlatModel get m => widget.model;
  bool get _selecting => widget.selected.isNotEmpty;

  int? _rowAtGlobal(double globalY) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || m.rows.isEmpty) return null;
    final local = box.globalToLocal(Offset(0, globalY)).dy;
    final i = ((local + _ctrl.offset) / rowExtent).floor();
    return i.clamp(0, m.rows.length - 1);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (!widget.allowSelection) return;
    final row = _rowAtGlobal(d.globalPosition.dy);
    if (row == null) return;
    final r = m.rows[row];
    if (r.isHeader) {
      widget.onHeaderLongPress?.call(row);
      return;
    }
    HapticFeedback.selectionClick();
    _anchor = row;
    _dragBase = Set.of(widget.selected);
    _dragAdd = !_dragBase.contains(keyOf(r.task!));
    _dragY = d.globalPosition.dy;
    _applyRange(row);
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _tickAutoScroll());
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_anchor == null) return;
    _dragY = d.globalPosition.dy;
    final row = _rowAtGlobal(_dragY);
    if (row != null) _applyRange(row);
  }

  void _onLongPressEnd() {
    _anchor = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _tickAutoScroll() {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _anchor == null) return;
    final local = box.globalToLocal(Offset(0, _dragY)).dy;
    const edge = 64.0;
    double delta = 0;
    if (local < edge) delta = -(edge - local) / 3;
    if (local > box.size.height - edge) delta = (local - (box.size.height - edge)) / 3;
    if (delta == 0) return;
    final pos = _ctrl.position;
    final next = (_ctrl.offset + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (next == _ctrl.offset) return;
    _ctrl.jumpTo(next);
    final row = _rowAtGlobal(_dragY);
    if (row != null) _applyRange(row);
  }

  void _applyRange(int row) {
    final a = _anchor!;
    final lo = a < row ? a : row, hi = a < row ? row : a;
    final next = Set.of(_dragBase);
    for (var i = lo; i <= hi; i++) {
      final t = m.rows[i].task;
      if (t == null) continue;
      if (_dragAdd) {
        next.add(keyOf(t));
      } else {
        next.remove(keyOf(t));
      }
    }
    if (next.length != widget.selected.length || !next.containsAll(widget.selected)) {
      widget.onSelectionChanged(next);
    }
  }

  void _tapRow(int i) {
    final r = m.rows[i];
    if (r.isHeader) {
      if (_selecting) {
        // Select (or clear) every visible task of the group.
        final end = m.groupEnd(i);
        final keys = [for (var j = i + 1; j < end; j++) keyOf(m.rows[j].task!)];
        final next = Set.of(widget.selected);
        if (keys.every(next.contains)) {
          next.removeAll(keys);
        } else {
          next.addAll(keys);
        }
        widget.onSelectionChanged(next);
      } else {
        m.toggle(i);
      }
      return;
    }
    if (_selecting) {
      final k = keyOf(r.task!);
      final next = Set.of(widget.selected);
      if (!next.remove(k)) next.add(k);
      widget.onSelectionChanged(next);
    } else {
      widget.onTapTask(r.task!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        if (m.rows.isEmpty && widget.empty != null) {
          final child = LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(height: c.maxHeight, child: widget.empty),
            ),
          );
          return widget.onRefresh == null ? child : RefreshIndicator(onRefresh: widget.onRefresh!, child: child);
        }
        Widget list = ListView.builder(
          key: _listKey,
          controller: _ctrl,
          physics: const AlwaysScrollableScrollPhysics(),
          itemExtent: rowExtent,
          itemCount: m.rows.length,
          itemBuilder: _buildRow,
        );
        list = Scrollbar(controller: _ctrl, interactive: true, thickness: 6, child: list);
        list = GestureDetector(
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: (_) => _onLongPressEnd(),
          onLongPressCancel: _onLongPressEnd,
          child: list,
        );
        if (widget.onRefresh != null) list = RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
        return list;
      },
    );
  }

  Widget _buildRow(BuildContext context, int i) {
    final r = m.rows[i];
    if (r.isHeader) {
      return _HeaderRow(model: m, row: r, onTap: () => _tapRow(i), onChevron: () => m.toggle(i));
    }
    final t = r.task!;
    final k = keyOf(t);
    final selected = (_selecting && widget.selected.contains(k)) || widget.highlight == k;
    return TaskRow(
      task: t,
      row: r,
      selected: selected,
      onTap: () => _tapRow(i),
      onChevron: () => m.toggle(i),
      onCheck: _selecting ? () => _tapRow(i) : () => widget.onToggle(t),
      onTag: _selecting ? null : widget.onTag,
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.model, required this.row, required this.onTap, required this.onChevron});
  final FlatModel model;
  final ListRow row;
  final VoidCallback onTap, onChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final g = model.groups[row.group];
    final base = theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, fontSize: 14);
    Widget label;
    Widget? trailing;
    final m = model;
    if (m is AgendaModel) {
      final today = m.todayCached;
      Color? color;
      if (g.roots.isEmpty) {
        color = g.date == today ? colors.today : colors.dim;
      } else if (g.date! < today) {
        color = colors.overdue;
      } else if (g.date == today) {
        color = colors.today;
      }
      final rel = m.relativeLabel(g);
      label = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: m.dayLabel(g)),
            if (rel.isNotEmpty)
              TextSpan(
                text: '  $rel',
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
            if (g.roots.isNotEmpty)
              TextSpan(
                text: '  (${g.roots.length})',
                style: TextStyle(fontWeight: FontWeight.w400, color: colors.dim),
              ),
          ],
        ),
        style: base.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      final f = g.file!;
      label = Text(f.relPath, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);
      trailing = ProgressPill(done: f.done, total: f.total);
    }
    return Material(
      color: colors.band,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            const SizedBox(width: _leftPad),
            _Chevron(visible: row.hasChildren, expanded: row.expanded, onTap: onChevron),
            const SizedBox(width: 4),
            Expanded(child: label),
            ?trailing,
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.visible, required this.expanded, required this.onTap});
  final bool visible, expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: _chevronWidth);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: _chevronWidth,
        height: rowExtent,
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          child: Icon(Icons.chevron_right, size: 18, color: context.colors.checkBorder),
        ),
      ),
    );
  }
}

class ProgressPill extends StatelessWidget {
  const ProgressPill({super.key, required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final colors = context.colors;
    final complete = done >= total;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: complete ? colors.done : colors.pill, borderRadius: BorderRadius.circular(9)),
      child: Text(
        '$done/$total',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: complete ? Colors.white : colors.pillText,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onChevron,
    required this.onCheck,
    this.onTag,
  });

  final Task task;
  final ListRow row;
  final bool selected;
  final VoidCallback onTap, onChevron, onCheck;
  final ValueChanged<String>? onTag; // null: tags aren't tappable (selecting)

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final t = task;
    final indent = _leftPad + (row.depth - 1) * _indentStep;

    var style = theme.textTheme.bodyLarge!.copyWith(fontSize: 15, height: 1.2);
    switch (t.state) {
      case TaskState.done:
        style = style.copyWith(color: colors.dim, decoration: TextDecoration.lineThrough, decorationColor: colors.dim);
      case TaskState.cancelled:
        style = style.copyWith(
          color: colors.dim,
          decoration: TextDecoration.lineThrough,
          decorationColor: colors.dim,
          fontStyle: FontStyle.italic,
        );
      case TaskState.doing:
        style = style.copyWith(color: colors.doing, fontWeight: FontWeight.w600);
      case TaskState.todo:
        break;
    }

    final meta = <InlineSpan>[];
    final due = t.due;
    if (due != null) {
      final now = today();
      final c = !t.isOpen
          ? colors.dim
          : due < now
          ? colors.overdue
          : due == now
          ? colors.today
          : colors.dim;
      meta.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.event, size: 12, color: c),
          ),
        ),
      );
      meta.add(
        TextSpan(
          text: isoDay(due),
          style: TextStyle(color: c),
        ),
      );
    }
    if (t.eta > 0) {
      if (meta.isNotEmpty) meta.add(const TextSpan(text: '   '));
      final quick = t.isOpen && t.eta <= 2; // GTD: do it now
      meta.add(
        TextSpan(
          text: '~${t.etaText}',
          style: TextStyle(color: quick ? colors.quick : colors.dim, fontWeight: quick ? FontWeight.w600 : null),
        ),
      );
    }
    // Tags sit on the title line, at the right edge.
    final tags = <InlineSpan>[];
    for (final tag in t.tags) {
      if (tags.isNotEmpty) tags.add(const TextSpan(text: ' '));
      final label = TextSpan(
        text: '#$tag',
        style: TextStyle(color: t.isOpen ? colors.tag : colors.dim),
      );
      final onTag = this.onTag;
      tags.add(
        onTag == null
            ? label
            : WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                // A bigger target than the text, so it can be hit with a thumb.
                child: GestureDetector(
                  key: ValueKey('tag-$tag'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTag(tag),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Text.rich(label),
                  ),
                ),
              ),
      );
    }

    return Material(
      color: selected ? colors.selection : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: _GuidePainter(row.depth, colors.guide),
          child: Row(
            children: [
              SizedBox(width: indent),
              _Chevron(visible: row.hasChildren, expanded: row.expanded, onTap: onChevron),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCheck,
                child: SizedBox(
                  width: _checkWidth,
                  height: rowExtent,
                  child: Center(
                    child: CustomPaint(
                      size: const Size(17, 17),
                      painter: CheckboxPainter(t.state, colors, selected: selected),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final title = Text(
                          t.text.isEmpty ? ' ' : t.text,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                        if (tags.isEmpty) return title;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(child: title), // pushes the tags to the right edge
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.5),
                              child: Text.rich(
                                TextSpan(children: tags),
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(children: meta),
                          style: TextStyle(fontSize: 12, color: colors.dim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              ProgressPill(done: t.subDone, total: t.subTotal),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vertical guides through the chevron column of each ancestor level.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.depth, this.color);
  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth <= 1) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 1; level < depth; level++) {
      final x = _leftPad + (level - 1) * _indentStep + _chevronWidth / 2 + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.depth != depth || old.color != color;
}

/// Empty = todo, blue inner square = in progress, green tick = done,
/// grey × = cancelled.
class CheckboxPainter extends CustomPainter {
  CheckboxPainter(this.state, this.colors, {this.selected = false});
  final TaskState state;
  final TaskColors colors;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    switch (state) {
      case TaskState.todo:
        canvas.drawRRect(r.deflate(0.75), stroke..color = colors.checkBorder);
      case TaskState.doing:
        canvas.drawRRect(r.deflate(0.75), stroke..color = colors.doing);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(5, 5, size.width - 10, size.height - 10), const Radius.circular(2)),
          Paint()..color = colors.doing,
        );
      case TaskState.done:
        canvas.drawRRect(r, Paint()..color = colors.done);
        final tick = Path()
          ..moveTo(size.width * 0.24, size.height * 0.52)
          ..lineTo(size.width * 0.43, size.height * 0.70)
          ..lineTo(size.width * 0.77, size.height * 0.32);
        canvas.drawPath(
          tick,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white,
        );
      case TaskState.cancelled:
        canvas.drawRRect(r.deflate(0.75), stroke..color = colors.dim);
        final x = Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = colors.dim;
        canvas.drawLine(Offset(size.width * 0.3, size.height * 0.3), Offset(size.width * 0.7, size.height * 0.7), x);
        canvas.drawLine(Offset(size.width * 0.7, size.height * 0.3), Offset(size.width * 0.3, size.height * 0.7), x);
    }
  }

  @override
  bool shouldRepaint(CheckboxPainter old) => old.state != state || old.colors != colors || old.selected != selected;
}
