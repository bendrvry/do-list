import StillCore
import SwiftUI

/// Commands offered by the ⋯ button in the menu bar dropdown.
struct DropdownCommands {
    var openWindow: () -> Void
    var showHistory: () -> Void
    var showSettings: () -> Void
    var quit: () -> Void
}

/// The task list. Shown in the main window and, with a few small differences, in the
/// dropdown under the menu bar icon.
struct MainTaskView: View {
    enum Presentation {
        case window
        case dropdown(DropdownCommands)
    }

    let model: MainListModel
    var presentation: Presentation = .window

    @Environment(DayClock.self) private var clock
    @Environment(Preferences.self) private var preferences
    @Environment(LoginItemService.self) private var loginItems
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            inputRow
            content
            if isWindow && !preferences.hasAnsweredLoginItemPrompt && !loginItems.isEnabled {
                LoginPrompt()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
    }

    private var isWindow: Bool {
        if case .window = presentation { return true }
        return false
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(Theme.headingFont)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(clock.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(Theme.dateFont)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if case .dropdown(let commands) = presentation {
                MoreMenu(commands: commands)
            }
        }
        .padding(.leading, Theme.margin)
        .padding(.trailing, isWindow ? Theme.margin : Theme.margin - 6)
        // The window's content starts below its title bar; the dropdown has none.
        .padding(.top, isWindow ? 6 : 18)
        .padding(.bottom, 18)
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: Theme.checkboxGap) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(model.inputFocus.isFocused ? Theme.secondaryText : Theme.placeholder)
                .frame(width: Theme.checkboxSize)
                .accessibilityHidden(true)
            TaskInputField(text: $draft, focus: model.inputFocus) { title in
                model.add(title)
            } onMoveDown: {
                model.selectFirst()
                if model.selectedID != nil { NSApp.keyWindow?.makeFirstResponder(nil) }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, Theme.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { model.inputFocus.focus() }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        let rows = model.rows
        if rows.isEmpty {
            Text("Nothing on your list.")
                .font(Theme.taskFont)
                .foregroundStyle(Theme.secondaryText)
                .padding(.leading, Theme.margin + Theme.checkboxSize + Theme.checkboxGap)
                .padding(.top, Theme.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(rows) { row in
                        switch row {
                        case .task(let task, let movable):
                            TaskRow(task: task, model: model, isMovable: movable)
                                .moveDisabled(!movable || model.editingID != nil)
                        case .divider:
                            GroupDivider()
                                .moveDisabled(true)
                                .accessibilityHidden(true)
                        }
                    }
                    .onMove { source, destination in
                        model.move(from: source, to: destination)
                    }
                    .listRowInsets(EdgeInsets(
                        top: 0, leading: Theme.margin - Theme.rowBleed,
                        bottom: 0, trailing: Theme.margin - Theme.rowBleed
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
                .onChange(of: model.scrollRequest) { _, id in
                    guard let id else { return }
                    withAnimation(Theme.animation(model.reduceMotion)) { proxy.scrollTo(id) }
                    model.scrollRequest = nil
                }
            }
        }
    }
}

/// The dropdown's only extra control: the same options as right-clicking the icon.
private struct MoreMenu: View {
    let commands: DropdownCommands
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Menu {
            Button("Open Window", action: commands.openWindow)
            Button("History", action: commands.showHistory)
            Divider()
            Toggle("Keep Window on Top", isOn: $preferences.keepWindowOnTop)
            Divider()
            Button("Settings…", action: commands.showSettings)
            Button("Quit \(AppInfo.name)", action: commands.quit)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More options")
    }
}

/// The hairline between open and completed tasks.
private struct GroupDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1 / displayScale)
            .padding(.horizontal, Theme.rowBleed)
            .padding(.vertical, 8)
    }
}

/// One-time, non-modal question shown during first use. Launch at login is only
/// enabled with the user's consent.
private struct LoginPrompt: View {
    @Environment(Preferences.self) private var preferences
    @Environment(LoginItemService.self) private var loginItems

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 8) {
                Text("Open \(AppInfo.name) at login?")
                    .font(Theme.smallFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer(minLength: 4)
                Button("Not Now") { answer(false) }
                Button("Open at Login") { answer(true) }
            }
            .controlSize(.small)
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 10)
        }
    }

    private func answer(_ enable: Bool) {
        if enable { loginItems.setEnabled(true) }
        withAnimation(.easeOut(duration: 0.2)) { preferences.hasAnsweredLoginItemPrompt = true }
    }
}
