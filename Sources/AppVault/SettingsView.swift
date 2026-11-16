import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: VaultViewModel
    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gear") }
            AuthenticationSettings(model: model).tabItem { Label("Authentication", systemImage: "key") }
            ProtectedAppsSettings(model: model).tabItem { Label("Protected Apps", systemImage: "lock.shield") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            AppearanceSettings(model: model).tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            AdvancedSettings(model: model).tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }.padding(20).frame(width: 620, height: 430)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: VaultViewModel
    @State private var launchAtLogin: Bool
    init(model: VaultViewModel) { self.model = model; _launchAtLogin = State(initialValue: model.preferences.launchAtLogin) }
    var body: some View { Form { Toggle("Launch AppVault when I log in", isOn: $launchAtLogin); Text("AppVault enables this during first setup. macOS may list it under Login Items.").font(.caption).foregroundStyle(.secondary); Button("Save") { var p = model.preferences; p.launchAtLogin = launchAtLogin; model.savePreferences(p) } }.formStyle(.grouped) }
}

private struct AuthenticationSettings: View {
    @ObservedObject var model: VaultViewModel
    @State private var method: AuthenticationMethod
    @State private var password = ""
    init(model: VaultViewModel) { self.model = model; _method = State(initialValue: model.configuration.method) }
    var body: some View { Form { Picker("Unlock method", selection: $method) { Text("Touch ID only").tag(AuthenticationMethod.touchID); Text("Password only").tag(AuthenticationMethod.password); Text("Touch ID or password").tag(AuthenticationMethod.touchIDOrPassword) }; if method != .touchID { SecureField("New password (leave blank to keep current)", text: $password); Text("A new password rotates the Keychain-only salted verifier.").font(.caption).foregroundStyle(.secondary) }; Button("Save authentication") { _ = model.saveConfiguration(method: method, password: password.isEmpty ? nil : password) } }.formStyle(.grouped) }
}

private struct ProtectedAppsSettings: View {
    @ObservedObject var model: VaultViewModel
    var body: some View { List(model.displayedApps()) { app in HStack { Text(app.displayName); Spacer(); Text(app.enabled ? "Enabled" : "Disabled").foregroundStyle(.secondary); Button("Remove", role: .destructive) { model.remove(app) } } }.overlay { if model.protectedApps.isEmpty { ContentUnavailableView("No protected apps", systemImage: "lock.open") } } }
}

struct PrivacySettings: View {
    var body: some View { Form { LabeledContent("Network") { Text("Disabled by default") }; LabeledContent("Passwords") { Text("Never stored in plaintext") }; LabeledContent("Biometrics") { Text("Never accessed or stored") }; LabeledContent("Sync") { Text("Not configured") }; Text("If optional sync is added, AppVault uploads only client-side encrypted opaque envelopes. A provider cannot read protected app metadata, passwords, password verifiers, Keychain data, or Touch ID data.").font(.caption).foregroundStyle(.secondary) }.formStyle(.grouped) }
}

private struct AppearanceSettings: View {
    @ObservedObject var model: VaultViewModel
    @State private var appearance: GeneralPreferences.Appearance
    init(model: VaultViewModel) { self.model = model; _appearance = State(initialValue: model.preferences.appearance) }
    var body: some View { Form { Picker("Appearance", selection: $appearance) { Text("System").tag(GeneralPreferences.Appearance.system); Text("Light").tag(GeneralPreferences.Appearance.light); Text("Dark").tag(GeneralPreferences.Appearance.dark) }; Button("Save") { var p = model.preferences; p.appearance = appearance; model.savePreferences(p) } }.formStyle(.grouped) }
}

private struct AdvancedSettings: View {
    @ObservedObject var model: VaultViewModel
    var body: some View { Form { LabeledContent("Launch monitor") { Text(model.monitorPaused ? "Paused" : "Active") }; Button(model.monitorPaused ? "Resume monitoring" : "Pause monitoring") { if model.monitorPaused { model.resumeMonitoring() } else { Task { try? await model.authenticate(reason: "Pause AppVault protection"); await model.pauseMonitoring(afterAuthenticated: true) } } }; Text("No accessibility, screen recording, or Full Disk Access permissions are requested. Some apps can launch before macOS delivers an observable launch event; this is a macOS user-space limitation.").font(.caption).foregroundStyle(.secondary) }.formStyle(.grouped) }
}

struct AboutSettings: View {
    var body: some View { VStack(alignment: .leading, spacing: 10) { Text("AppVault").font(.title.bold()); Text("Version 1.0.0"); Text("A privacy-first, offline macOS menu-bar app.").foregroundStyle(.secondary); Divider(); Text("AppVault is not an unbypassable security boundary. See the in-app onboarding and README for limitations.").font(.caption).foregroundStyle(.secondary); Spacer() }.frame(maxWidth: .infinity, alignment: .leading) }
}
