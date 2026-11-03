// Saved views: named filters. The title opens [ViewsSheet] to switch between
// them (or back to all tasks); [showViewEditor] creates, edits and deletes.

import 'package:flutter/material.dart';

import '../core/parser.dart' as parser;
import 'add_task.dart';
import 'dialogs.dart';
import 'settings.dart';
import 'tags.dart';
import 'theme.dart';

/// What the views sheet asks for.
sealed class ViewChoice {
  const ViewChoice();
}

class SelectView extends ViewChoice {
  const SelectView(this.view);
  final SavedView? view; // null: all tasks
}

class EditView extends ViewChoice {
  const EditView(this.view);
  final SavedView view;
}

class NewView extends ViewChoice {
  const NewView(this.filter);
  final String filter; // prefilled (the current search), may be empty
}

class ViewsSheet extends StatelessWidget {
  const ViewsSheet({super.key, required this.views, required this.current, required this.search});
  final List<SavedView> views;
  final String? current;
  final String search; // the search box, offered as a new view

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    Widget mark(bool on) =>
        SizedBox(width: 24, child: on ? Icon(Icons.check, size: 20, color: theme.colorScheme.primary) : null);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('Views', style: theme.textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    key: const Key('view-all'),
                    leading: mark(current == null),
                    title: const Text('All tasks'),
                    onTap: () => Navigator.pop(context, const SelectView(null)),
                  ),
                  for (final v in views)
                    ListTile(
                      key: ValueKey('view-${v.name}'),
                      leading: mark(current == v.name),
                      title: Text(v.name),
                      subtitle: Text(
                        v.filter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.dim, fontSize: 12.5),
                      ),
                      trailing: IconButton(
                        key: ValueKey('editView-${v.name}'),
                        tooltip: 'Edit view',
                        icon: Icon(Icons.edit_outlined, size: 20, color: colors.dim),
                        onPressed: () => Navigator.pop(context, EditView(v)),
                      ),
                      onTap: () => Navigator.pop(context, SelectView(v)),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              key: const Key('newView'),
              leading: const SizedBox(width: 24, child: Icon(Icons.add, size: 20)),
              title: Text(search.trim().isEmpty ? 'New view' : 'New view from this filter'),
              subtitle: search.trim().isEmpty
                  ? null
                  : Text(search.trim(), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, NewView(search.trim())),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
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
