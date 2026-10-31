// The main screen: Tasks / Agenda / Calendar tabs, the search and state
// filters, selection mode with its bulk action bar, and every action flow.
// Mirrors src/mainwindow.cpp.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/actions.dart';
import '../core/day.dart';
import '../core/filter.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/task.dart';
import 'calendar.dart';
import 'add_task.dart';
import 'dialogs.dart';
import 'platform.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'task_list.dart';
import 'task_sheet.dart';
import 'theme.dart';

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
  Timer? _debounce, _flashTimer;
  late int tab = settings.tab.clamp(0, 2);
  late int etaPreset = settings.etaPreset.clamp(0, etaPresets.length - 1);
  Set<LineKey> selected = {};
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
    for (final m in [list, agenda, day]) {
      m.refilter();
    }
    store.onMessage = _snack;
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

  void _snack(String text, {bool undo = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 4),
        persist: false, // an action would otherwise keep it up until dismissed
        action: undo ? SnackBarAction(label: 'Undo', onPressed: store.undo) : null,
      ),
    );
  }

  void _done(int n, String label) {
    if (n == 0) {
      _snack('$label: nothing to change');
    } else {
      _snack('$label: $n line${n == 1 ? '' : 's'} changed', undo: true);
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
      _snack('Invalid regular expression: ${e.message}');
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
      title: subtask ? 'New subtask' : 'New task',
      where: subtask ? 'under "${anchor.text}"' : 'after "${anchor.text}"',
    );
    if (t == null) return;
    setState(() => selected = {});
    final k = actions.addAfter(anchor, t.text, subtask: subtask, due: t.due);
    if (k != null) _snack(subtask ? 'Subtask added' : 'Task added', undo: true);
    _showNew(k);
  }

  /// The + button: always into todo.md in the (first) folder, created if needed.
  Future<void> addTopLevel() async {
    if (store.roots.isEmpty) return _openSettings();
    final path = actions.inboxPath;
    final t = await showAddTask(context, title: 'New task', where: relPathFor(path, store.roots));
    if (t == null) return;
    final k = actions.append(path, t.text, due: t.due);
    if (k != null) _snack('Task added', undo: true);
    if (tab != 0) _setTab(0);
    _showNew(k);
  }

  Future<void> _open(Task t) async {
    final err = await openInEditor(t.file.path, t.line + 1);
    if (err != null) _snack('Could not open ${t.file.relPath}: $err');
  }

  void reveal(Task t) {
    _setTab(0);
    final row = list.reveal(t);
    if (row < 0) {
      _snack('Hidden by the current filter');
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
          task: t,
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
              Expanded(child: _body()),
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
    final stats = store.lastLoad;
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('todo.md'),
          if (stats != null && !store.loading)
            Text(
              '${store.taskCount} tasks · ${store.files.length} files',
              style: TextStyle(fontSize: 12, color: context.colors.dim, fontWeight: FontWeight.w400),
            ),
        ],
      ),
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
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar() {
    final tasks = selectedTasks;
    return AppBar(
      leading: IconButton(tooltip: 'Done selecting', icon: const Icon(Icons.close), onPressed: () => _setSelection({})),
      title: Text('${selected.length} selected'),
      actions: [
        IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all), onPressed: _selectAll),
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
                hintText: 'Filter: words, due:today, ~<=15m, is:doing …',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ListenableBuilder(
                  listenable: search,
                  builder: (_, _) => search.text.isEmpty
                      ? IconButton(
                          tooltip: 'Filter syntax',
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
              child: ListView(
                scrollDirection: Axis.horizontal,
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
          ],
        ),
      ),
    );
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter'),
        content: const SelectableText(
          'Space separated terms, all must match.\n\n'
          'Words match the task text or file path.\n\n'
          'ETA:  ~<=15m  ~<1h  ~>2h  ~>=1d  ~30m  ~none  ~any\n'
          'Due:  due:overdue  due:today  due:week  due:none  due:any\n'
          'State:  is:todo  is:doing  is:done  is:cancelled  is:open',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Widget _body() {
    final narrowing = list.filter.narrows;
    Widget empty(String what) => _Empty(
      text: narrowing ? 'Nothing matches the filter' : what,
      action: narrowing ? TextButton(onPressed: () => setFilter(''), child: const Text('Clear filter')) : null,
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
          showFile: true,
          onSelectionChanged: _setSelection,
          onTapTask: _openTask,
          onToggle: toggleTask,
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
