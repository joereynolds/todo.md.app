// Tag widgets: pills, the list of every tag (filter by one), suggestions
// while typing "#…" in a text field, and a picker to add a tag to a task.

import 'package:flutter/material.dart';

import '../core/parser.dart' as parser;
import '../core/store.dart';
import 'theme.dart';

/// A tag as a tappable outlined pill ("#office"). With [onRemove], it has an
/// × to take the tag off.
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.tag,
    required this.onTap,
    this.selected = false,
    this.trailing,
    this.onRemove,
  });
  final String tag;
  final VoidCallback onTap;
  final bool selected;
  final String? trailing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = Text.rich(
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
    );
    return Container(
      decoration: BoxDecoration(
        color: selected ? colors.selection : null,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: selected ? colors.tag : colors.guide),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            key: ValueKey('pill-$tag'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(padding: EdgeInsets.fromLTRB(10, 6, onRemove == null ? 10 : 4, 6), child: label),
          ),
          if (onRemove != null)
            GestureDetector(
              key: ValueKey('untag-$tag'),
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
                child: Icon(Icons.close, size: 15, color: colors.dim),
              ),
            ),
        ],
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

/// Existing tags that start with (then contain) [partial], minus [exclude];
/// all of them when [partial] is empty. Case-insensitive.
List<String> matchTags(List<String> tags, String partial, {Set<String> exclude = const {}, int max = 12}) {
  final p = partial.toLowerCase();
  final starts = <String>[], contains = <String>[];
  for (final t in tags) {
    final l = t.toLowerCase();
    if (exclude.contains(l) || l == p) continue;
    if (l.startsWith(p)) {
      starts.add(t);
    } else if (l.contains(p)) {
      contains.add(t);
    }
  }
  return [...starts, ...contains].take(max).toList();
}

/// A row of existing tags that complete the "#…" word at the caret of
/// [controller]. Hidden when the caret isn't in such a word or nothing matches.
class TagSuggestions extends StatelessWidget {
  const TagSuggestions({super.key, required this.controller, required this.tags});
  final TextEditingController controller;
  final List<String> tags;

  /// The "#…" word around the caret: (start, end) in the text, or null.
  static (int, int)? _word(TextEditingValue v) {
    final sel = v.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final s = v.text;
    final caret = sel.baseOffset.clamp(0, s.length);
    var st = caret;
    while (st > 0 && !_space(s.codeUnitAt(st - 1))) {
      st--;
    }
    var end = caret;
    while (end < s.length && !_space(s.codeUnitAt(end))) {
      end++;
    }
    if (st == caret || s.codeUnitAt(st) != 0x23) return null; // '#'
    return (st, end);
  }

  static bool _space(int c) => c == 0x20 || c == 0x09 || c == 0x0a;

  void _pick(String tag) {
    final v = controller.value;
    final w = _word(v);
    if (w == null) return;
    final (st, end) = w;
    final s = v.text;
    final after = end < s.length ? s.substring(end) : ' ';
    final text = '${s.substring(0, st)}#$tag${after.startsWith(' ') ? '' : ' '}$after';
    final caret = st + tag.length + 2;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final v = controller.value;
        final w = _word(v);
        if (w == null || tags.isEmpty) return const SizedBox.shrink();
        final partial = v.text.substring(w.$1 + 1, v.selection.baseOffset.clamp(w.$1 + 1, v.text.length));
        // Leave out tags the text already has (other words).
        final present = <String>{};
        for (final word in v.text.split(RegExp(r'\s+'))) {
          final t = parser.tagToken(word);
          if (t != null && word != v.text.substring(w.$1, w.$2)) present.add(t.toLowerCase());
        }
        final found = matchTags(tags, partial, exclude: present);
        if (found.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SingleChildScrollView(
            key: const Key('tagSuggestions'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in found)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TagPill(tag: t, onTap: () => _pick(t)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Asks for a tag to add: type a new one or tap an existing one. Returns it
/// without the '#', or null if cancelled.
Future<String?> pickTag(BuildContext context, {required List<String> tags, Set<String> exclude = const {}}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TagPicker(tags: tags, exclude: exclude),
  );
}

class _TagPicker extends StatefulWidget {
  const _TagPicker({required this.tags, required this.exclude});
  final List<String> tags;
  final Set<String> exclude; // lower case

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _typed {
    var t = _text.text.trim();
    while (t.startsWith('#')) {
      t = t.substring(1);
    }
    return t;
  }

  bool get _valid => parser.tagToken('#$_typed') == _typed;

  void _submit() {
    if (_valid) Navigator.pop(context, _typed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _text,
          builder: (context, _) {
            final found = matchTags(widget.tags, _typed, exclude: widget.exclude, max: 40);
            final bad = _typed.isNotEmpty && !_valid;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add tag', style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('tagText'),
                    controller: _text,
                    autofocus: true,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      prefixText: '#',
                      hintText: 'new or existing tag',
                      errorText: bad ? 'Letters, digits, - _ / only, not just digits' : null,
                      suffixIcon: _valid
                          ? IconButton(
                              key: const Key('tagAdd'),
                              tooltip: 'Add',
                              icon: const Icon(Icons.check),
                              onPressed: _submit,
                            )
                          : null,
                    ),
                  ),
                  if (found.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final t in found) TagPill(tag: t, onTap: () => Navigator.pop(context, t))],
                        ),
                      ),
                    ),
                  ] else if (widget.tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('No tags yet: type one', style: TextStyle(color: colors.dim)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
