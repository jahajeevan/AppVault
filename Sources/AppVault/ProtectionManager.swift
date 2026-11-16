import AppKit
import SwiftUI

/// Coordinates the single, explicit lock state for every protected bundle. This is a practical
/// user-space guard: macOS does not expose an API that can make another app unbypassably inert.
@MainActor
final class ProtectionManager: ObservableObject {
    @Published private(set) var states: [String: ProtectionState] = [:]
    @Published private(set) var activeLock: LockSession?

    private var apps: [ProtectedApp] = []
    private var configuration = SecurityConfiguration()
    private let grants = ProtectionCoordinator()
    private var runningApps: [String: NSRunningApplication] = [:]
    private var panel: LockPanelController?
    var passwordVerification: ((String) -> Bool)?

    func updateRegistry(apps: [ProtectedApp], configuration: SecurityConfiguration) {
        self.apps = apps; self.configuration = configuration
        let enabled = Set(apps.filter(\.enabled).map(\.bundleIdentifier))
        states = states.filter { enabled.contains($0.key) }
        for id in enabled where states[id] == nil { states[id] = .locked }
    }

    func handleActivation(_ runningApp: NSRunningApplication) async {
        guard let id = runningApp.bundleIdentifier,
              let app = ApplicationMatcher.protectedApp(for: id, in: apps) else { return }
        runningApps[id] = runningApp
        if states[id] == .unlocked, await grants.hasValidGrant(for: id) { return }
        await presentLock(for: app, runningApp: runningApp)
    }

    func handleDeactivation(_ runningApp: NSRunningApplication) async {
        guard configuration.relockWhenInactive, let id = runningApp.bundleIdentifier,
              ApplicationMatcher.protectedApp(for: id, in: apps) != nil else { return }
        if states[id] == .unlocked { states[id] = .locked; await grants.revoke(bundleIdentifier: id) }
    }

    func handleTermination(_ runningApp: NSRunningApplication) async {
        guard let id = runningApp.bundleIdentifier else { return }
        runningApps.removeValue(forKey: id); states[id] = .locked
        await grants.revoke(bundleIdentifier: id)
        if activeLock?.app.bundleIdentifier == id { dismissLock() }
    }

    func submitPassword(_ password: String) async {
        guard let session = activeLock else { return }
        guard passwordVerification?(password) == true else { fail("That password was not accepted."); return }
        await unlock(session)
    }

    func usePassword() { guard var session = activeLock else { return }; session.phase = .password; activeLock = session }
    func retryTouchID() { guard let session = activeLock else { return }; Task { await authenticateTouchID(session) } }
    func cancel() { guard let session = activeLock else { return }; states[session.app.bundleIdentifier] = .locked; dismissLock() }

    private func presentLock(for app: ProtectedApp, runningApp: NSRunningApplication) async {
        let id = app.bundleIdentifier
        if activeLock?.app.bundleIdentifier == id { takeForeground(); return }
        if states[id] == .authenticating { takeForeground(); return }
        states[id] = .authenticating
        // Hide immediately before taking AppVault foreground. The notification is delivered after
        // activation, so a short exposure is an unavoidable macOS user-space limitation.
        runningApp.hide()
        let session = LockSession(app: app, method: app.effectiveMethod(global: configuration), phase: .ready)
        activeLock = session
        showPanel()
        switch session.method {
        case .touchID: await beginTouchID(afterPresenting: session)
        case .password: usePassword()
        case .touchIDOrPassword: await beginTouchID(afterPresenting: session)
        }
    }

    /// Give the screen-covering guard one run-loop turn to become visible before macOS presents
    /// its Touch ID sheet. Without this, LocalAuthentication can race the panel and briefly
    /// leave the protected app visible behind the system prompt.
    private func beginTouchID(afterPresenting session: LockSession) async {
        takeForeground()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard activeLock?.id == session.id else { return }
        await authenticateTouchID(session)
    }

    private func authenticateTouchID(_ session: LockSession) async {
        guard activeLock?.id == session.id else { return }
        activeLock?.phase = .checkingTouchID
        do { try await LocalAuthenticator().authenticate(reason: "Unlock \(session.app.displayName)", method: .touchID); await unlock(session) }
        catch VaultError.authenticationCancelled { states[session.id] = .locked; if session.method == .touchIDOrPassword { usePassword() } else { activeLock?.phase = .failed("Touch ID was cancelled. Try again.") } }
        catch { if session.method == .touchIDOrPassword { activeLock?.phase = .failed("Touch ID didn't work. Use your password or try again.") } else { activeLock?.phase = .failed("Touch ID didn't work. Try again.") } }
    }

    private func unlock(_ session: LockSession) async {
        guard activeLock?.id == session.id else { return }
        states[session.id] = .unlocked
        await grants.grant(bundleIdentifier: session.id, duration: session.app.effectiveGracePeriod(global: configuration))
        let app = runningApps[session.id]
        dismissLock()
        app?.activate(options: [])
    }

    private func fail(_ message: String) { activeLock?.phase = .failed(message) }
    private func showPanel() { if panel == nil { panel = LockPanelController(manager: self) }; panel?.show(immersive: configuration.immersiveLockScreen); takeForeground() }
    private func takeForeground() { NSApp.activate(ignoringOtherApps: true); panel?.bringToFront() }
    private func dismissLock() { panel?.hide(); activeLock = nil }
}

@MainActor
final class LockPanelController {
    private let panel: NSPanel
    private let manager: ProtectionManager
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    init(manager: ProtectionManager) {
        self.manager = manager
        panel = KeyboardLockPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520), styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isMovable = false; panel.hidesOnDeactivate = false
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: LockScreenView(manager: manager))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }
    func show(immersive: Bool) {
        if immersive, let screen = NSScreen.main {
            savedPresentationOptions = NSApp.presentationOptions
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableAppleMenu, .disableProcessSwitching, .disableHideApplication]
            panel.setFrame(screen.frame, display: true)
        } else { panel.setContentSize(NSSize(width: 460, height: 520)); panel.center() }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil); if let savedPresentationOptions { NSApp.presentationOptions = savedPresentationOptions; self.savedPresentationOptions = nil } }
    func bringToFront() { panel.makeKeyAndOrderFront(nil); panel.orderFrontRegardless() }
}

/// A borderless panel does not reliably accept a text-field first responder by default.
/// The lock screen needs to be key so its password field is usable without any mouse trick.
private final class KeyboardLockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
