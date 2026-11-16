import SwiftUI
import AppKit

@main
struct AppVaultApp: App {
    @StateObject private var model = VaultViewModel.live()
    @NSApplicationDelegateAdaptor(AppVaultAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(
            "AppVault",
            systemImage: model.protectedApps.isEmpty ? "lock.open" : "lock.shield",
            isInserted: Binding(
                get: { model.hasCompletedOnboarding },
                set: { _ in }
            )
        ) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("AppVault", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(colorScheme)
                .environmentObject(model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 900, height: 650)

        Settings { SettingsView(model: model) }
    }

    private var colorScheme: ColorScheme? {
        switch model.preferences.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppVaultAppDelegate: NSObject, NSApplicationDelegate {
    // Keep the model alive independently of the main window. A MenuBarExtra can remain
    // alive after its SwiftUI window is closed, so relying on a weak window reference left
    // AppVault running with no way to restore its main screen.
    var model: VaultViewModel?
    static var permitNextTermination = false
    private var recoveryWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Closing the main window is deliberately a lock event. Otherwise the vault remains
        // unlocked in memory and a Dock click can reveal it without asking again.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Let SwiftUI create WindowGroup first. This is only a safety net for macOS launches
        // where a prior closed/minimized window is not automatically restored.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.showVaultWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showVaultWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.permitNextTermination { Self.permitNextTermination = false; return .terminateNow }
        guard let model else { return .terminateCancel }
        model.requestQuit(systemRequest: true)
        return .terminateLater
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.styleMask.contains(.titled) else { return }
        model?.lockVault()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func showVaultWindow() {
        if let window = recoveryWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if let window = NSApp.windows.first(where: { window in
            !(window is NSPanel) && window.styleMask.contains(.titled)
        }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let model else { return }
        let host = NSHostingController(rootView: ContentView(model: model)
            .frame(minWidth: 760, minHeight: 520)
            .environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppVault"
        window.center()
        window.contentViewController = host
        window.isReleasedWhenClosed = false
        recoveryWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
