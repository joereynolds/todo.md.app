// Remembered folders (add / remove) and the theme.

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/store.dart';
import 'dialogs.dart';
import 'platform.dart';
import 'settings.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store, required this.settings});
  final TaskStore store;
  final Settings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Settings get settings => widget.settings;

  void _setDirs(List<String> dirs) {
    settings.directories = dirs;
    widget.store.setRoots(dirs);
    setState(() {});
  }

  void _add(String? dir) {
    if (dir == null || dir.trim().isEmpty) return;
    final n = normalizeRoot(dir.trim());
    if (!Directory(n).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n does not exist')));
      return;
    }
    final dirs = [...settings.directories];
    if (!dirs.contains(n)) dirs.add(n);
    _setDirs(dirs);
  }

  void _noAccess() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('todo.md needs "All files access" to read your notes folders')));
  }

  Future<void> _pick() async {
    if (!await ensureStorageAccess()) return mounted ? _noAccess() : null;
    _add(await pickDirectory());
  }

  Future<void> _typePath() async {
    if (!await ensureStorageAccess()) return mounted ? _noAccess() : null;
    final root = await storageRoot();
    if (!mounted) return;
    final dir = await promptText(
      context,
      title: 'Add folder',
      message: 'Full path of a folder with markdown notes',
      initial: '$root/',
      action: 'Add',
    );
    _add(dir);
  }

  @override
  Widget build(BuildContext context) {
    final dirs = settings.directories;
    final theme = Theme.of(context);
    final colors = context.colors;
    final load = widget.store.lastLoad;
    return Scaffold(
      appBar: AppBar(title: const Text('Folders & theme')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Folders', style: theme.textTheme.titleSmall),
          ),
          if (dirs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No folders yet. Every .md file under a folder is searched for tasks.',
                style: TextStyle(color: colors.dim),
              ),
            ),
          for (final d in dirs)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(d.split('/').last.isEmpty ? d : d.split('/').last),
              subtitle: Text(d, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _setDirs([...dirs]..remove(d)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (hasFolderPicker)
                  FilledButton.tonalIcon(
                    onPressed: _pick,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Choose folder'),
                  ),
                if (canUseAnyFolder) TextButton(onPressed: _typePath, child: const Text('Type a path')),
                if (Platform.isIOS)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final d = await appNotesDir();
                      _add(d);
                    },
                    icon: const Icon(Icons.folder_special_outlined),
                    label: const Text("Use the app's folder"),
                  ),
              ],
            ),
          ),
          if (Platform.isIOS)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Put (or sync) your notes in Files › On My iPhone › todo.md.',
                style: TextStyle(color: colors.dim, fontSize: 12.5),
              ),
            ),
          if (load != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '${load.tasks} tasks in ${load.files} files, loaded in ${load.ms} ms',
                style: TextStyle(color: colors.dim, fontSize: 12.5),
              ),
            ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Theme', style: theme.textTheme.titleSmall),
          ),
          RadioGroup<AppTheme>(
            groupValue: settings.theme,
            onChanged: (t) => setState(() => settings.theme = t ?? AppTheme.light),
            child: Column(
              children: [
                for (final t in AppTheme.values) RadioListTile<AppTheme>(value: t, title: Text(themeLabels[t]!)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
