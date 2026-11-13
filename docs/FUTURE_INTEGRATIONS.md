# Future integrations

Version 1 has no automation surface on purpose. The architecture is ready for one: every change already goes through `TaskStore` in `StillCore`, a UI-free library with transactional, validated operations:

```swift
addTask(title:)                    -> TaskItem?
openTasks()                        -> [TaskItem]
completedTasks(matching:limit:offset:)
updateTitle(id:to:)
setCompleted(id:_:) / completeTask(id:)
restoreTask(id:)
deleteTask(id:)
duplicateTask(id:)
moveTask(id:toIndex:)
```

Titles are cleaned up in one place (`TaskTitle.sanitize`): whitespace is trimmed, newlines are joined and length is capped. So any new entry point gets the same validation as the UI.

The rule for every integration below: **only the running app writes to the database.** External processes ask the app to make changes; they never open `Tasks.sqlite` themselves. That keeps undo, validation and the UI consistent, and avoids two writers.

## 1. App Intents / Shortcuts (recommended first)

This is the most native option. It needs no server and no new process, and it works with Shortcuts, Spotlight and Siri.

1. Add a file such as `Sources/Still/Intents/TaskIntents.swift`:
   - `AddTaskIntent` with a `title: String` parameter. It calls `store.addTask(title:)`.
   - `ListTasksIntent`. It returns `openTasks()` titles. `IntentResult & ReturnsValue<[String]>` is enough to start; an `AppEntity` for `TaskItem` can come later.
   - `CompleteTaskIntent` and `RestoreTaskIntent`, taking a `TaskEntity`. A `TaskEntityQuery` would be backed by `openTasks()` / `completedTasks()`.
2. Make the store reachable from intents: create it once in `AppDelegate` and expose it as `AppDependencyManager.shared.add { store }`, or as a `@MainActor` shared instance.
3. Mark the intents `@MainActor`, and set `openAppWhenRun = false` where appropriate. They run inside the app process, so the single-writer rule holds automatically.
4. Add an `AppShortcutsProvider` with phrases such as "Add a task to \(.applicationName)".

App Intents needs a properly bundled and signed app. `build-app.sh` already produces one, though Xcode's metadata extraction step (`appintentsmetadataprocessor`) is easier to run from an Xcode build.

## 2. Local command-line tool

```bash
still add "Buy milk"
still list
still complete <task-id>
```

A small `still` executable target would talk to the running app instead of the database:

- **Simplest:** a custom URL scheme (`dolist://add?title=…`), handled with `NSAppleEventManager` / `application(_:open:)` in `AppDelegate`. It suits fire-and-forget commands. Reads (`list`) need a reply channel, though, and any app can open a URL, so add-only is the safe scope.
- **Better:** an XPC Mach service, or a Unix domain socket in the app's Application Support folder with `0600` permissions. Use a small JSON request/response protocol that maps one-to-one onto the `TaskStore` operations listed above. Bind only to the local socket, never TCP.
- If the app isn't running, the CLI can launch it (`open -b app.dolist.mac`) and retry.
- Validate every request in the app: known operation, UUID that parses, title passed through `sanitize`. Return clear errors.

## 3. MCP server

An MCP server lets Claude Desktop, Claude Code and other MCP clients read and change the list:

| Tool | Maps to |
|---|---|
| `tasks.list` | `openTasks()` (+ optional `completedTasks(matching:)`) |
| `tasks.add` | `addTask(title:)` |
| `tasks.update` | `updateTitle(id:to:)` |
| `tasks.complete` | `setCompleted(id:true)` |
| `tasks.restore` | `restoreTask(id:)` |

Implement it as a **stdio** MCP server, a separate small executable that forwards to the CLI/IPC channel from option 2. That way it never opens a network port. The user enables it explicitly by adding it to their MCP client config, so nothing is exposed until they choose it.

Guidelines:

- Read-only tools (`list`) and mutating tools should be separate, so clients can grant them separately.
- Return task IDs with titles, so follow-up calls are unambiguous.
- Think about a "proposed tasks" flow for bulk sources such as email or meeting notes: the AI suggests tasks, the user confirms, and only then is `tasks.add` called. Do List itself never reads email. It only stores the tasks it's given.

## Security checklist for any integration

- Local only by default; no unauthenticated network listeners.
- Explicit user opt-in (a Settings toggle or a config entry).
- Least privilege: separate read and write capabilities.
- All writes go through `TaskStore` (validation, transactions, undo).
- Task contents are never sent anywhere unless the user configures a destination.
