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
flutter test                          # core, store/models, widget tests (38)
flutter analyze
flutter test benchmark/               # 200k tasks / 5,000 files, JIT timings
BENCH_DIR=~/notes flutter test benchmark/
flutter test screenshots/ --update-goldens   # PNGs in screenshots/out (real fonts from the SDK cache)
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
| `lib/ui/task_list.dart` | `TaskListView` (fixed 48 px rows, gestures, drag-select), `TaskRow`, `CheckboxPainter`, `ProgressPill`. |
| `lib/ui/home.dart` | Tabs, search + chips, selection mode + action bar, all action flows (`MainWindow`). |
| `lib/ui/calendar.dart` | The desktop sidebar as a tab: month grid (folds to a week), day list, stat tiles. |
| `lib/ui/task_sheet.dart`, `dialogs.dart`, `add_task.dart` | Task sheet; due, ETA, replace, prompts; add-task sheet, `DueRow`, `Pick`. |
| `lib/ui/theme.dart`, `settings.dart`, `settings_page.dart` | Light/Soft/Dark/System + `TaskColors`; SharedPreferences (same keys as the desktop QSettings); folders page. |
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
  resume. Pull-to-refresh calls it too.
- **Isolates**: `Isolate.run` closures live in top-level helpers so they capture
  only their arguments (a closure shares its context with siblings, which could
  drag the store along and fail to send).
- **Writes**: temp file `.<name>.todomd~` + rename (in-place fallback); hidden so
  the scanner and sync tools ignore it.
- **Gestures instead of shortcuts**: checkbox tap = toggle with subtasks; row tap
  = task sheet; swipe right = toggle done, left = due date (`Dismissible` whose
  `confirmDismiss` runs the action and returns false); long press + drag =
  range select with edge auto-scroll, done by one recognizer on the whole list
  (per-row recognizers die when their row scrolls away). Header tap = fold (or,
  while selecting, select its tasks). Back clears the selection.
- **Open in editor** opens the file with an external app (`open_filex`,
  `text/markdown` then `text/plain`); no line numbers on mobile.
- **Add task** (+) never asks for a file: it appends to `todo.md` in the first
  folder, creating it if needed (`TaskActions.inboxPath`). The add sheet
  (`add_task.dart`) also takes a due date (quick picks + inline month grid);
  add below / add subtask use the same sheet.
- **Look**: the user dislikes stock Material. `theme.dart` flattens it: 4 px
  corners, thin borders, no tonal fills/tints, no ripples (`NoSplash`), no
  shadows, plain nav bar. Use the app's own `Pick` toggles and `MonthView`
  rather than Material chips and `showDatePicker`.
- **Snackbars** must pass `persist: false`: in current Flutter a snackbar with an
  action (Undo) otherwise stays until dismissed (a reported annoyance).
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
  to Tasks). Also tappable in the task sheet. The `#` Tags chip in the filter bar
  lists every tag with its open-task count (`TaskStore.tags()`).

## Not done yet

- iOS release builds; folders outside the app sandbox on iOS (security-scoped bookmarks).
- Hardware keyboard shortcuts (the desktop's single-key ones).
- Same ideas list as the desktop (reordering, recurring tasks, ETA roll-up …).
