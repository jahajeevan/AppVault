import Foundation
import Security

struct ProtectedApp: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var appURL: URL
    var enabled: Bool
    /// Nil inherits the global security setting; a value tightens or customizes this app's flow.
    var authenticationOverride: AuthenticationMethod?
    /// Nil inherits the global grace period.
    var gracePeriodOverride: TimeInterval?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), bundleIdentifier: String, displayName: String, appURL: URL, enabled: Bool = true, authenticationOverride: AuthenticationMethod? = nil, gracePeriodOverride: TimeInterval? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.bundleIdentifier = bundleIdentifier; self.displayName = displayName
        self.appURL = appURL; self.enabled = enabled; self.authenticationOverride = authenticationOverride; self.gracePeriodOverride = gracePeriodOverride; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    func effectiveMethod(global: SecurityConfiguration) -> AuthenticationMethod { authenticationOverride ?? global.method }
    func effectiveGracePeriod(global: SecurityConfiguration) -> TimeInterval { gracePeriodOverride ?? global.gracePeriod }
}

enum AuthenticationMethod: String, Codable, CaseIterable, Sendable { case touchID, password, touchIDOrPassword }

struct SecurityConfiguration: Codable, Sendable {
    var method: AuthenticationMethod = .touchIDOrPassword
    var gracePeriod: TimeInterval = 30
    /// When enabled, leaving an unlocked protected app immediately revokes its grant.
    var relockWhenInactive = true
    /// Uses AppVault's immersive lock surface while authentication is pending.
    var immersiveLockScreen = true
    var passwordVerifier: PasswordVerifier?
}

enum ProtectionState: Equatable, Sendable { case locked, authenticating, unlocked }

struct LockSession: Identifiable, Equatable {
    enum Phase: Equatable { case ready, checkingTouchID, password, failed(String) }
    let app: ProtectedApp
    let method: AuthenticationMethod
    var phase: Phase
    var id: String { app.bundleIdentifier }
}

struct GeneralPreferences: Codable, Sendable {
    /// AppVault registers itself after first setup so protection resumes after a login.
    var launchAtLogin = true
    var showInDock = false
    var appearance: Appearance = .system
    enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
}

struct PasswordVerifier: Codable, Equatable, Sendable {
    let salt: Data
    let digest: Data
    let rounds: Int
    static let currentRounds = 210_000
}

struct AppGrant: Codable, Sendable {
    var bundleIdentifier: String
    var expiresAt: Date
    var isValid: Bool { expiresAt > .now }
}

enum VaultError: LocalizedError, Equatable {
    case keychain(OSStatus), passwordNotConfigured, invalidPassword, authenticationCancelled, unavailable(String), invalidApplication
    var errorDescription: String? {
        switch self {
        case .keychain: return "AppVault could not securely access its Keychain data."
        case .passwordNotConfigured: return "Set a password before using password protection."
        case .invalidPassword: return "The password was not accepted."
        case .authenticationCancelled: return "Authentication was cancelled."
        case .unavailable(let message): return message
        case .invalidApplication: return "That application cannot be protected."
        }
    }
}
