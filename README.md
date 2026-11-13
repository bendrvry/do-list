# Do List

A to-do list for the Mac that stays out of your way. Press **⌃⌥T** from anywhere, type the thing, press Return.

## Why another to-do app?

Most to-do apps start simple and keep growing until they have projects, tags, priorities, due dates, reminders, an inbox and a subscription. After a while you spend more time looking after the list than doing what's on it.

Do List is one list. You add things and tick them off, and they go away. There's nothing to organise or set up, so there's nothing to fall behind on.

The effort went into the small things you do fifty times a day. One shortcut opens the window from any app with the cursor already in the input, and the same shortcut hides it again. When the window is in front you can just start typing and it becomes a new task, without clicking a "+" first. There's also a ✓ in the menu bar: click it and your list drops down over whatever you're doing, and the app you were in keeps focus.

Finished tasks slide below a divider and clear at midnight. They aren't deleted, so if you need to check when you did something, History has them all, grouped by day and searchable. Undo covers everything, including the task you deleted by mistake and the one you dragged to the bottom.

It's written in Swift with native windows, so it follows your system appearance, works from the keyboard and labels everything for VoiceOver.

Do List has no account, sync or analytics, and no network code at all. Your tasks live in a small SQLite file on your Mac.

## Install

You'll need macOS 14 Sonoma or later.

### Download

Download the zip from the [latest release](../../releases/latest), unzip it and drag Do List into Applications.

The app isn't notarised (that needs a paid Apple developer account), so the first time you open it macOS will say it can't check it. Right-click the app and choose Open, or go to System Settings › Privacy & Security and click Open Anyway. You only have to do this once.

### Build it yourself

You need the Xcode Command Line Tools (Swift 6). Full Xcode is optional.

```bash
git clone https://github.com/bendrvry/do-list.git
cd do-list
./scripts/build-app.sh --install
```

That builds a release copy, signs it ad hoc and puts it in `/Applications`. Leave off `--install` if you only want `build/Do List.app` and a zip next to it.

To run the tests:

```bash
./scripts/test.sh
```

## Using it

| | |
|---|---|
| Add | Type and press Return. If the window's in front, you don't need to click into the input first. |
| Complete | Click the circle, or select the task and press Space. |
| In progress | Right-click a task and choose Mark In Progress to flag what you're in the middle of. |
| Edit | Double-click the text, or select the task and press Return. Escape cancels. |
| Reorder | Drag it, or use ⌘↑ and ⌘↓. |
| Everything else | Right-click for Duplicate, Move Up / Down, Mark Incomplete and Delete. |
| History | ⇧⌘H shows finished tasks grouped by day, with search. Hover one and click Restore to put it back on the list. |

The first time you open Do List, a line at the bottom of the window asks whether it should open at login. Nothing gets registered unless you say yes.

### Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Show or hide Do List from anywhere | **⌃⌥T** (change it in Settings) |
| New task | ⌘N |
| History | ⇧⌘H |
| Keep window on top | ⌥⌘T |
| Settings | ⌘, |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Close the window (the app keeps running) | ⌘W |
| Move from the input into the list | ↓ |
| Move the selection | ↑ ↓ |
| Complete or uncomplete | Space |
| Edit | Return |
| Delete | Delete |
| Move a task up or down | ⌘↑ / ⌘↓ |
| Back to the input | Escape |

### Settings

I've kept these to a minimum. In Settings you can turn on open at login, change the global shortcut, hide the menu bar icon, keep the window on top of other apps, and pick light, dark or the system appearance.

The rest is about finished tasks. They can drop to the bottom of the list or stay where they were, and they can clear at midnight, after seven days or never. You can also choose whether a day means the calendar day or a full 24 hours.

## Your data

Tasks are stored in `~/Library/Application Support/app.dolist.mac/Tasks.sqlite`, and settings go in the normal macOS defaults under `app.dolist.mac`. Nothing leaves your Mac.

To try a build without touching your real list, point it at a scratch folder:

```bash
STILL_DATA_DIR=/tmp/dolist-dev "build/Do List.app/Contents/MacOS/Do List"
```

## How it's built

It's a Swift package with no dependencies. SwiftUI draws the views, AppKit handles the windows, menus and menu bar, and storage uses the SQLite library that ships with macOS. The code still uses the working name, Still, but that name doesn't appear anywhere in the app.

```
Sources/
  StillCore/   The task engine. No UI. Storage, migrations, undo, visibility rules.
  Still/       The Mac app. Windows, menus, menu bar dropdown, global shortcut, views.
Tests/         Swift Testing suite for StillCore
scripts/       build-app.sh, test.sh, make-icon.swift
```

Some things that help if you're reading the code:

- The UI never talks to SQLite directly. Every change goes through `TaskStore`, where each operation runs as one transaction and records its own undo step. Anything added later, such as Shortcuts support, would call the same methods.
- Whether a finished task is visible is worked out from its timestamps, your settings and the current time, so nothing gets moved or deleted at midnight. One timer wakes the app at the next moment the list could change, and daylight-saving changes are accounted for.
- The global shortcut uses Carbon's `RegisterEventHotKey`, so it doesn't need Accessibility or Input Monitoring permission.
- The menu bar dropdown is a non-activating panel, which is how Spotlight works too. It takes your typing while the app you were in keeps focus.
- If the database is damaged or was written by a newer version, Do List tells you where the file is and quits without changing it.

The tests cover the task operations, undo and redo, ordering, each retention setting, daylight-saving and time-zone changes, and history search and paging. One test fills the history with 20,000 tasks to check it stays fast.

[docs/FUTURE_INTEGRATIONS.md](docs/FUTURE_INTEGRATIONS.md) sketches how Shortcuts, a command-line tool or an MCP server could be added.

## Known limitations

- Search only ignores case for unaccented letters, because it uses SQLite's `LIKE`.
- A task is one line. If you paste several lines, they're joined into one task.
- History shows tasks that are finished right now, so restoring a task takes it out of History.
- Open at Login remembers where the app was when you turned it on, so move the app to Applications first.

## License

[MIT](LICENSE). Do what you like with it.
