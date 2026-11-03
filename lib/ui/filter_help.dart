// "How to filter": the filter syntax in plain words, with examples that can be
// tapped to try them. Pops with the chosen example's filter text.

import 'package:flutter/material.dart';

import 'theme.dart';

const _sections = <(String, String?, List<(String, String)>)>[
  ('Words', null, [('kitchen', 'Tasks that mention "kitchen" (or are in a file with it in the name)')]),
  ('Tags', null, [('#work', 'Tagged #work, including sub-tags like #work/admin')]),
  (
    'Due dates',
    null,
    [
      ('due:today', 'Due today'),
      ('due:overdue', 'Past their due date'),
      ('due:week', 'Due in the next 7 days'),
      ('due:none', 'No due date'),
      ('due:any', 'Has a due date'),
    ],
  ),
  (
    'Time estimates',
    'm = minutes, h = hours, d = days, w = weeks',
    [('~<=15m', '15 minutes or less'), ('~>2h', 'More than 2 hours'), ('~none', 'No estimate')],
  ),
  (
    'Status',
    'Done and cancelled tasks only show when their chip is on.',
    [
      ('is:doing', 'In progress'),
      ('is:open', 'Not done or cancelled yet'),
      ('is:done', 'Done'),
      ('done:today', 'Finished today (shows even with the Done chip off)'),
      ('done:week', 'Finished in the last 7 days'),
    ],
  ),
  (
    'Combining',
    'Several terms must all match. Put OR (in capitals) between them for "any of these".',
    [('#home due:week', '#home and due this week'), ('#music OR #video', 'Either tag')],
  ),
];

Future<String?> showFilterHelp(BuildContext context) {
  return showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _FilterHelp());
}

class _FilterHelp extends StatelessWidget {
  const _FilterHelp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('How to filter', style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Type words to find tasks. Tap an example below to try it.',
                style: TextStyle(color: colors.pillText, fontSize: 13.5),
              ),
              for (final (title, note, examples) in _sections) ...[
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600)),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note, style: TextStyle(color: colors.dim, fontSize: 12.5)),
                  ),
                const SizedBox(height: 4),
                for (final (term, meaning) in examples)
                  InkWell(
                    key: ValueKey('help-$term'),
                    onTap: () => Navigator.pop(context, term),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150, // the meanings line up
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.band,
                                  borderRadius: BorderRadius.circular(colors.radius),
                                ),
                                child: Text(
                                  term,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    color: term.startsWith('#') ? colors.tag : theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(meaning, style: const TextStyle(fontSize: 13.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
