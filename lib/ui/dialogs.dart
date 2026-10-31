// Due-date picker, ETA picker (number + unit + presets), find/replace, and
// text prompts. Mirrors src/dialogs.cpp, laid out for touch.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import 'add_task.dart';
import 'theme.dart';

String _tasks(int n) => n == 1 ? '1 task' : '$n tasks';

/// A chosen due date; `day == null` means "clear".
typedef DueChoice = ({Day? day});

Future<DueChoice?> pickDue(BuildContext context, {Day? initial, required int count}) {
  return showModalBottomSheet<DueChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final colors = context.colors;
      return SafeArea(
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
                  Text(
                    'Due date',
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      initial == null ? _tasks(count) : '${_tasks(count)}, now ${isoDay(initial)}',
                      style: TextStyle(color: colors.dim, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DueRow(value: initial, allowNone: false, onChanged: (d) => Navigator.pop(context, (day: d))),
              if (initial != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, (day: null)),
                    child: const Text('Clear due date'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

const _units = [('m', 'minutes'), ('h', 'hours'), ('d', 'days'), ('w', 'weeks'), ('y', 'years')];
const _etaPresets = ['2m', '15m', '30m', '1h', '2h', '1d'];

/// Returns the ETA token without '~' ("45m"), '' to remove it, null if cancelled.
Future<String?> pickEta(BuildContext context, {required String current, required int count}) {
  return showDialog<String>(
    context: context,
    builder: (_) => EtaDialog(current: current, count: count),
  );
}

class EtaDialog extends StatefulWidget {
  const EtaDialog({super.key, required this.current, required this.count});
  final String current;
  final int count;

  @override
  State<EtaDialog> createState() => _EtaDialogState();
}

class _EtaDialogState extends State<EtaDialog> {
  late final TextEditingController _amount;
  String _unit = 'm';

  @override
  void initState() {
    super.initState();
    var amount = 15;
    final c = widget.current;
    if (c.length >= 2 && _units.any((u) => u.$1 == c[c.length - 1])) {
      amount = int.tryParse(c.substring(0, c.length - 1)) ?? amount;
      _unit = c[c.length - 1];
    }
    _amount = TextEditingController(text: '$amount');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_amount.text) ?? 0;

  void _step(int d) {
    final v = (_value + d).clamp(1, 999999999);
    _amount.text = '$v';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ETA (${_tasks(widget.count)})'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('How long it might take:'),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(onPressed: () => _step(-1), icon: const Icon(Icons.remove)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('etaAmount'),
                  controller: _amount,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(onPressed: () => _step(1), icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const Key('etaUnit'),
            initialValue: _unit,
            items: [for (final (u, label) in _units) DropdownMenuItem(value: u, child: Text(label))],
            onChanged: (u) => setState(() => _unit = u ?? 'm'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _etaPresets) ActionChip(label: Text(p), onPressed: () => Navigator.pop(context, p)),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.current.isNotEmpty)
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _value > 0 ? () => Navigator.pop(context, '$_value$_unit') : null,
          child: const Text('Set'),
        ),
      ],
    );
  }
}

class ReplaceSpec {
  const ReplaceSpec(this.find, this.replacement, {this.regex = false, this.caseSensitive = false});
  final String find, replacement;
  final bool regex, caseSensitive;

  /// Applies to a task's raw content; throws FormatException on a bad regex.
  String apply(String content) {
    final repl = replacement.replaceAll('\n', ' ');
    if (regex) {
      final re = RegExp(find, caseSensitive: caseSensitive);
      return content.replaceAllMapped(re, (m) {
        return repl.replaceAllMapped(RegExp(r'\\(\d)'), (g) => m.group(int.parse(g[1]!)) ?? '');
      });
    }
    if (find.isEmpty) return content;
    if (caseSensitive) return content.replaceAll(find, repl);
    return content.replaceAll(RegExp(RegExp.escape(find), caseSensitive: false), repl);
  }
}

Future<ReplaceSpec?> pickReplace(BuildContext context, {required int count}) {
  final find = TextEditingController(), repl = TextEditingController();
  var regex = false, cs = false;
  return showDialog<ReplaceSpec>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Replace in ${_tasks(count)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: find,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Find'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: repl,
                decoration: const InputDecoration(labelText: 'Replace with'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: regex,
                onChanged: (v) => setState(() => regex = v ?? false),
                title: const Text(r'Regular expression (\1 for groups)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: cs,
                onChanged: (v) => setState(() => cs = v ?? false),
                title: const Text('Case sensitive'),
              ),
              Text(
                'Matches the raw task text after "- [ ] ", dates included.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ReplaceSpec(find.text, repl.text, regex: regex, caseSensitive: cs)),
            child: const Text('Replace'),
          ),
        ],
      ),
    ),
  );
}

/// A one-line text prompt. Returns null if cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  String action = 'OK',
  String? hint,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(message)),
          TextField(
            key: const Key('promptField'),
            controller: c,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: Text(action)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'OK'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}
