import AppKit

@MainActor
enum PasswordPrompt {
    static func request(reason: String) throws -> String {
        let alert = NSAlert(); alert.messageText = "Unlock AppVault"; alert.informativeText = reason
        alert.addButton(withTitle: "Unlock"); alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); field.placeholderString = "AppVault password"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { throw VaultError.authenticationCancelled }
        let password = field.stringValue
        guard !password.isEmpty else { throw VaultError.invalidPassword }
        return password
    }
}
