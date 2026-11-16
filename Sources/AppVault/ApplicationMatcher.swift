import Foundation

enum ApplicationMatcher {
    /// Bundle identity is authoritative; path is deliberately not used because app updates may move it.
    static func protectedApp(for bundleIdentifier: String?, in protectedApps: [ProtectedApp]) -> ProtectedApp? {
        guard let bundleIdentifier else { return nil }
        return protectedApps.first { $0.enabled && $0.bundleIdentifier == bundleIdentifier }
    }
}
