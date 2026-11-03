# Todo.md (app)

The phone version of [todo.md](https://github.com/joereynolds/todo.md).

Point it at a folder of notes and it'll find every task in every `.md` file.

<p align="center">
  <img src="docs/screenshots/tasks.png" alt="Tasks, file by file, with tags, due dates and estimates" width="200">
  <img src="docs/screenshots/agenda.png" alt="Agenda: open tasks grouped by due day" width="200">
  <img src="docs/screenshots/task.png" alt="A task opened: text, tags, state and actions" width="200">
  <img src="docs/screenshots/calendar.png" alt="Calendar: month, the day's tasks, quick counts" width="200">
</p>

## Installing

### Android

TBD

### iOS

Lol. Build it yourself and pray.

### From source

Needs Flutter.

```
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Filtering

Same as the desktop

```
kitchen            tasks or file paths with "kitchen" in them
due:overdue        also due:today, due:week, due:none, due:any
is:doing           also is:todo, is:done, is:cancelled, is:open
~<=15m             quick stuff. Also ~<1h, ~>2h, ~>=1d, ~none, ~any
```

Stack them up. `due:week ~<=15m` is everything quick due this week.

## Markdown

It's the same syntax as the desktop app, see the
[README there](https://github.com/joereynolds/todo.md#markdown-representation).

```
- [ ] Sort the kitchen !2026-11-01
  - [x] Fix the tap x2026-10-29
  - [ ] Clean counter tops ~15m
  - [ ] Take bins out ~2m
- [/] Paint the hallway ~2d
```

Enjoy!
