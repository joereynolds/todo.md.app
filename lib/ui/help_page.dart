// Help (⋮ → Help): how the app works, for someone new to it. Text in
// `backticks` is shown as task syntax.

import 'package:flutter/material.dart';

import 'theme.dart';

const _sections = <(IconData, String, List<String>)>[
  (
    Icons.description_outlined,
    'Your tasks are in your notes',
    [
      'todo.md reads the markdown (.md) files in the folders you choose and shows every task line it finds. '
          'Nothing is stored anywhere else: when you tick a task, the app edits that line in the file.',
      'A task is a list item with a box:  `- [ ] Buy milk`. The box says its state:  `[ ]` to do,  `[/]` in progress,  '
          '`[x]` done,  `[-]` cancelled.',
      'Indent a task under another to make it a subtask. A parent shows how many of its subtasks are done, e.g. `2/4`.',
      'Edit your notes in any app (Obsidian, Markor, a sync tool …). Changes show up here when you come back, '
          'or pull the list down to refresh.',
    ],
  ),
  (
    Icons.edit_note,
    'Dates, estimates and tags',
    [
      'Add these anywhere in a task\'s text:',
      '`!2026-12-25`  a due date. Overdue tasks are red, today\'s are orange.',
      '`~15m`  a time estimate (m, h, d, w). Tasks of 2 minutes or less are green: do them now.',
      '`#work`  a tag. Tap a tag to see everything with it. `#work/admin` counts as part of `#work`.',
      'The app adds `+date` when you create a task and `xdate` when you finish one, so you can see when.',
    ],
  ),
  (
    Icons.view_agenda_outlined,
    'The three tabs',
    [
      'Tasks: everything, file by file. Tap a file\'s name to fold it.',
      'Agenda: open tasks with a due date, grouped by day, starting with anything overdue.',
      'Calendar: a month (tap the arrow to fold it to a week), the tasks due on the chosen day, and quick '
          'counts like "overdue" and "due today". Tap a count to see those tasks.',
    ],
  ),
  (
    Icons.touch_app_outlined,
    'Working with tasks',
    [
      'Tap the box to tick a task off (its subtasks too). Tap it again to undo.',
      'Tap a task to open it: change its text, state, due date, estimate or tags, add a task below it or a subtask, '
          'open its file, or delete it.',
      'Press and hold, then drag, to select several tasks. The bar at the bottom then sets them all at once; '
          'the share button sends them to another app or copies them as a list.',
    ],
  ),
  (
    Icons.add,
    'Adding tasks',
    [
      'The + button adds a task to `todo.md` in your first folder (it\'s created if it isn\'t there). '
          'You can pick a due date as you add it.',
      'To put a task somewhere else, open a task in that file and use "Add task below" or "Add subtask".',
    ],
  ),
  (
    Icons.search,
    'Searching and filtering',
    [
      'Type in the search box to show only matching tasks. Several words must all match.',
      'Special terms filter by tag, due date, estimate or state, e.g. `#home`,  `due:today`,  `~<=15m`,  `is:doing`,  '
          '`done:today`. '
          'Put `OR` between terms for "any of these". The full list, with examples you can tap to try, is under '
          '"Search tips" in the filters.',
      'The sliders button in the search box opens the filters: Todo, Doing, Done and Cancelled show or hide tasks '
          'in that state (done and cancelled are hidden at first); Estimate picks a time range; Tags lists your '
          'tags. A dot on the button means something is set; Reset puts it back.',
    ],
  ),
  (
    Icons.filter_list,
    'Views',
    [
      'A view is a search you keep, with a name. "This week" could be `due:overdue OR due:week`; '
          '"Media" could be `#music OR #video OR #photography`.',
      'Your views are tabs along the top, after All. Tap one, or swipe the list left and right to go from one to '
          'the next. The search box still narrows things down within a view.',
      'The + button in a view starts the new task with the view\'s tags (and today\'s date for a `due:today` '
          'view), so it shows up there.',
      'Make one with the + at the end of the tabs, or ⋮ → New view (it starts from whatever is in the search '
          'box). Tap the view you\'re in, or press and hold any, to edit or delete it.',
    ],
  ),
  (
    Icons.content_paste_outlined,
    'Templates',
    [
      'A template is a set of tasks you use again and again: a packing list, a weekly review, the steps of a '
          'routine job. Inserting one adds fresh copies of its tasks, all to do.',
      'Make one by selecting tasks and choosing "Save as template" from the ⋮ menu (subtasks come too, dates are '
          'dropped), or write one in Menu → Templates.',
      'Insert one from a task ("Insert template…": below it, or as its subtasks) or from the + button '
          '("Template…", into `todo.md`). The new tasks are selected afterwards, so you can give them all a due '
          'date in one go.',
      'Templates are plain files in a hidden `.templates` folder in your notes, shared with the desktop app. A due '
          'date written in a template is kept; estimates and tags are too.',
    ],
  ),
  (
    Icons.undo,
    'Undo and messages',
    [
      'Every change can be undone with the arrows at the top, even several steps back.',
      'What just happened is shown briefly next to the title. If a file was changed elsewhere in the meantime, '
          'the app doesn\'t overwrite it and says so there.',
    ],
  ),
  (
    Icons.palette_outlined,
    'Folders and theme',
    [
      'Menu → Folders & theme: add or remove the folders to read, and pick a look.',
      'On Android the app asks for "All files access" so it can read your notes folders directly.',
    ],
  ),
];

class HelpPage extends StatelessWidget {
  const HelpPage({super.key, this.onFilterHelp});

  /// Opens the "How to filter" sheet (from the Searching section).
  final VoidCallback? onFilterHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final (icon, title, paras) in _sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            for (final p in paras)
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 8),
                child: Text.rich(_rich(p, colors, theme), style: const TextStyle(fontSize: 14, height: 1.35)),
              ),
            if (title == 'Searching and filtering' && onFilterHelp != null)
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('helpFilter'),
                    onPressed: onFilterHelp,
                    child: const Text('How to filter …'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// `code` as task syntax (tags in the tag colour), the rest as plain text.
TextSpan _rich(String text, TaskColors colors, ThemeData theme) {
  final parts = text.split('`');
  return TextSpan(
    children: [
      for (var i = 0; i < parts.length; i++)
        if (i.isOdd)
          TextSpan(
            text: parts[i],
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: parts[i].startsWith('#') ? colors.tag : theme.colorScheme.primary,
              backgroundColor: colors.band,
            ),
          )
        else
          TextSpan(text: parts[i]),
    ],
  );
}
