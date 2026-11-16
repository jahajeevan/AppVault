import XCTest
@testable import AppVault
import CryptoKit

final class AppVaultTests: XCTestCase {
    func testPasswordPolicy() { XCTAssertNotNil(PasswordPolicy.violation(for: "tooShort1A")); XCTAssertNil(PasswordPolicy.violation(for: "StrongPassword42")) }
    func testVerifierAcceptsOnlyOriginalPassword() { let verifier = PasswordSecurity.makeVerifier(password: "StrongPassword42", salt: Data(repeating: 7, count: 32), rounds: 2); XCTAssertTrue(PasswordSecurity.verify("StrongPassword42", verifier: verifier)); XCTAssertFalse(PasswordSecurity.verify("StrongPassword43", verifier: verifier)) }
    func testMemoryPersistence() throws { let store = MemorySecureStore(); let app = ProtectedApp(bundleIdentifier: "com.example.App", displayName: "Example", appURL: URL(fileURLWithPath: "/Applications/Example.app")); try store.save([app], key: "apps"); XCTAssertEqual(try store.load([ProtectedApp].self, key: "apps"), [app]) }
    @MainActor func testVaultStatePersistsAsOneLoadableState() {
        let store = MemorySecureStore()
        let app = DiscoverableApplication(url: URL(fileURLWithPath: "/Applications/Example.app"), bundleIdentifier: "com.example.App", name: "Example", icon: nil)
        let first = VaultViewModel(store: store); first.load(); first.add(app)
        XCTAssertTrue(first.completeInitialSetup(password: "StrongPassword42", confirmation: "StrongPassword42"))
        XCTAssertEqual(first.configuration.method, .password)
        XCTAssertTrue(first.verifyPassword("StrongPassword42"))
        let restored = VaultViewModel(store: store); restored.load()
        XCTAssertEqual(restored.protectedApps.map(\.bundleIdentifier), ["com.example.App"])
        XCTAssertTrue(restored.hasCompletedOnboarding)
    }
    @MainActor func testFreshVaultDoesNotNeedPersistedStateBeforePasswordCreation() {
        let model = VaultViewModel(store: MemorySecureStore(), shouldLoadPersistedState: false)
        model.load()
        XCTAssertFalse(model.hasCompletedOnboarding)
        XCTAssertNil(model.configuration.passwordVerifier)
    }
    func testGrantExpiry() { XCTAssertFalse(AppGrant(bundleIdentifier: "x", expiresAt: .now.addingTimeInterval(-1)).isValid); XCTAssertTrue(AppGrant(bundleIdentifier: "x", expiresAt: .now.addingTimeInterval(10)).isValid) }
    func testAppMatchingRequiresExactEnabledBundleIdentifier() {
        let app = ProtectedApp(bundleIdentifier: "com.example.App", displayName: "Example", appURL: URL(fileURLWithPath: "/Applications/Example.app"))
        XCTAssertEqual(ApplicationMatcher.protectedApp(for: "com.example.App", in: [app])?.id, app.id)
        XCTAssertNil(ApplicationMatcher.protectedApp(for: "com.example.AppHelper", in: [app]))
        var disabled = app; disabled.enabled = false; XCTAssertNil(ApplicationMatcher.protectedApp(for: "com.example.App", in: [disabled]))
    }
    func testPerAppPolicyInheritsOrOverridesGlobalConfiguration() {
        let global = SecurityConfiguration(method: .touchIDOrPassword, gracePeriod: 30)
        var app = ProtectedApp(bundleIdentifier: "com.example.App", displayName: "Example", appURL: URL(fileURLWithPath: "/Applications/Example.app"))
        XCTAssertEqual(app.effectiveMethod(global: global), .touchIDOrPassword); XCTAssertEqual(app.effectiveGracePeriod(global: global), 30)
        app.authenticationOverride = .password; app.gracePeriodOverride = 90
        XCTAssertEqual(app.effectiveMethod(global: global), .password); XCTAssertEqual(app.effectiveGracePeriod(global: global), 90)
    }
    func testLaunchGateCoalescesDuplicateNotifications() async {
        let gate = LaunchGate()
        let first = await gate.begin("com.example.App"); XCTAssertTrue(first)
        let duplicate = await gate.begin("com.example.App"); XCTAssertFalse(duplicate)
        await gate.end("com.example.App")
        let afterEnd = await gate.begin("com.example.App"); XCTAssertTrue(afterEnd)
    }
    func testLaunchGateTracksDifferentAppsIndependently() async {
        let gate = LaunchGate()
        let first = await gate.begin("net.whatsapp.WhatsApp")
        let second = await gate.begin("com.apple.Safari")
        XCTAssertTrue(first); XCTAssertTrue(second)
    }
    func testCoordinatorRevokesGrant() async {
        let coordinator = ProtectionCoordinator(); await coordinator.grant(bundleIdentifier: "x", duration: 60)
        let isGranted = await coordinator.hasValidGrant(for: "x"); XCTAssertTrue(isGranted); await coordinator.revoke(bundleIdentifier: "x")
        let isRevoked = await coordinator.hasValidGrant(for: "x"); XCTAssertFalse(isRevoked)
    }
    func testEnvelopeDoesNotExposePlaintext() throws { let key = SymmetricKey(size: .bits256); let envelope = try EncryptedSync.seal(["name": "Sensitive App"], key: key); XCTAssertFalse(String(data: envelope.ciphertext, encoding: .utf8)?.contains("Sensitive App") == true); XCTAssertEqual(try EncryptedSync.open(envelope, as: [String: String].self, key: key)["name"], "Sensitive App") }
}
