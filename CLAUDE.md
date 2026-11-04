# todo.md (app)

The mobile version of the desktop app in `../todo.md` (C++/Qt). It **mirrors
that app's behaviour exactly**: same task syntax, parsing rules, write
invariants, filter terms, agenda wording and bulk-action semantics. When
behaviour changes in one, change the other. The desktop's `CLAUDE.md` is the
reference for the rules; this file covers what differs.

Stack: **Flutter / Dart**, Android first (iOS builds, but is sandboxed to the
app's own folder). Linux desktop is enabled for development only.

## Build / run / test

```sh
flutter test                          # core, store/models, widget tests (51)
flutter analyze
flutter test benchmark/               # 200k tasks / 5,000 files, JIT timings
BENCH_DIR=~/notes flutter test benchmark/
flutter test screenshots/ --update-goldens   # PNGs in screenshots/out (real fonts from the SDK cache)
python3 tool/readme_shots.py           # then: README images (readme-*.png, Midnight) at 40% into docs/screenshots
flutter build apk --release --split-per-abi
make install-android                  # build + adb install the APK for the plugged-in phone's ABI
```

Gradle 8.14 needs JDK 17–24; this machine's default is Java 26, so build with
`JAVA_HOME=$(nix build --no-link --print-out-paths nixpkgs#jdk17)/lib/openjdk`.
The local Android SDK has no cmdline-tools, so platforms can't be added here:
avoid plugins that need a compileSdk above 36.

CI: `.github/workflows/tests.yml` (analyze + test, and a debug APK build to catch
Gradle breakage). Releases: bump `version:` in pubspec.yaml, then
`git tag vX.Y.Z && git push origin vX.Y.Z`; `release.yml` checks the tag, tests,
and attaches per-ABI + universal APKs. Signed with the `ANDROID_KEYSTORE_*`
secrets if present (via `android/key.properties`), else the debug key.

Perf baseline (JIT under `flutter test`, so a release build is faster): load
≈ 440 ms, list model ≈ 90 ms, agenda ≈ 160 ms, filter change 65–120 ms. The
search box is debounced 150 ms.

## Layout

| File | Role (desktop counterpart) |
|---|---|
| `lib/core/day.dart` | Dates as `int` days since epoch (`Day`); `todayFn` is overridable for tests. |
| `lib/core/task.dart` | `Task`, `TaskFile`, `TaskState`, `LineKey` (path + line). |
| `lib/core/parser.dart` | `parser.*`: parse, `setState/setDue/setEta/setCreated/setContent`, `parseEta`. |
| `lib/core/edits.dart` | `edits.*`: `Edit`, `LineBuffer` (CRLF, trailing newline), `applyEdits` + inverse. |
| `lib/core/filter.dart` | `TaskFilter`, `EtaCond`, `etaPresets`. |
| `lib/core/store.dart` | `TaskStore` (ChangeNotifier): roots, isolate load, per-dir watches, `refresh()`, the only writer, undo/redo. |
| `lib/core/models.dart` | `FlatModel` / `TaskListModel` / `AgendaModel` (the desktop's `FlatTaskModel`). Rows are `ListRow`. |
| `lib/core/actions.dart` | The edits behind every action (state, due, ETA, replace, delete, add). Always includes subtasks. |
| `lib/ui/task_list.dart` | `TaskListView` (48 px tasks, 30 px headers: quiet dim line + hairline, no band, plain `done/total`; the user found the old band too big. Two heights so `RowLayout` finds offsets by binary search over header rows and `_RowSliver` uses it: Flutter's own varied-extent list sums every height per layout, too slow at 200k), gestures, drag-select, `TaskRow`, `CheckboxPainter`, `ProgressPill`. |
| `lib/ui/home.dart` | Tabs, views strip + swiper, search box, selection mode + action bar, all action flows (`MainWindow`). |
| `lib/ui/filter_sheet.dart` | The search box's tune button: state toggles, ETA preset, tag list, "Search tips". |
| `lib/ui/calendar.dart` | The desktop sidebar as a tab: month grid (folds to a week), day list, stat tiles. |
| `lib/ui/task_sheet.dart`, `dialogs.dart`, `add_task.dart`, `tags.dart` | Task sheet; due, ETA, replace, prompts; add-task sheet, `DueRow`, `Pick`; tag pills, tag list, suggestions, picker. |
| `lib/ui/theme.dart`, `settings.dart`, `settings_page.dart` | Light/Soft/Dark/System and the desktop's Clean/Midnight/Paper (same tokens; accent colours in-progress; Midnight's pill tabs = nav-bar pill; Paper's card = `TaskColors.card`, `_card` in home; no roomier rows, tasks stay 48 px) + `TaskColors`; SharedPreferences (same keys as the desktop QSettings, plus `SavedView`s); folders page. |
| `lib/ui/views.dart` | `ViewStrip` (tabs along the top), `ViewSwiper` (horizontal swipes step views), view editor. |
| `lib/core/templates.dart`, `lib/ui/templates_page.dart` | Templates: dir, names, save/instantiate; list page, editor, picker. |
| `lib/ui/help_page.dart`, `filter_help.dart` | ⋮ → Help (how the app works, plain words; keep it in step with features), and the search box's ? sheet (examples tap to apply). |
| `lib/ui/platform.dart` + `MainActivity.kt` | Storage access over the `todomd/storage` channel, folder picker, open file. |

## Differences from the desktop (deliberate)

- **Storage**: dart:io straight off disk (fast scans), which on Android needs
  `MANAGE_EXTERNAL_STORAGE` ("All files access"). Not Play-store friendly; fine
  for sideloading/F-Droid. The SAF folder picker is used only to get a path
  (`treeToPath` in `MainActivity.kt`). `file_picker` and `permission_handler`
  were dropped (JNI weight; compileSdk 37).
- **Watching**: Dart can't watch recursively on Linux/Android, so each directory
  gets its own watch (max 4000), as on the desktop. Watches are dropped when the
  app is paused and `refresh()` (mtime/size diff, isolate scan) catches up on
  resume. **No pull-to-refresh** (the user removed it: horizontal view swipes kept
  catching on it); ⋮ → Reload reloads everything.
- **Isolates**: `Isolate.run` closures live in top-level helpers so they capture
  only their arguments (a closure shares its context with siblings, which could
  drag the store along and fail to send).
- **Writes**: temp file `.<name>.todomd~` + rename (in-place fallback); hidden so
  the scanner and sync tools ignore it.
- **Gestures instead of shortcuts**: checkbox tap = toggle with subtasks; row tap
  = task sheet; **no row swipes** (the user didn't want them: accidental
  completions); horizontal swipes on Tasks/Agenda switch views; long press + drag =
  range select with edge auto-scroll, done by one recognizer on the whole list
  (per-row recognizers die when their row scrolls away). Header tap = fold (or,
  while selecting, select its tasks). Back clears the selection.
- **Open in editor** opens the file with an external app (`open_filex`,
  `text/markdown` then `text/plain`); no line numbers on mobile.
- **Add task** (+) never asks for a file: it appends to `todo.md` in the first
  folder, creating it if needed (`TaskActions.inboxPath`). The add sheet
  (`add_task.dart`) also takes a due date (quick picks + inline month grid);
  add below / add subtask use the same sheet.
- **Main screen kept uncluttered** (the user asked): the search box says just
  "Search"; state toggles, ETA preset and the tag list live in `FilterSheet`
  behind the tune icon in the search box (a dot when states/ETA aren't the default).
- **Look**: the user dislikes stock Material. `theme.dart` flattens it: 4 px
  corners, thin borders, no tonal fills/tints, no ripples (`NoSplash`), no
  shadows, plain nav bar. Use the app's own `Pick` toggles and `MonthView`
  rather than Material chips and `showDatePicker`.
- **No snackbars** (the user can't stand them): messages go in a small dim line
  beside the title (`_say` / `_withStatus` in home), fading after 4 s, in both the
  normal and the selection app bar. Undo is the app bar's button. The settings page
  shows its errors inline.
- Selection is held as `LineKey`s and pruned after every store change; Task
  objects are rebuilt on each change, as on the desktop.

## Tags (added here first: port to the desktop)

- A tag is a whitespace-separated word `#name`: letters, digits, `_ - /` (non-ASCII
  counts as a letter), needing at least one non-digit (`#42` is not a tag). Trailing
  `. , ; : ! ? )` are dropped (`#office,` → `office`). `a#b`, `##x`, `#a.b` aren't tags.
- `parser.tagToken`; `Task.tags` keeps them as written, case-insensitively de-duplicated.
  Like dates and ETA they're stripped from `Task.text` but stay in `content`.
- Filter term `#tag` (case-insensitive) matches the tag or anything under it
  (`#work` matches `#work/admin`), not prefixes (`#wor`).
- UI: tags show on the title line, at the right edge (purple, `TaskColors.tag`,
  at most half the width);
  tapping one sets the filter to `#tag` (again clears; from the calendar it switches
  to Tasks). Also tappable in the task sheet. The Tags section of the filter sheet
  lists every tag on an open task, with the count (`TaskStore.tags()`); tags only on
  done/cancelled tasks are left out (suggestions still offer them).
- Typing `#…` in the add-task sheet or the task sheet's text box shows matching
  existing tags (`TagSuggestions`, `lib/ui/tags.dart`); tapping one completes the word.
- Task sheet: × on a tag removes it, "+ Tag" adds one (`pickTag`: type or pick).
  `parser.addTag/removeTag`, `actions.addTag/removeTag`: **one task only**, not its
  subtasks (unlike every other action); undoable. Removing keeps trailing punctuation
  (`Call #mum, then` → `Call, then`). The sheet follows the store (looks its task up
  by key), so it stays open and updates; tag editing is hidden while the text is dirty.

## Share / copy as list (added here first: port to the desktop)

Selection bar → share icon → "Send to an app" (Android share sheet, `shareText` over
the `todomd/storage` channel) or "Copy as text". Either way the text is the selected
tasks (not their subtasks) as `- text` lines,
text only (no checkbox, dates, ETA, tags), in visual order, indented under selected
ancestors (`actions.bulletList`). Clears the selection.

## OR in filters, and saved views (added here first: port to the desktop)

- **OR**: the word `OR` (capitals, on its own) between filter terms gives
  alternatives: `a b OR c` = (a and b) or c. Lower-case `or` is a plain word.
  `TaskFilter` parses into clauses (`_Clause`), matched if any clause holds.
- **Views** (`lib/ui/views.dart`): a name + a filter in the same language. Saved in
  SharedPreferences as JSON (`views/list`, active one in `views/current`). They're
  tabs along the top of Tasks/Agenda (`ViewStrip`, under the search box: All, each view, +; shown once a
  view exists, else ⋮ → New view…). Tap = switch, tap the active one or long-press =
  edit; swiping the list left/right steps through them (`ViewSwiper`: one model; its recognizer wins at the normal slop only while the drag is more across than down, so neither a swipe nor a scroll is mistaken for the other. Note a drag recognizer's onCancel also fires for every gesture it *lost*: the swiper ignores it unless dragging, else each scroll replayed the last swipe's offset;
  the content follows the finger and the next slides in; off while selecting).
  New view is prefilled with the search box if it has text (that search is then
  cleared). **Adding in a view**: + starts the task with the tags of the view's
  first OR-alternative (cursor before them) and due today for `due:today`
  (`viewDefaults` in filter.dart); if the view still doesn't match it, the status
  line says so. The editor has quick terms (due:week, due:overdue …) and tag pills
  that toggle a term in or out (a tag after a tag is joined with OR), and a live
  count of matching tasks (state toggles apply).
- **Subtasks come along**: a task under a task that matches shows too (its state
  toggle still applies; `_appendTask`'s `under`, ported to the desktop). And a view
  holds for every task under one it matches (`inView`, `TaskFilter.matches(inView:)`,
  also the editor's count), so a `#house` view lists the untagged subtasks of a
  `#house` task and the search box can find them within it.
- The active view's filter goes in `TaskFilter.setView` for **Tasks and Agenda** (not
  the calendar day list), ANDed with the search box, so search narrows within it.
  Picking a view from the Calendar tab switches to Tasks. Note `is:done` in a view
  still needs the Done state toggle on, as with the search box.

## done: filter terms (added here first: port to the desktop)

`done:today` / `done:week` match done tasks whose `x` date is today / in the last 7
days (today included). Tasks they match show **even with the Done state toggle off**
(asking for finished tasks implies it); everything else still follows the toggles.
The calendar's "done today" tile uses `done:today` (it used to do nothing).

## Templates (as the desktop: `src/templates.*`)

`lib/core/templates.dart` ports the desktop's rules and file format, so both apps share
`.templates/` (first root that has one, else the first root; hidden, so never scanned):
`templateFromTasks` (save: todo, all dates removed, ETAs/tags kept, 2 spaces per selected
ancestor), `instantiateTemplate` (insert: todo, `+today`, other dates dropped except a
written `!due`, re-indented with the file's unit). `TaskActions.insertTemplate` is one
undoable edit (after the anchor's subtree, as its last subtasks, or appended to todo.md).
Mobile UI (`lib/ui/templates_page.dart`): ⋮ → Templates lists them (+ = new, empty
file); tapping one opens it as an **ordinary task list** (the user asked for that, not a
text editor): `TemplateEditorPage` has its own `TaskStore` rooted at `.templates` (like
the desktop's `m_templateStore`), a `FileModel` (one file, `showHeaders = false`), and
`TaskActions(stampCreated: false)` (no `+date` in templates). Tap = the usual task sheet
minus template/open/select (`TaskSheet.hidden`); tick, swipe, + add, undo/redo all work.
Title tap = rename (a plain file rename, so case-only renames work on Android's
case-insensitive storage); ⋮ = insert into tasks, rename, delete. Selection ⋮ →
"Save as template…" (selected + subtasks), task sheet → "Insert template…" (below / as
subtasks), add sheet → "Template…" (into todo.md). Inserted tasks end up selected.
Template file writes are plain file IO (not undoable), as on the desktop.

## Not done yet

- iOS release builds; folders outside the app sandbox on iOS (security-scoped bookmarks).
- Hardware keyboard shortcuts (the desktop's single-key ones).
- Same ideas list as the desktop (reordering, recurring tasks, ETA roll-up …).
