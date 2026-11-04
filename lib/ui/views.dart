// Saved views: named filters, shown as tabs along the top ([ViewStrip]) and
// stepped through with horizontal swipes ([ViewSwiper]); [showViewEditor]
// creates, edits and deletes.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/parser.dart' as parser;
import 'add_task.dart';
import 'dialogs.dart';
import 'settings.dart';
import 'tags.dart';
import 'theme.dart';

/// The views along the top: "All" and each view. Tap one to show it; tap the
/// active one (or long-press any) to edit it; + makes a new one.
class ViewStrip extends StatefulWidget {
  const ViewStrip({
    super.key,
    required this.views,
    required this.current,
    required this.onSelect,
    required this.onEdit,
    required this.onNew,
  });
  final List<SavedView> views;
  final SavedView? current; // null: all tasks
  final ValueChanged<SavedView?> onSelect;
  final ValueChanged<SavedView> onEdit;
  final VoidCallback onNew;

  @override
  State<ViewStrip> createState() => _ViewStripState();
}

class _ViewStripState extends State<ViewStrip> {
  final _active = GlobalKey();

  @override
  void didUpdateWidget(ViewStrip old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      // Keep the active one in sight (after a swipe, say).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _active.currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(c, alignment: 0.5, duration: const Duration(milliseconds: 200));
        }
      });
    }
  }

  Widget _tab(BuildContext context, String label, SavedView? v) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final on = v == widget.current;
    return GestureDetector(
      key: on ? _active : null,
      behavior: HitTestBehavior.opaque,
      onTap: () => on ? (v == null ? null : widget.onEdit(v)) : widget.onSelect(v),
      onLongPress: v == null ? null : () => widget.onEdit(v),
      child: Container(
        key: ValueKey(v == null ? 'view-all' : 'view-${v.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? theme.colorScheme.primary : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? theme.colorScheme.onSurface : colors.dim,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        key: const Key('viewStrip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _tab(context, 'All', null),
          for (final v in widget.views) _tab(context, v.name, v),
          IconButton(
            key: const Key('newView'),
            tooltip: 'New view',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: Icon(Icons.add, color: context.colors.dim),
            onPressed: widget.onNew,
          ),
        ],
      ),
    );
  }
}

/// Horizontal swipes on [child] step through the views: the content follows
/// the finger, and the next one slides in. [index] of [count] (0 = all tasks).
class ViewSwiper extends StatefulWidget {
  const ViewSwiper({
    super.key,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.child,
    this.enabled = true,
  });
  final int index, count;
  final ValueChanged<int> onChanged;
  final Widget child;
  final bool enabled;

  @override
  State<ViewSwiper> createState() => _ViewSwiperState();
}

class _ViewSwiperState extends State<ViewSwiper> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
    ..addListener(() => setState(() {}));
  bool _dragging = false;
  double _dx = 0; // while dragging
  double _from = 0; // where the settle animation starts (it ends at 0)
  double _width = 1;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  double get _offset => _dragging ? _dx : _from * (1 - Curves.easeOutCubic.transform(_anim.value));

  bool _has(int dir) {
    final i = widget.index + dir;
    return i >= 0 && i < widget.count;
  }

  void _start(DragStartDetails _) {
    final at = _offset;
    _anim.stop();
    setState(() {
      _dragging = true;
      _dx = at;
    });
  }

  void _update(DragUpdateDetails d) {
    final delta = d.primaryDelta ?? 0;
    // Left (negative) goes to the next view; resist where there's none.
    final dir = (_dx + delta) < 0 ? 1 : -1;
    setState(() => _dx += _has(dir) ? delta : delta * 0.25);
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dir = _dx < 0 ? 1 : -1;
    final far = _dx.abs() > _width * 0.2;
    final flung = v.abs() > 400 && (v < 0) == (_dx < 0);
    if ((far || flung) && _dx != 0 && _has(dir)) {
      _from = dir * _width * 0.3; // the next one comes in from the side swiped away from
      widget.onChanged(widget.index + dir);
    } else {
      _from = _dx;
    }
    _dragging = false;
    _dx = 0;
    _anim.forward(from: 0);
  }

  // Also called for every gesture this recognizer lost (a scroll, a tap), so
  // only a drag in progress may move anything.
  void _cancel() {
    if (!_dragging) return;
    _from = _dx;
    _dragging = false;
    _dx = 0;
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        final dx = _offset;
        final fade = (1 - (dx.abs() / _width).clamp(0.0, 1.0) * 0.8);
        final on = widget.enabled && widget.count > 1;
        return RawGestureDetector(
          gestures: {
            if (on)
              _SwipeRecognizer: GestureRecognizerFactoryWithHandlers<_SwipeRecognizer>(
                () => _SwipeRecognizer(debugOwner: this),
                (r) => r
                  ..onStart = _start
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = _cancel,
              ),
          },
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Opacity(opacity: fade, child: widget.child),
            ),
          ),
        );
      },
    );
  }
}

/// A horizontal drag that wins at the usual slop, but only while the finger
/// has gone further across than up or down. The list's vertical scroll uses
/// the same slop, so whichever direction the finger mostly goes wins: a
/// sideways swipe with some drift isn't taken for a scroll, and a scroll with
/// some drift isn't taken for a swipe. (There's no pull-to-refresh to catch
/// a swipe that starts slightly downward at the top.)
class _SwipeRecognizer extends HorizontalDragGestureRecognizer {
  _SwipeRecognizer({super.debugOwner});

