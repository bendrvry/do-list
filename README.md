# Do List

A to-do list for the Mac that gets out of your way.

Press **⌃⌥T** from anywhere, type the thing, press Return. That's the whole idea.

---

## Why another to-do app?

Most to-do apps start simple and then keep going. Projects, tags, priorities, due dates, reminders, a sidebar, an inbox, a sync account, a subscription. After a while you spend more time looking after the list than doing what's on it.

Do List is the opposite. It's one list. You add things, you tick them off, they go away. There's nothing to organise and nothing to set up, so there's nothing to fall behind on.

What it does have is the small stuff done properly:

- **It's fast to reach.** One shortcut opens it from any app, with the cursor already in the input. Press it again and it's gone.
- **You can just start typing.** Whenever the window is in front, typing goes straight into a new task. No clicking a "+" first.
- **It lives in the menu bar too.** Click the ✓ icon and your list drops down without pulling you out of whatever you were doing.
- **Done means done.** Completed tasks slide below a divider and quietly clear at midnight. They aren't deleted. History keeps them, searchable, if you ever need to look back.
- **Undo works on everything.** Added the wrong thing, deleted the right thing, dragged something to the bottom by accident: ⌘Z.
- **It feels like a Mac app** because it is one. Native window, system appearance, proper keyboard support, VoiceOver labels.

And just as important is what it doesn't do. There's no account, no sync, no analytics, no network code at all. Your tasks sit in a small SQLite file on your Mac and never go anywhere else.

---

## Install

You'll need macOS 14 Sonoma or later.

### Download

Download the zip from the [latest release](../../releases/latest), unzip it and drag **Do List** into Applications.

The app isn't notarised by Apple (that needs a paid developer account), so the first time you open it macOS will say it can't check it. Either right-click the app and choose **Open**, or go to System Settings › Privacy & Security and click **Open Anyway**. You only have to do this once.

### Build it yourself

All you need is the Xcode Command Line Tools (Swift 6). Full Xcode is optional.

```bash
git clone https://github.com/bendrvry/do-list.git
cd do-list
./scripts/build-app.sh --install
```

That builds a release copy, signs it ad hoc and puts it in `/Applications`. Leave off `--install` if you'd rather just get `build/Do List.app` and a zip next to it.

To run the tests:

```bash
./scripts/test.sh
```

---

## Using it

| | |
|---|---|
| **Add** | Type and press Return. If the window's in front, you can start typing without clicking anything. |
| **Complete** | Click the circle, or select the task and press Space. |
| **In progress** | Right-click a task and choose Mark In Progress, so you can see what you're in the middle of. |
| **Edit** | Double-click the text, or select it and press Return. Escape cancels. |
| **Reorder** | Drag it, or use ⌘↑ and ⌘↓. |
| **Everything else** | Right-click for Duplicate, Move Up / Down, Mark Incomplete and Delete. |
| **History** | ⇧⌘H shows finished tasks grouped by day, with search. Hover one and click Restore to put it back on the list. |

The first time you open Do List, one line at the bottom of the window asks if it should open at login. Nothing gets registered unless you say yes.

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

There aren't many, on purpose.

- **Open at login**, the **global shortcut**, and whether to **show the menu bar icon**.
- **Keep window on top**, for people who like their list always visible.
- **Appearance:** follow the system, or force light or dark.
- **What happens to finished tasks.** They can drop to the bottom or stay where they were. They can clear at midnight, after seven days, or never. And you can choose whether "a day" means a calendar day or 24 hours.

---

## Your data

Tasks are stored in `~/Library/Application Support/app.dolist.mac/Tasks.sqlite`. Settings use the normal macOS defaults system under `app.dolist.mac`. That's it. Nothing is uploaded, synced or tracked.

If you want to try a build without touching your real list, point it at a scratch folder:

```bash
STILL_DATA_DIR=/tmp/dolist-dev "build/Do List.app/Contents/MacOS/Do List"
```

---

## How it's built

It's a Swift package: SwiftUI for the views, AppKit for windows, menus and the menu bar, and SQLite (through the system library, no dependencies) for storage. Inside the code the project still goes by its working name, **Still**. You won't see that name anywhere in the app.

```
Sources/
  StillCore/   The task engine. No UI. Storage, migrations, undo, visibility rules.
  Still/       The Mac app. Windows, menus, menu bar dropdown, global shortcut, views.
Tests/         Swift Testing suite for StillCore
scripts/       build-app.sh, test.sh, make-icon.swift
```

A few choices worth knowing about if you're reading the code:

- **Every change goes through one place.** The UI never talks to SQLite directly. It calls `TaskStore`, where each operation is a single transaction that also records its own undo step. Anything added later, like Shortcuts support, would go through the same door.
- **Nothing happens at midnight.** Whether a finished task is visible is worked out from its timestamps, your settings and the current time. No rows get moved or deleted. A single timer wakes the app at the next moment the list could change, rather than polling, and daylight-saving changes are handled.
- **The global shortcut uses Carbon's `RegisterEventHotKey`**, so it doesn't need Accessibility or Input Monitoring permission.
- **The menu bar dropdown is a non-activating panel**, the same trick Spotlight uses. It takes your typing without stealing focus from the app you were in.
- **It refuses to make things worse.** If the database is damaged, or was written by a newer version, Do List tells you where the file is and quits without changing it.

The test suite covers task operations, undo and redo, ordering, every retention setting, daylight-saving and time-zone changes, history search and paging, and a 20,000-task history to keep an eye on speed.

If you're curious about hooking it up to Shortcuts, a command-line tool or an MCP server, [docs/FUTURE_INTEGRATIONS.md](docs/FUTURE_INTEGRATIONS.md) sketches out how that would work.

---

## Known limitations

- Search ignores case for plain English letters only (it uses SQLite's `LIKE`).
- A task is one line. If you paste several lines, they're joined into one task.
- History shows tasks that are currently finished. It isn't a log, so restoring a task takes it out of History.
- Open at Login remembers where the app was when you turned it on. Move the app to Applications first.

---

## License

[MIT](LICENSE). Do what you like with it.
