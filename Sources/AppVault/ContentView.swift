import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: VaultViewModel
    @State private var section: Section? = .apps
    @State private var showingPicker = false
    enum Section: Hashable { case apps, security, privacy, about }
    var body: some View {
        if !model.hasCompletedOnboarding || model.needsVaultPassword { OnboardingView(model: model) }
        else if !model.isVaultUnlocked { VaultAccessView(model: model) }
        else { NavigationSplitView {
            List(selection: $section) {
                SwiftUI.Section("AppVault") { Label("Protected Apps", systemImage: "lock.shield").tag(Section.apps) }
                SwiftUI.Section("Security") { Label("Authentication", systemImage: "key").tag(Section.security); Label("Privacy", systemImage: "hand.raised").tag(Section.privacy) }
                SwiftUI.Section("Info") { Label("About", systemImage: "info.circle").tag(Section.about) }
            }.listStyle(.sidebar).navigationTitle("AppVault")
        } detail: {
            switch section ?? .apps { case .apps: ProtectedAppsPage(model: model, showingPicker: $showingPicker); case .security: SecurityPage(model: model); case .privacy: PrivacyPage(); case .about: AboutPage() }
        }.background(WorkspaceBackdrop()).toolbar { if section == .apps { Button("Add protected app", systemImage: "plus") { showingPicker = true } } }.sheet(isPresented: $showingPicker) { AppPicker(model: model) } }
    }
}

struct ProtectedAppsPage: View {
    @ObservedObject var model: VaultViewModel; @Binding var showingPicker: Bool; @State private var editing: ProtectedApp?
    var body: some View { VStack(alignment: .leading, spacing: 18) {
        Header(title: "Protected Apps", subtitle: "Apps that require authentication before they can be opened.") { Text("\(model.protectedApps.filter(\.enabled).count) protected").foregroundStyle(.secondary) }
        TextField("Search protected apps", text: $model.searchText).textFieldStyle(.roundedBorder).frame(maxWidth: 460)
        if model.displayedApps().isEmpty { ContentUnavailableView("No protected apps", systemImage: "lock.open", description: Text("Add an app to require authentication before it becomes active.")); Spacer() }
        else { List(model.displayedApps()) { app in AppRow(app: app, model: model, editing: $editing) }.listStyle(.inset).frame(maxWidth: 860, maxHeight: .infinity) }
        if let message = model.statusMessage { Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).sheet(item: $editing) { AppProtectionEditor(model: model, app: $0) } }
}

private struct Header<Trailing: View>: View { let title: String; let subtitle: String; @ViewBuilder let trailing: () -> Trailing; var body: some View { HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 28, weight: .semibold)); Text(subtitle).foregroundStyle(.secondary) }; Spacer(); trailing() } } }
private struct AppRow: View { let app: ProtectedApp; @ObservedObject var model: VaultViewModel; @Binding var editing: ProtectedApp?; var body: some View { HStack(spacing: 14) { Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path)).resizable().frame(width: 38, height: 38); VStack(alignment: .leading, spacing: 3) { Text(app.displayName).font(.headline); Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary) }; Spacer(); Label(app.enabled ? "Protected" : "Paused", systemImage: app.enabled ? "lock.fill" : "pause.circle").foregroundColor(app.enabled ? .accentColor : .secondary); Menu { Button("Edit protection") { editing = app }; Button(app.enabled ? "Pause protection" : "Enable protection") { model.toggle(app) }; Divider(); Button("Remove from Protected Apps", role: .destructive) { model.remove(app) } } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }.menuStyle(.borderlessButton) }.padding(.vertical, 8) } }

struct AppPicker: View { @Environment(\.dismiss) private var dismiss; @ObservedObject var model: VaultViewModel; @State private var query = ""; @State private var apps: [DiscoverableApplication] = []; @State private var selected: DiscoverableApplication?; var filtered: [DiscoverableApplication] { apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) } }; var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Add Protected App").font(.title2.weight(.semibold)); Text("Choose an application to protect.").foregroundStyle(.secondary); TextField("Search applications", text: $query).textFieldStyle(.roundedBorder); List(filtered, selection: $selected) { app in HStack { Image(nsImage: app.icon ?? NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28); VStack(alignment: .leading) { Text(app.name); Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary) } }.tag(app) }; HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add") { if let selected { model.add(selected); dismiss() } }.keyboardShortcut(.defaultAction).disabled(selected == nil) } }.padding(24).frame(width: 600, height: 540).onAppear { apps = model.discovery.applications() } } }

