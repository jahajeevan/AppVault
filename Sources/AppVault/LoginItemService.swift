import Foundation
import ServiceManagement

@MainActor
enum LoginItemService {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}
