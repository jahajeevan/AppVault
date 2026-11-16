import Foundation
import LocalAuthentication

protocol Authenticating {
    func authenticate(reason: String, method: AuthenticationMethod) async throws
}

struct LocalAuthenticator: Authenticating {
    func authenticate(reason: String, method: AuthenticationMethod) async throws {
        guard method != .password else { throw VaultError.unavailable("Enter your AppVault password to continue.") }
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if method == .touchIDOrPassword { throw VaultError.unavailable("Touch ID is unavailable. Enter your AppVault password to continue.") }
            throw VaultError.unavailable("Touch ID is not available on this Mac.")
        }
        do { try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) }
        catch LAError.userCancel, LAError.appCancel, LAError.systemCancel { throw VaultError.authenticationCancelled }
        catch { throw VaultError.unavailable("Touch ID could not verify your identity.") }
    }
}

actor ProtectionCoordinator {
    private var grants: [String: AppGrant] = [:]
    func hasValidGrant(for bundleIdentifier: String) -> Bool { grants[bundleIdentifier]?.isValid == true }
    func grant(bundleIdentifier: String, duration: TimeInterval) { grants[bundleIdentifier] = AppGrant(bundleIdentifier: bundleIdentifier, expiresAt: .now.addingTimeInterval(duration)) }
    func revoke(bundleIdentifier: String) { grants.removeValue(forKey: bundleIdentifier) }
    func revokeAll() { grants.removeAll() }
}
