import Foundation
import Observation
import ServiceManagement

/// "Open at Login" via ServiceManagement's `SMAppService.mainApp`. No helper app or
/// background agent: the system simply launches the app at login.
@MainActor
@Observable
final class LoginItemService {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    init() { refresh() }

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = enabled
                ? "\(AppInfo.name) couldn't be added to your login items."
                : "\(AppInfo.name) couldn't be removed from your login items."
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
