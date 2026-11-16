import Foundation
import AppKit

struct DiscoverableApplication: Identifiable, Hashable {
    let url: URL; let bundleIdentifier: String; let name: String; let icon: NSImage?
    var id: String { bundleIdentifier }
}

protocol ApplicationDiscovering {
    func applications() -> [DiscoverableApplication]
}

struct WorkspaceApplicationDiscovery: ApplicationDiscovering {
    func applications() -> [DiscoverableApplication] {
        let manager = FileManager.default
        let roots = manager.urls(for: .applicationDirectory, in: .userDomainMask) + manager.urls(for: .applicationDirectory, in: .localDomainMask) + [URL(fileURLWithPath: "/System/Applications", isDirectory: true)]
        let candidates = roots.flatMap { root in
            let direct = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let nested = direct.flatMap { child in
                (try? manager.contentsOfDirectory(at: child, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            }
            return direct + nested
        }
        var seen = Set<String>()
        return candidates.compactMap { url in
                guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
                guard id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return DiscoverableApplication(url: url, bundleIdentifier: id, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent, icon: NSWorkspace.shared.icon(forFile: url.path))
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class LaunchMonitor {
    private var observers: [NSObjectProtocol] = []
    private let gate = LaunchGate()
    private let onActivate: @MainActor (NSRunningApplication) async -> Void
    private let onDeactivate: @MainActor (NSRunningApplication) async -> Void
    private let onTerminate: @MainActor (NSRunningApplication) async -> Void
    init(onActivate: @escaping @MainActor (NSRunningApplication) async -> Void, onDeactivate: @escaping @MainActor (NSRunningApplication) async -> Void, onTerminate: @escaping @MainActor (NSRunningApplication) async -> Void) { self.onActivate = onActivate; self.onDeactivate = onDeactivate; self.onTerminate = onTerminate }
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let observeActivate: (Notification) -> Void = { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let self else { return }
            Task { @MainActor in
                guard let id = app.bundleIdentifier, await self.gate.begin(id) else { return }
                await self.onActivate(app)
                await self.gate.end(id)
            }
        }
        // Launch protects a newly created process; activation also covers an app that was already running.
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: observeActivate),
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: observeActivate),
            center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { Task { @MainActor in await self?.onDeactivate(app) } } },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { Task { @MainActor in await self?.onTerminate(app) } } }
        ]
    }
    func stop() { let center = NSWorkspace.shared.notificationCenter; observers.forEach(center.removeObserver); observers.removeAll(); Task { await gate.clear() } }
    deinit { MainActor.assumeIsolated { stop() } }
}

/// Serializes duplicate launch notifications for the same bundle until its authentication flow ends.
actor LaunchGate {
    private var pending = Set<String>()
    func begin(_ bundleIdentifier: String) -> Bool { pending.insert(bundleIdentifier).inserted }
    func end(_ bundleIdentifier: String) { pending.remove(bundleIdentifier) }
    func clear() { pending.removeAll() }
}