  final _downAt = <int, Offset>{};
  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downAt[event.pointer] = event.position;
    _moved = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _downAt[event.pointer];
    if (event is PointerMoveEvent && down != null) _moved = event.position - down;
    if (event is PointerUpEvent || event is PointerCancelEvent) _downAt.remove(event.pointer);
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind kind, double? deviceTouchSlop) {
    final dx = _moved.dx.abs(), dy = _moved.dy.abs();
    return dx > computeHitSlop(kind, gestureSettings) && dx > dy;
  }
}

/// The editor's answer: a view to save (in place of [ViewEdit.original] when
/// editing), or deleted.
typedef ViewEdit = ({SavedView? saved, bool deleted});

/// Create (no [initial]) or edit a view. [count] says how many tasks a filter
/// matches; [taken] are the other views' names (lower case).
Future<ViewEdit?> showViewEditor(
  BuildContext context, {
  SavedView? initial,
  String filter = '',
  required Set<String> taken,
  required List<String> tags,
  required int Function(String filter) count,
}) {
  return showModalBottomSheet<ViewEdit>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ViewEditor(initial: initial, filter: filter, taken: taken, tags: tags, count: count),
  );
}

class _ViewEditor extends StatefulWidget {
  const _ViewEditor({
    required this.initial,
    required this.filter,
    required this.taken,
    required this.tags,
    required this.count,
  });
  final SavedView? initial;
  final String filter;
  final Set<String> taken;
  final List<String> tags;
  final int Function(String filter) count;

  @override
  State<_ViewEditor> createState() => _ViewEditorState();
}

const _quick = [
  ('Due this week', 'due:week'),
  ('Overdue', 'due:overdue'),
  ('Due today', 'due:today'),
  ('No due date', 'due:none'),
  ('In progress', 'is:doing'),
  ('≤ 15m', '~<=15m'),
];

class _ViewEditorState extends State<_ViewEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _filter = TextEditingController(text: widget.initial?.filter ?? widget.filter);

  @override
  void dispose() {
    _name.dispose();
    _filter.dispose();
    super.dispose();
  }

  String? get _nameError {
    final n = _name.text.trim();
    if (n.isEmpty) return null;
    return widget.taken.contains(n.toLowerCase()) ? 'There is already a view called "$n"' : null;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _nameError == null && _filter.text.trim().isNotEmpty;

  /// Appends a term. A tag after a tag is joined with OR ("any of these").
  /// Appends a term, or takes it out (with an OR next to it) if it's there.
  void _toggle(String term) {
    final text = _filter.text.trim();
    final words = text.isEmpty ? <String>[] : text.split(RegExp(r'\s+'));
    final i = words.indexWhere((w) => w.toLowerCase() == term.toLowerCase());
    if (i < 0) return _add(term);
    words.removeAt(i);
    if (i > 0 && words[i - 1] == 'OR') {
      words.removeAt(i - 1);
    } else if (i < words.length && words[i] == 'OR') {
      words.removeAt(i);
    }
    while (words.isNotEmpty && words.first == 'OR') {
      words.removeAt(0);
    }
    while (words.isNotEmpty && words.last == 'OR') {
      words.removeLast();
    }
    final joined = words.join(' ');
    _filter.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );
  }

  void _add(String term) {
    final text = _filter.text.trimRight();
    final words = text.split(RegExp(r'\s+'));
    final lastIsTag = words.isNotEmpty && parser.tagToken(words.last) != null;
    final joined = text.isEmpty
        ? term
        : lastIsTag && parser.tagToken(term) != null
        ? '$text OR $term'
        : '$text $term';
    _filter.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      'Delete view',
      'Delete "${widget.initial!.name}"? Tasks are not touched.',
      action: 'Delete',
    );
    if (ok && mounted) Navigator.pop(context, (saved: null, deleted: true));
  }

  void _save() {
    if (!_valid) return;
    Navigator.pop(context, (saved: SavedView(_name.text.trim(), _filter.text.trim()), deleted: false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final editing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: ListenableBuilder(
            listenable: Listenable.merge([_name, _filter]),
            builder: (context, _) {
              final f = _filter.text.trim();
              final n = f.isEmpty ? null : widget.count(f);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    editing ? 'Edit view' : 'New view',
                    style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('viewName'),
                    controller: _name,
                    autofocus: !editing,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: 'Name, e.g. This week', errorText: _nameError),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('viewFilter'),
                    controller: _filter,
                    autocorrect: false,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Filter, e.g. due:week  or  #music OR #video'),
                  ),
                  TagSuggestions(controller: _filter, tags: widget.tags),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      n == null
                          ? 'Same terms as the filter box. OR between terms: any of them.'
                          : '$n task${n == 1 ? '' : 's'} match',
                      key: const Key('viewCount'),
                      style: TextStyle(color: colors.dim, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (label, term) in _quick)
                        Pick(
                          key: ValueKey('quick-$term'),
                          label: label,
                          selected: f.split(RegExp(r'\s+')).contains(term),
                          onTap: () => _toggle(term),
                        ),
                    ],
                  ),
                  if (widget.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in widget.tags.take(30))
                          TagPill(
                            tag: t,
                            selected: f.toLowerCase().split(RegExp(r'\s+')).contains('#${t.toLowerCase()}'),
                            onTap: () => _toggle('#$t'),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (editing)
                        TextButton(
                          key: const Key('deleteView'),
                          onPressed: _delete,
                          child: Text('Delete', style: TextStyle(color: colors.overdue)),
                        ),
                      const Spacer(),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      const SizedBox(width: 6),
                      FilledButton(
                        key: const Key('saveView'),
                        onPressed: _valid ? _save : null,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