struct SecurityPage: View { @ObservedObject var model: VaultViewModel; @State private var method: AuthenticationMethod; @State private var password = ""; @State private var relock: Bool; init(model: VaultViewModel) { self.model = model; _method = State(initialValue: model.configuration.method); _relock = State(initialValue: model.configuration.relockWhenInactive) }; var body: some View { VStack(alignment: .leading, spacing: 24) { Header(title: "Vault security", subtitle: "Your AppVault password secures both the vault and every protected app.") { EmptyView() }; SettingsSection("How protected apps unlock") { Picker("Authentication", selection: $method) { Text("Touch ID").tag(AuthenticationMethod.touchID); Text("Password").tag(AuthenticationMethod.password); Text("Touch ID or password").tag(AuthenticationMethod.touchIDOrPassword) }.pickerStyle(.radioGroup); SecureField("New vault password (leave blank to keep current)", text: $password).textFieldStyle(.roundedBorder); Text("Changing this password also changes the password used to unlock AppVault and its menu controls. Only a salted verifier is held in your Keychain.").font(.caption).foregroundStyle(.secondary) }; SettingsSection("Lock behavior") { Toggle("Lock again when you leave a protected app", isOn: $relock); Text("The immersive guard covers the screen while authentication is required. macOS-reserved system shortcuts remain outside a normal app's control.").font(.caption).foregroundStyle(.secondary) }; HStack { Spacer(); Button("Save security changes") { _ = model.saveConfiguration(method: method, password: password.isEmpty ? nil : password, relockWhenInactive: relock) }.buttonStyle(.borderedProminent) } }.padding(28).frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading) } }
private struct SettingsSection<Content: View>: View { let title: String; @ViewBuilder let content: () -> Content; init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }; var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); Divider(); content() } } }

struct PrivacyPage: View { var body: some View { VStack(alignment: .leading, spacing: 24) { Header(title: "Privacy", subtitle: "AppVault protects app access without collecting your data.") { EmptyView() }; SettingsSection("App monitoring") { Text("AppVault observes standard macOS app activity notifications to protect the apps you select."); Text("It does not request Accessibility, Screen Recording, Full Disk Access, or network permissions.").foregroundStyle(.secondary) }; SettingsSection("Your data") { LabeledContent("Passwords", value: "Never stored in plaintext"); LabeledContent("Touch ID", value: "Handled only by macOS"); LabeledContent("Sync", value: "Off by default") }; SettingsSection("Important limitation") { Text("AppVault is a practical user-space guard, not an unbypassable OS security boundary. It immediately hides and redirects protected apps after macOS activation notifications.").foregroundStyle(.secondary) } }.padding(28).frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading) } }
struct AboutPage: View { var body: some View { VStack(alignment: .leading, spacing: 20) { Spacer().frame(height: 32); Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(.tint); Text("AppVault").font(.system(size: 34, weight: .bold)); Text("Protect the apps that matter.").font(.title3).foregroundStyle(.secondary); Text("Version 1.0.0").foregroundStyle(.secondary); Divider(); Text("Privacy-focused application protection for macOS.").foregroundStyle(.secondary); Spacer() }.padding(42).frame(maxWidth: .infinity, alignment: .leading) } }
struct OnboardingView: View {
    @ObservedObject var model: VaultViewModel
    @State private var password = ""
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VaultMark(size: 62)
            Text("Build your vault").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Create the single password that secures AppVault and the apps you choose to protect.").foregroundStyle(.secondary).frame(maxWidth: 530, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                Text("Vault password").font(.headline)
                SecureField("Create a strong password", text: $password).textFieldStyle(.roundedBorder)
                SecureField("Confirm vault password", text: $confirmation).textFieldStyle(.roundedBorder)
                Text("The password itself is never saved. AppVault stores only a salted verifier in your Keychain. You can enable Touch ID later in Vault security.").font(.caption).foregroundStyle(.secondary)
            }.padding(22).background(.bar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let message = model.statusMessage { Text(message).font(.callout).foregroundStyle(.red) }
            Button("Create AppVault") { _ = model.completeInitialSetup(password: password, confirmation: confirmation) }.buttonStyle(.borderedProminent).disabled(password.isEmpty || confirmation.isEmpty)
            Text("AppVault is a practical user-space guard, not an unbypassable macOS security boundary.").font(.caption).foregroundStyle(.secondary)
        }.padding(44).frame(maxWidth: 620, maxHeight: .infinity, alignment: .center).background(WorkspaceBackdrop())
    }
}

