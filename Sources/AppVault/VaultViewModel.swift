import Foundation
import AppKit

@MainActor
final class VaultViewModel: ObservableObject {
    @Published private(set) var protectedApps: [ProtectedApp] = []
    @Published private(set) var configuration = SecurityConfiguration()
    @Published private(set) var preferences = GeneralPreferences()
    @Published private(set) var hasCompletedOnboarding = false
    @Published private(set) var isVaultUnlocked = false
    @Published private(set) var areMenuControlsUnlocked = false
    var needsVaultPassword: Bool { hasCompletedOnboarding && configuration.passwordVerifier == nil }
    @Published var statusMessage: String?
    @Published var monitorPaused = false
    @Published var searchText = ""
    let discovery: ApplicationDiscovering
    private let store: SecureStore
    private let shouldLoadPersistedState: Bool
    let protectionManager = ProtectionManager()
    private var monitor: LaunchMonitor?
    private static let stateKey = "vault-state-v4"
    private static let firstRunMarkerKey = "com.appvault.desktop.first-run-v4-complete"

    private struct PersistedState: Codable {
        var protectedApps: [ProtectedApp] = []
        var configuration = SecurityConfiguration()
        var preferences = GeneralPreferences()
        var hasCompletedOnboarding = false
    }

    init(store: SecureStore, discovery: ApplicationDiscovering = WorkspaceApplicationDiscovery(), shouldLoadPersistedState: Bool = true) { self.store = store; self.discovery = discovery; self.shouldLoadPersistedState = shouldLoadPersistedState; protectionManager.passwordVerification = { [weak self] password in self?.verifyPassword(password) == true } }
    static func live() -> VaultViewModel {
        // Avoid touching Keychain before the owner has explicitly created their vault.
        let configured = UserDefaults.standard.bool(forKey: Self.firstRunMarkerKey)
        let model = VaultViewModel(store: KeychainStore(), shouldLoadPersistedState: configured)
        model.load(); model.startMonitoring(); return model
    }
    func load() {
        guard shouldLoadPersistedState else { return }
        do {
            if let state = try store.load(PersistedState.self, key: Self.stateKey) { apply(state) }
        } catch { present(error) }
    }
    /// The vault password is mandatory even when Touch ID is selected. It is also the
    /// recovery path for Touch ID and protects AppVault's own administrative controls.
    func completeInitialSetup(password: String, confirmation: String) -> Bool {
        guard password == confirmation else { statusMessage = "The passwords do not match."; return false }
        if let violation = PasswordPolicy.violation(for: password) { statusMessage = violation; return false }
        // First-run deliberately does one thing: creates the vault password. The owner can
        // opt into Touch ID later from Vault security after setup is complete.
        configuration.method = .password
        configuration.passwordVerifier = PasswordSecurity.makeVerifier(password: password)
        hasCompletedOnboarding = true
        isVaultUnlocked = true
        do { try LoginItemService.setEnabled(true); preferences.launchAtLogin = true }
        catch { statusMessage = "Vault created, but macOS did not enable launch at login. Turn it on in Settings." }
        guard persistState() else { return false }
        UserDefaults.standard.set(true, forKey: Self.firstRunMarkerKey)
        if statusMessage == nil { statusMessage = "Your vault is ready." }
        return true
    }
    func savePreferences(_ preferences: GeneralPreferences) {
        do {
            if preferences.launchAtLogin != self.preferences.launchAtLogin { try LoginItemService.setEnabled(preferences.launchAtLogin) }
            self.preferences = preferences; guard persistState() else { return }; statusMessage = "Preferences saved."
        } catch { present(error) }
    }
    func saveConfiguration(method: AuthenticationMethod, password: String?, relockWhenInactive: Bool? = nil) -> Bool {
        if let password, let violation = PasswordPolicy.violation(for: password) { statusMessage = violation; return false }
        if password == nil, configuration.passwordVerifier == nil { statusMessage = VaultError.passwordNotConfigured.localizedDescription; return false }
        configuration.method = method
        if let relockWhenInactive { configuration.relockWhenInactive = relockWhenInactive }
        if let password { configuration.passwordVerifier = PasswordSecurity.makeVerifier(password: password) }
        guard persistState() else { return false }; statusMessage = "Security settings saved."; return true
    }
    func add(_ app: DiscoverableApplication) {
        guard !app.bundleIdentifier.isEmpty else { statusMessage = VaultError.invalidApplication.localizedDescription; return }
        guard !protectedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { statusMessage = "This app is already protected."; return }
        protectedApps.append(ProtectedApp(bundleIdentifier: app.bundleIdentifier, displayName: app.name, appURL: app.url)); _ = persistState()
    }
    func toggle(_ app: ProtectedApp) { guard let index = protectedApps.firstIndex(of: app) else { return }; protectedApps[index].enabled.toggle(); protectedApps[index].updatedAt = .now; _ = persistState() }
    func update(_ app: ProtectedApp, authenticationOverride: AuthenticationMethod?, gracePeriodOverride: TimeInterval?) {
        guard let index = protectedApps.firstIndex(of: app) else { return }
        protectedApps[index].authenticationOverride = authenticationOverride
        protectedApps[index].gracePeriodOverride = gracePeriodOverride
        protectedApps[index].updatedAt = .now
        _ = persistState(); statusMessage = "Updated protection for \(app.displayName)."
    }
    func remove(_ app: ProtectedApp) { protectedApps.removeAll { $0.id == app.id }; _ = persistState(); protectionManager.updateRegistry(apps: protectedApps, configuration: configuration) }
    func verifyPassword(_ password: String) -> Bool { guard let verifier = configuration.passwordVerifier else { return false }; return PasswordSecurity.verify(password, verifier: verifier) }
    func unlockVault(password: String) -> Bool {
        guard verifyPassword(password) else { statusMessage = "That vault password was not accepted."; return false }
        isVaultUnlocked = true
        statusMessage = nil
        return true
    }
    func lockVault() { isVaultUnlocked = false; areMenuControlsUnlocked = false }
    func unlockMenuControls(password: String) -> Bool {
        guard verifyPassword(password) else { statusMessage = "That vault password was not accepted."; return false }
        areMenuControlsUnlocked = true
        isVaultUnlocked = true
        statusMessage = nil
        return true
    }
    func lockMenuControls() { areMenuControlsUnlocked = false }
    func pauseMonitoringFromUnlockedMenu() { monitorPaused = true; statusMessage = "Protection monitoring is paused." }
    func quitFromUnlockedMenu() { AppVaultAppDelegate.permitNextTermination = true; NSApp.terminate(nil) }
    func requestQuit(systemRequest: Bool = false) {
        do {
            let password = try PasswordPrompt.request(reason: "Enter your AppVault password to quit protection.")
            guard verifyPassword(password) else { statusMessage = "AppVault stays running: password not accepted."; if systemRequest { NSApp.reply(toApplicationShouldTerminate: false) }; return }
            if systemRequest { NSApp.reply(toApplicationShouldTerminate: true) }
            else { AppVaultAppDelegate.permitNextTermination = true; NSApp.terminate(nil) }
        } catch { if systemRequest { NSApp.reply(toApplicationShouldTerminate: false) } }
    }
    func authenticate(reason: String) async throws { try await authenticate(reason: reason, method: configuration.method) }
    func authenticate(reason: String, method: AuthenticationMethod) async throws {
        switch method {
        case .touchID:
            try await LocalAuthenticator().authenticate(reason: reason, method: .touchID)
        case .password:
            guard verifyPassword(try PasswordPrompt.request(reason: reason)) else { throw VaultError.invalidPassword }
        case .touchIDOrPassword:
            do { try await LocalAuthenticator().authenticate(reason: reason, method: .touchIDOrPassword) }
            catch VaultError.authenticationCancelled { throw VaultError.authenticationCancelled }
            catch { guard verifyPassword(try PasswordPrompt.request(reason: reason)) else { throw VaultError.invalidPassword } }
        }
    }
    func pauseMonitoring(afterAuthenticated: Bool) async {
        guard afterAuthenticated else { statusMessage = "Authenticate before pausing protection."; return }
        monitorPaused = true; statusMessage = "Protection monitoring is paused."
    }
    func resumeMonitoring() { monitorPaused = false; statusMessage = "Protection monitoring resumed." }
    func displayedApps() -> [ProtectedApp] { let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines); return protectedApps.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
    private func startMonitoring() { protectionManager.updateRegistry(apps: protectedApps, configuration: configuration); monitor = LaunchMonitor(onActivate: { [weak self] app in guard let self, !self.monitorPaused else { return }; await self.protectionManager.handleActivation(app) }, onDeactivate: { [weak self] app in await self?.protectionManager.handleDeactivation(app) }, onTerminate: { [weak self] app in await self?.protectionManager.handleTermination(app) }); monitor?.start() }
    @discardableResult private func persistState() -> Bool {
        do { try store.save(PersistedState(protectedApps: protectedApps, configuration: configuration, preferences: preferences, hasCompletedOnboarding: hasCompletedOnboarding), key: Self.stateKey); protectionManager.updateRegistry(apps: protectedApps, configuration: configuration); return true }
        catch { present(error); return false }
    }
    private func apply(_ state: PersistedState) { protectedApps = state.protectedApps; configuration = state.configuration; preferences = state.preferences; hasCompletedOnboarding = state.hasCompletedOnboarding; isVaultUnlocked = false; areMenuControlsUnlocked = false }
    private func present(_ error: Error) { statusMessage = error.localizedDescription }
}
