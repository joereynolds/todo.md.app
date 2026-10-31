# Todo.md (app)

The phone version of [todo.md](https://github.com/joereynolds/todo.md). Same
tasks, same markdown, same everything, just with your thumbs.

Point it at a folder of notes and it'll find every task in every `.md` file
under it.

## Installing

### Android

Grab an APK from [releases](https://github.com/joereynolds/todo.md.app/releases).
`arm64-v8a` is the one you want on pretty much any phone from the last few
years. Not sure? Get the `universal` one.

It'll ask for "All files access" when you add a folder. That's so it can read
your notes straight off storage, which is a lot faster than going through
Android's file picker API when you've got thousands of files.

Syncthing, Nextcloud, whatever. As long as the files are on the phone it works.

### iOS

No builds yet. It does build from source, but iOS only lets it see its own
folder (Files › On My iPhone › todo.md) so put or sync your notes there.

### From source

Needs Flutter.

```
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## Using it

Three tabs. Tasks (everything, grouped by file), Agenda (by due date) and
Calendar (pick a day, see what's due, plus some quick filters).

- Tap the checkbox to tick it off. Subtasks come with it
- Tap a task to edit it, change its state, due date, ETA, add subtasks etc...
- Swipe right to mark done, swipe left to set a due date
- Long press then drag to select a bunch. Then mark them all done, set a due
  date, an ETA, whatever
- Tap a file or day header to fold it up
- Pull down to refresh

Anything you do to a task also happens to its subtasks. Everything can be
undone.

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