struct VaultAccessView: View {
    @ObservedObject var model: VaultViewModel
    @State private var password = ""
    var body: some View {
        VStack(spacing: 22) {
            VaultMark(size: 70)
            Text("AppVault is locked").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Enter your vault password to manage protection.").foregroundStyle(.secondary)
            SecureField("Vault password", text: $password).textFieldStyle(.roundedBorder).frame(width: 300).onSubmit { if model.unlockVault(password: password) { password = "" } }
            Button("Open vault") { if model.unlockVault(password: password) { password = "" } }.buttonStyle(.borderedProminent).disabled(password.isEmpty)
            if let message = model.statusMessage { Text(message).font(.callout).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(WorkspaceBackdrop())
    }
}
struct AppProtectionEditor: View { @Environment(\.dismiss) private var dismiss; @ObservedObject var model: VaultViewModel; let app: ProtectedApp; @State private var inheritedAuth: Bool; @State private var method: AuthenticationMethod; @State private var inheritedGrace: Bool; @State private var grace: Double; init(model: VaultViewModel, app: ProtectedApp) { self.model = model; self.app = app; _inheritedAuth = State(initialValue: app.authenticationOverride == nil); _method = State(initialValue: app.authenticationOverride ?? model.configuration.method); _inheritedGrace = State(initialValue: app.gracePeriodOverride == nil); _grace = State(initialValue: app.gracePeriodOverride ?? model.configuration.gracePeriod) }; var body: some View { VStack(alignment: .leading, spacing: 18) { Text("Edit \(app.displayName)").font(.title2.weight(.semibold)); Toggle("Use global authentication", isOn: $inheritedAuth); if !inheritedAuth { Picker("Authentication", selection: $method) { Text("Touch ID only").tag(AuthenticationMethod.touchID); Text("Password only").tag(AuthenticationMethod.password); Text("Touch ID or password").tag(AuthenticationMethod.touchIDOrPassword) } }; Toggle("Use global grace period", isOn: $inheritedGrace); if !inheritedGrace { HStack { Text("Grace period"); Slider(value: $grace, in: 0...300, step: 15); Text("\(Int(grace)) sec") } }; HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save changes") { model.update(app, authenticationOverride: inheritedAuth ? nil : method, gracePeriodOverride: inheritedGrace ? nil : grace); dismiss() }.buttonStyle(.borderedProminent) } }.padding(24).frame(width: 460) } }
struct MenuBarView: View {
    @ObservedObject var model: VaultViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { VaultMark(size: 24); Text("AppVault").font(.headline) }
            Label(model.monitorPaused ? "Protection paused" : "Protection running", systemImage: model.monitorPaused ? "pause.circle" : "lock.fill").foregroundStyle(model.monitorPaused ? .orange : .secondary)
            Divider()
            if !model.areMenuControlsUnlocked {
                Text("Vault controls are sealed.").font(.caption).foregroundStyle(.secondary)
                SecureField("Vault password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if model.unlockMenuControls(password: password) { password = "" } }
                Button("Unseal controls") { if model.unlockMenuControls(password: password) { password = "" } }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
                if let message = model.statusMessage { Text(message).font(.caption).foregroundStyle(.red) }
            } else {
                Button(model.monitorPaused ? "Resume protection" : "Pause protection") { if model.monitorPaused { model.resumeMonitoring() } else { model.pauseMonitoringFromUnlockedMenu() } }
                Button("Open AppVault") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Divider()
                Button("Quit AppVault") { model.quitFromUnlockedMenu() }
            }
        }.padding().frame(width: 260).onDisappear { model.lockMenuControls() }
    }
}

struct WorkspaceBackdrop: View { var body: some View { ZStack { Color(red: 0.075, green: 0.07, blue: 0.065); LinearGradient(colors: [Color(red: 0.16, green: 0.115, blue: 0.075).opacity(0.45), .clear], startPoint: .topLeading, endPoint: .bottomTrailing); Rectangle().stroke(Color.white.opacity(0.035), lineWidth: 1).padding(32) }.ignoresSafeArea() } }
