// The main screen: Tasks / Agenda / Calendar tabs, the search and state
// filters, selection mode with its bulk action bar, and every action flow.
// Mirrors src/mainwindow.cpp.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/actions.dart';
import '../core/day.dart';
import '../core/filter.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/task.dart';
import 'calendar.dart';
import 'add_task.dart';
import 'dialogs.dart';
import 'filter_help.dart';
import 'help_page.dart';
import 'platform.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'task_list.dart';
import 'tags.dart';
import 'task_sheet.dart';
import 'theme.dart';
import 'views.dart';

const _stateChips = [
  (TaskState.todo, 'Todo'),
  (TaskState.doing, 'Doing'),
  (TaskState.done, 'Done'),
  (TaskState.cancelled, 'Cancelled'),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store, required this.settings});
  final TaskStore store;
  final Settings settings;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  TaskStore get store => widget.store;
  Settings get settings => widget.settings;

  late final TaskActions actions = TaskActions(store);
  late final TaskListModel list;
  late final AgendaModel agenda;
  late final AgendaModel day; // the calendar's single-day list
  final search = TextEditingController();
  final listScroll = ScrollController(), agendaScroll = ScrollController();
  Timer? _debounce, _flashTimer, _statusTimer;
  String? status; // the message beside the title
  late int tab = settings.tab.clamp(0, 2);
  late int etaPreset = settings.etaPreset.clamp(0, etaPresets.length - 1);
  Set<LineKey> selected = {};
  late List<SavedView> views = settings.views;
  SavedView? view; // the active one; null = all tasks
  LineKey? flash;

  bool get selecting => selected.isNotEmpty;
  FlatModel get current => switch (tab) {
    0 => list,
    1 => agenda,
    _ => day,
  };

  @override
  void initState() {
    super.initState();
    // Created before this state listens to the store, so they rebuild first.
    list = TaskListModel(store)
      ..collapsedKeys = settings.collapsed
      ..onCollapsedChanged = (k) => settings.collapsed = k;
    agenda = AgendaModel(store)
      ..showEmptyDays = settings.emptyDays
      ..collapsedKeys = settings.agendaCollapsed
      ..onCollapsedChanged = (k) => settings.agendaCollapsed = k;
    day = AgendaModel(store, day: today());
    final states = settings.states;
    for (final m in [list, agenda, day]) {
      m.filter.states = states;
    }
    for (final m in [list, agenda]) {
      m.filter.etaPreset = etaPresets[etaPreset].conds;
    }
    final current = settings.currentView;
    view = views.where((v) => v.name == current).firstOrNull;
    for (final m in [list, agenda]) {
      m.filter.setView(view?.filter ?? '');
    }
    for (final m in [list, agenda, day]) {
      m.refilter();
    }
    store.onMessage = _say;
    store.addListener(_onStore);
    WidgetsBinding.instance.addObserver(this);
    final dirs = settings.directories;
    if (dirs.isNotEmpty && store.roots.isEmpty) store.setRoots(dirs);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onStore);
    _debounce?.cancel();
    _flashTimer?.cancel();
    _statusTimer?.cancel();
    for (final m in [list, agenda, day]) {
      m.dispose();
    }
    search.dispose();
    listScroll.dispose();
    agendaScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        store.watching = true; // also catches up with changes made meanwhile
        agenda.refreshIfDateChanged();
        day.refreshIfDateChanged();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        store.watching = false;
      default:
        break;
    }
  }

  void _onStore() {
    // Task objects are rebuilt on every change; drop keys that are gone.
    final valid = {
      for (final k in selected)
        if (store.taskFor(k) != null) k,
    };
    setState(() => selected = valid);
  }

  // ------------------------------------------------------------ feedback

  /// A short message beside the title (no snackbars: the user can't stand
  /// them). It fades after a few seconds; undo is the app bar's button.
  void _say(String text) {
    if (!mounted) return;
    _statusTimer?.cancel();
    setState(() => status = text);
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => status = null);
    });
  }

  Widget _withStatus(Widget title) {
    return Row(
      children: [
        Flexible(flex: 3, child: title),
        const SizedBox(width: 10),
        Flexible(
          flex: 2,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: status == null
                ? const SizedBox.shrink()
                : Text(
                    status!,
                    key: ValueKey(status),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                      color: context.colors.dim,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _done(int n, String label) {
    if (n == 0) {
      _say('$label: nothing to change');
    } else {
      _say('$label: $n line${n == 1 ? '' : 's'} changed');
    }
  }

  void _flashKey(LineKey? k) {
    _flashTimer?.cancel();
    setState(() => flash = k);
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => flash = null);
    });
  }

  void _scrollTo(FlatModel m, ScrollController c, int row) {
    if (row < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasClients) return;
      final pos = c.position;
      final top = c.offset, bottom = top + pos.viewportDimension;
      final y = row * rowExtent;
      if (y >= top && y + rowExtent <= bottom) return;
      c.jumpTo((y - pos.viewportDimension / 3).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    });
  }

  void _showNew(LineKey? k) {
    if (k == null) return;
    final t = store.taskFor(k);
    if (t == null) return;
    if (tab == 0) {
      _scrollTo(list, listScroll, list.reveal(t));
    } else if (tab == 1) {
      _scrollTo(agenda, agendaScroll, agenda.indexOf(t));
    }
    _flashKey(k);
  }

  // ------------------------------------------------------------ selection

  List<Task> get selectedTasks => [for (final k in selected) ?store.taskFor(k)];

  void _setSelection(Set<LineKey> s) => setState(() => selected = s);

  void _selectAll() {
    _setSelection({
      for (final r in current.rows)
        if (r.task != null) keyOf(r.task!),
    });
  }

  void _setTab(int i) {
    if (i == tab) return;
    setState(() {
      tab = i;
      selected = {};
    });
    settings.tab = i;
  }

  // ------------------------------------------------------------ filtering

  void _applyFilter() {
    for (final m in [list, agenda]) {
      m.filter.setText(search.text);
      m.refilter();
    }
    setState(() {});
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _applyFilter);
  }

  void setFilter(String text) {
    _debounce?.cancel();
    search.text = text;
    _applyFilter();
  }

  /// Tapping a tag: show everything with it (in the Tasks tab when coming from
  /// the calendar). Tapping the tag that's already the filter clears it.
  void filterTag(String tag) {
    final term = tagTerm(tag);
    setFilter(search.text.trim().toLowerCase() == term ? '' : term);
    if (tab == 2) _setTab(0);
  }

  /// The tag the filter is set to, when it's just that ("#office").
  String? get _activeTag {
    final t = search.text.trim();
    return t.startsWith('#') && !t.contains(' ') && t.length > 1 ? t : null;
  }

  List<String> get tagNames => [for (final t in store.tags()) t.name];

  Future<void> _pickTag() async {
    final active = _activeTag?.toLowerCase();
    // Only tags on open tasks (plus the one being filtered by, so it can be cleared).
    final tags = [
      for (final t in store.tags())
        if (t.open > 0 || active == '#${t.name.toLowerCase()}') t,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => TagSheet(tags: tags, active: active),
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      setFilter('');
    } else {
      filterTag(picked);
    }
  }

  // ------------------------------------------------------------ views

  /// Shows only what [v] matches in Tasks and Agenda (null: everything).
  void setView(SavedView? v) {
    view = v;
    settings.currentView = v?.name;
    for (final m in [list, agenda]) {
      m.filter.setView(v?.filter ?? '');
      m.refilter();
    }
    setState(() => selected = {});
    if (tab == 2 && v != null) _setTab(0);
  }

  int _countMatching(String filter) {
    final f = TaskFilter()
      ..states = list.filter.states
      ..setText(filter);
    var n = 0;
    for (final file in store.files) {
      for (final t in file.tasks) {
        if (f.matches(t)) n++;
      }
    }
    return n;
  }

  Future<void> _openViews() async {
    final choice = await showModalBottomSheet<ViewChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ViewsSheet(views: views, current: view?.name, search: search.text),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case SelectView(:final view):
        setView(view);
      case EditView(:final view):
        await _editView(view);
      case NewView(:final filter):
        await _editView(null, filter: filter);
    }
  }

  Future<void> _editView(SavedView? original, {String filter = ''}) async {
    final edit = await showViewEditor(
      context,
      initial: original,
      filter: filter,
      taken: {
        for (final v in views)
          if (v != original) v.name.toLowerCase(),
      },
      tags: [
        for (final t in store.tags())
          if (t.open > 0) t.name,
      ],
      count: _countMatching,
    );
    if (!mounted || edit == null) return;
    final next = [...views];
    final i = original == null ? -1 : next.indexOf(original);
    final saved = edit.saved;
    if (edit.deleted) {
      if (i >= 0) next.removeAt(i);
    } else if (saved != null) {
      if (i >= 0) {
        next[i] = saved;
      } else {
        next.add(saved);
      }
    }
    views = next;
    settings.views = next;
    if (edit.deleted) {
      if (view == original) setView(null);
      _say('Deleted view "${original!.name}"');
    } else if (saved != null) {
      // A new view, or the active one edited: show it. A new one made from
      // the search box takes the search's place.
      if (original == null && filter.isNotEmpty && search.text.trim() == filter) setFilter('');
      if (original == null || view == original) setView(saved);
    }
    setState(() {});
  }

  void _toggleState(TaskState s) {
    final on = !list.filter.stateVisible(s);
    for (final m in [list, agenda, day]) {
      m.filter.setStateVisible(s, on);
      m.refilter();
    }
    settings.states = list.filter.states;
    setState(() {});
  }

  void _setEtaPreset(int i) {
    etaPreset = i;
    settings.etaPreset = i;
    for (final m in [list, agenda]) {
      m.filter.etaPreset = etaPresets[i].conds;
      m.refilter();
    }
    setState(() {});
  }

  // ------------------------------------------------------------ actions

  void toggleTask(Task t) {
    final n = actions.toggleTask(t);
    _done(n, t.state == TaskState.done ? 'Mark todo' : 'Mark done');
  }

  void _swipe(Task t, bool right) {
    if (right) {
      toggleTask(t);
    } else {
      _due([t]);
    }
  }

  void _state(List<Task> tasks, TaskState s) => _done(actions.setState(tasks, s), stateLabels[s]!);

  /// Share the selected tasks' text as a bullet list: to another app through
  /// the system share sheet, or onto the clipboard.
  Future<void> _share(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final n = tasks.length;
    final copy = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('Share $n task${n == 1 ? '' : 's'} as a list', style: Theme.of(sheet).textTheme.titleMedium),
            ),
            if (canShare)
              ListTile(
                key: const Key('share-app'),
                leading: const Icon(Icons.share_outlined),
                title: const Text('Send to an app'),
                subtitle: const Text('WhatsApp, email, notes …'),
                onTap: () => Navigator.pop(sheet, false),
              ),
            ListTile(
              key: const Key('share-copy'),
              leading: const Icon(Icons.copy),
              title: const Text('Copy as text'),
              onTap: () => Navigator.pop(sheet, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (copy == null) return;
    final text = bulletList(tasks);
    if (copy) {
      await Clipboard.setData(ClipboardData(text: text));
      _say('Copied $n task${n == 1 ? '' : 's'}');
    } else {
      await shareText(text);
    }
    if (mounted) setState(() => selected = {});
  }

  Future<void> _due(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final choice = await pickDue(context, initial: tasks.first.due, count: expand(tasks).length);
    if (choice == null) return;
    _done(actions.setDue(tasks, choice.day), choice.day == null ? 'Clear due date' : 'Set due date');
  }

  Future<void> _eta(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final eta = await pickEta(context, current: tasks.first.etaText, count: expand(tasks).length);
    if (eta == null) return;
    _done(actions.setEta(tasks, eta), eta.isEmpty ? 'Clear ETA' : 'Set ETA');
  }

  Future<void> _replace(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final spec = await pickReplace(context, count: expand(tasks).length);
    if (spec == null || (spec.find.isEmpty && !spec.regex)) return;
    try {
      _done(actions.replace(tasks, spec.apply), 'Replace');
    } on FormatException catch (e) {
      _say('Invalid regular expression: ${e.message}');
    }
  }

  Future<void> _delete(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final n = expand(tasks).length;
    final ok = await confirm(
      context,
      'Delete tasks',
      'Delete $n task line${n == 1 ? '' : 's'} (including subtasks)? You can undo this.',
      action: 'Delete',
    );
    if (!ok) return;
    setState(() => selected = {});
    _done(actions.delete(tasks), 'Delete');
  }

  Future<void> _add(Task anchor, {required bool subtask}) async {
    final t = await showAddTask(
      context,
      tags: tagNames,
      title: subtask ? 'New subtask' : 'New task',
      where: subtask ? 'under "${anchor.text}"' : 'after "${anchor.text}"',
    );
    if (t == null) return;
    setState(() => selected = {});
    final k = actions.addAfter(anchor, t.text, subtask: subtask, due: t.due);
    if (k != null) _say(subtask ? 'Subtask added' : 'Task added');
    _showNew(k);
  }

  /// The + button: always into todo.md in the (first) folder, created if needed.
  Future<void> addTopLevel() async {
    if (store.roots.isEmpty) return _openSettings();
    final path = actions.inboxPath;
    final t = await showAddTask(context, tags: tagNames, title: 'New task', where: relPathFor(path, store.roots));
    if (t == null) return;
    final k = actions.append(path, t.text, due: t.due);
    if (k != null) _say('Task added');
    if (tab != 0) _setTab(0);
    _showNew(k);
  }

  Future<void> _open(Task t) async {
    final err = await openInEditor(t.file.path, t.line + 1);
    if (err != null) _say('Could not open ${t.file.relPath}: $err');
  }

  void reveal(Task t) {
    _setTab(0);
    final row = list.reveal(t);
    if (row < 0) {
      _say('Hidden by the current filter');
      return;
    }
    _scrollTo(list, listScroll, row);
    _flashKey(keyOf(t));
  }

  void _openTask(Task t) {
    final key = keyOf(t);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        void close() => Navigator.pop(sheet);
        Task? fresh() => store.taskFor(key);
        return TaskSheet(
          store: store,
          taskKey: key,
          tags: tagNames,
          onTag: (tag) {
            close();
            filterTag(tag);
          },
          onAddTag: (tag) {
            if (fresh() case final t?) actions.addTag(t, tag);
          },
          onRemoveTag: (tag) {
            if (fresh() case final t?) actions.removeTag(t, tag);
          },
          onState: (s) {
            close();
            if (fresh() case final t?) _state([t], s);
          },
          onSave: (text) {
            close();
            if (fresh() case final t?) _done(actions.setContent(t, text), 'Edit');
          },
          onAction: (a) {
            close();
            final t = fresh();
            if (t == null) return;
            switch (a) {
              case SheetAction.due:
                _due([t]);
              case SheetAction.eta:
                _eta([t]);
              case SheetAction.addBelow:
                _add(t, subtask: false);
              case SheetAction.addSubtask:
                _add(t, subtask: true);
              case SheetAction.open:
                _open(t);
              case SheetAction.delete:
                _delete([t]);
              case SheetAction.select:
                _setSelection({key});
            }
          },
        );
      },
    );
  }

  void _openHelp() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (page) => HelpPage(
          onFilterHelp: () {
            Navigator.pop(page); // back to the list, where an example applies
            _help();
          },
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(store: store, settings: settings),
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setSelection({});
      },
      child: Scaffold(
        appBar: selecting ? _selectionBar() : _appBar(),
        body: Column(
          children: [
            if (store.loading) const LinearProgressIndicator(minHeight: 2),
            if (store.roots.isEmpty)
              Expanded(child: _NoFolders(onAdd: _openSettings))
            else ...[
              if (tab < 2) _filterBar(),
              Expanded(child: _card(_body())),
            ],
          ],
        ),
        floatingActionButton: !selecting && tab == 0 && store.roots.isNotEmpty
            ? FloatingActionButton(tooltip: 'Add task', onPressed: addTopLevel, child: const Icon(Icons.add))
            : null,
        bottomNavigationBar: selecting ? _actionBar() : _navBar(),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      title: _withStatus(GestureDetector(
        key: const Key('viewTitle'),
        behavior: HitTestBehavior.opaque,
        onTap: _openViews,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(view?.name ?? 'todo.md', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: context.colors.dim),
          ],
        ),
      )),
      actions: [
        IconButton(
          tooltip: store.canUndo ? 'Undo ${store.undoLabel}' : 'Undo',
          onPressed: store.canUndo ? store.undo : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: store.canRedo ? 'Redo ${store.redoLabel}' : 'Redo',
          onPressed: store.canRedo ? store.redo : null,
          icon: const Icon(Icons.redo),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'expand':
                current.expandAll();
              case 'collapse':
                current.collapseAll();
              case 'empty':
                agenda.showEmptyDays = !agenda.showEmptyDays;
                settings.emptyDays = agenda.showEmptyDays;
                setState(() {});
              case 'reload':
                store.reload();
              case 'select':
                _selectAll();
              case 'settings':
                _openSettings();
              case 'help':
                _openHelp();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'select', child: Text('Select all')),
            const PopupMenuItem(value: 'expand', child: Text('Expand all')),
            const PopupMenuItem(value: 'collapse', child: Text('Collapse all')),
            if (tab == 1)
              CheckedPopupMenuItem(value: 'empty', checked: agenda.showEmptyDays, child: const Text('Show empty days')),
            const PopupMenuItem(value: 'reload', child: Text('Reload')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'settings', child: Text('Folders & theme')),
            const PopupMenuItem(value: 'help', child: Text('Help')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar() {
    final tasks = selectedTasks;
    return AppBar(
      leading: IconButton(tooltip: 'Done selecting', icon: const Icon(Icons.close), onPressed: () => _setSelection({})),
      title: _withStatus(Text('${selected.length} selected')),
      actions: [
        IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all), onPressed: _selectAll),
        IconButton(tooltip: 'Share', icon: const Icon(Icons.share_outlined), onPressed: () => _share(tasks)),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(tasks)),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'replace':
                _replace(tasks);
              case 'clearDue':
                _done(actions.setDue(tasks, null), 'Clear due date');
              case 'clearEta':
                _done(actions.setEta(tasks, ''), 'Clear ETA');
              case 'sub':
                _add(tasks.first, subtask: true);
              case 'below':
                _add(tasks.first, subtask: false);
              case 'open':
                _open(tasks.first);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'replace', child: Text('Replace text…')),
            const PopupMenuItem(value: 'clearDue', child: Text('Clear due date')),
            const PopupMenuItem(value: 'clearEta', child: Text('Clear ETA')),
            if (tasks.length == 1) ...[
              const PopupMenuItem(value: 'below', child: Text('Add task below')),
              const PopupMenuItem(value: 'sub', child: Text('Add subtask')),
              const PopupMenuItem(value: 'open', child: Text('Open file')),
            ],
          ],
        ),
      ],
    );
  }

  Widget _filterBar() {
    final colors = context.colors;
    return Material(
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
        child: Column(
          children: [
            TextField(
              key: const Key('search'),
              controller: search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Search tasks, or tap ? for #tags, dates …',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ListenableBuilder(
                  listenable: search,
                  builder: (_, _) => search.text.isEmpty
                      ? IconButton(
                          tooltip: 'How to filter',
                          icon: const Icon(Icons.help_outline, size: 20),
                          onPressed: _help,
                        )
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () => setFilter(''),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    PopupMenuButton<int>(
                      key: const Key('etaFilter'),
                      tooltip: 'Filter by ETA',
                      initialValue: etaPreset,
                      onSelected: _setEtaPreset,
                      itemBuilder: (_) => [
                        for (var i = 0; i < etaPresets.length; i++)
                          PopupMenuItem(value: i, key: ValueKey('eta-$i'), child: Text(etaPresets[i].label)),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: etaPreset == 0 ? null : colors.selection,
                          avatar: const Icon(Icons.timer_outlined, size: 16),
                          label: Text(etaPreset == 0 ? 'ETA' : etaPresets[etaPreset].label),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        key: const Key('tagFilter'),
                        onTap: _pickTag,
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _activeTag == null ? null : colors.selection,
                          avatar: const Icon(Icons.tag, size: 16),
                          label: Text(_activeTag ?? 'Tags'),
                        ),
                      ),
                    ),
                    for (final (s, label) in _stateChips)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          key: ValueKey('state-$label'),
                          visualDensity: VisualDensity.compact,
                          label: Text(label),
                          selected: list.filter.stateVisible(s),
                          onSelected: (_) => _toggleState(s),
                        ),
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

  Future<void> _help() async {
    final term = await showFilterHelp(context);
    if (term != null && mounted) setFilter(term);
  }

  /// Paper: the content sits in a rounded, bordered card on the window colour.
  Widget _card(Widget child) {
    final colors = context.colors;
    if (!colors.card) return child;
    final theme = Theme.of(context);
    final r = BorderRadius.circular(colors.radius + 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: r,
          child: ColoredBox(color: theme.colorScheme.surface, child: child),
        ),
      ),
    );
  }

  Widget _body() {
    final searching = list.filter.searchNarrows || etaPreset != 0;
    Widget empty(String what) => _Empty(
      text: searching
          ? 'Nothing matches the filter'
          : view != null
          ? 'Nothing in "${view!.name}"'
          : what,
      action: searching
          ? TextButton(onPressed: () => setFilter(''), child: const Text('Clear filter'))
          : view != null
          ? TextButton(onPressed: () => setView(null), child: const Text('Show all tasks'))
          : null,
    );
    switch (tab) {
      case 0:
        return TaskListView(
          key: const Key('list'),
          model: list,
          controller: listScroll,
          selected: selected,
          highlight: flash,
          onSelectionChanged: _setSelection,
          onTapTask: _openTask,
          onToggle: toggleTask,
          onTag: filterTag,
          onSwipe: _swipe,
          onRefresh: store.refresh,
          empty: store.loading ? const SizedBox() : empty('No tasks yet. Tap + to add one.'),
        );
      case 1:
        return TaskListView(
          key: const Key('agenda'),
          model: agenda,
          controller: agendaScroll,
          selected: selected,
          highlight: flash,
          onSelectionChanged: _setSelection,
          onTapTask: _openTask,
          onToggle: toggleTask,
          onTag: filterTag,
          onSwipe: _swipe,
          onRefresh: store.refresh,
          empty: store.loading ? const SizedBox() : empty('Nothing due. Tasks with !YYYY-MM-DD show here.'),
        );
      default:
        return CalendarPane(
          store: store,
          dayModel: day,
          filterText: search.text,
          onFilter: (f) {
            setFilter(f);
            if (f.isNotEmpty) _setTab(0);
          },
          onReveal: reveal,
          onToggle: toggleTask,
          onTag: filterTag,
          onSwipe: _swipe,
        );
    }
  }

  Widget _navBar() {
    return NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: _setTab,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
        NavigationDestination(icon: Icon(Icons.view_agenda_outlined), label: 'Agenda'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Calendar'),
      ],
    );
  }

  Widget _actionBar() {
    final tasks = selectedTasks;
    Widget b(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
      child: InkWell(
        key: ValueKey('bulk-$label'),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11.5, height: 1.2), maxLines: 1),
          ],
        ),
      ),
    );
    final colors = context.colors;
    return Material(
      color: Theme.of(context).navigationBarTheme.backgroundColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              b(Icons.check_box, 'Done', () => _state(tasks, TaskState.done), color: colors.done),
              b(
                Icons.indeterminate_check_box_outlined,
                'Doing',
                () => _state(tasks, TaskState.doing),
                color: colors.doing,
              ),
              b(Icons.check_box_outline_blank, 'Todo', () => _state(tasks, TaskState.todo)),
              b(
                Icons.disabled_by_default_outlined,
                'Cancel',
                () => _state(tasks, TaskState.cancelled),
                color: colors.dim,
              ),
              b(Icons.event, 'Due', () => _due(tasks)),
              b(Icons.timer_outlined, 'ETA', () => _eta(tasks)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.dim),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _NoFolders extends StatelessWidget {
  const _NoFolders({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48, color: context.colors.dim),
            const SizedBox(height: 12),
            const Text(
              'Point it at a folder of markdown notes.\nEvery .md file in it is searched for tasks.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add a folder'),
            ),
          ],
        ),
      ),
    );
  }
}
