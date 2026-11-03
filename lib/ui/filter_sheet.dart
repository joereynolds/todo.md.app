// The filters behind the search box's tune button: which states show, an ETA
// preset, and the tags in use (tap one to filter by it). State and ETA
// changes apply as they're made; a tag or "Search tips" closes the sheet.

import 'package:flutter/material.dart';

import '../core/filter.dart';
import '../core/store.dart';
import '../core/task.dart';
import 'add_task.dart';
import 'tags.dart';
import 'theme.dart';

const stateFilters = [
  (TaskState.todo, 'Todo'),
  (TaskState.doing, 'Doing'),
  (TaskState.done, 'Done'),
  (TaskState.cancelled, 'Cancelled'),
];

/// The state toggles' default: todo and doing shown.
const defaultStates = 0x3;

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.states,
    required this.etaPreset,
    required this.tags,
    required this.activeTag,
    required this.onStates,
    required this.onEta,
    required this.onTag,
    required this.onHelp,
  });

  final int states, etaPreset;
  final List<TagCount> tags;
  final String? activeTag; // "#office", lower case
  final ValueChanged<int> onStates;
  final ValueChanged<int> onEta;
  final ValueChanged<String> onTag; // '' clears the tag filter
  final VoidCallback onHelp;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late int _states = widget.states, _eta = widget.etaPreset;

  bool get _isDefault => _states == defaultStates && _eta == 0;

  void _setStates(int v) {
    setState(() => _states = v);
    widget.onStates(v);
  }

  void _setEta(int v) {
    setState(() => _eta = v);
    widget.onEta(v);
  }

  void _close(VoidCallback then) {
    Navigator.pop(context);
    then();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(text, style: TextStyle(color: colors.dim, fontSize: 12.5)),
    );
    final active = widget.activeTag;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Filters', style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (!_isDefault)
                    TextButton(
                      key: const Key('filtersReset'),
                      onPressed: () {
                        _setStates(defaultStates);
                        _setEta(0);
                      },
                      child: const Text('Reset'),
                    ),
                ],
              ),
              heading('Show'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (s, label) in stateFilters)
                    Pick(
                      key: ValueKey('state-$label'),
                      label: label,
                      selected: _states & stateBit(s) != 0,
                      onTap: () => _setStates(_states ^ stateBit(s)),
                    ),
                ],
              ),
              heading('Estimate'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < etaPresets.length; i++)
                    Pick(
                      key: ValueKey('eta-$i'),
                      label: etaPresets[i].label,
                      selected: _eta == i,
                      onTap: () => _setEta(i),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Tags', style: TextStyle(color: colors.dim, fontSize: 12.5)),
                    ),
                    if (active != null)
                      GestureDetector(
                        key: const Key('clearTag'),
                        onTap: () => _close(() => widget.onTag('')),
                        child: Text(
                          'Clear $active',
                          style: TextStyle(color: theme.colorScheme.primary, fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.tags.isEmpty)
                Text('No tags yet. Add one anywhere in a task, like  #office', style: TextStyle(color: colors.dim))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in widget.tags)
                      TagPill(
                        tag: t.name,
                        trailing: '${t.open}', // open tasks
                        selected: active == '#${t.name.toLowerCase()}',
                        onTap: () => _close(() => widget.onTag(t.name)),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('filterTips'),
                  onPressed: () => _close(widget.onHelp),
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Search tips: dates, estimates, OR …'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
