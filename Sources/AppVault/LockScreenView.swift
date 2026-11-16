import SwiftUI
import AppKit

/// A compact security checkpoint that expands naturally into the immersive lock surface.
struct LockScreenView: View {
    @ObservedObject var manager: ProtectionManager
    @State private var password = ""
    @FocusState private var passwordIsFocused: Bool

    var body: some View {
        ZStack {
            LockBackdrop()
            if let session = manager.activeLock { lockContents(session) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lockContents(_ session: LockSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandGlyph(size: 26)
                Text("AppVault").font(.headline.weight(.semibold))
                Spacer()
                Label("Protected", systemImage: "lock.fill").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }.padding(.bottom, 44)

            appIdentity(session)
            VStack(spacing: 10) {
                Text("Unlock \(session.app.displayName)").font(.system(size: 28, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                Text("Use Touch ID or your AppVault password to continue.").font(.callout).foregroundStyle(.secondary)
            }.padding(.top, 24)

            authenticationControls(session).frame(maxWidth: 340).padding(.top, 32)
            Spacer(minLength: 30)
            Text("Protection stays on this Mac")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 38).padding(.vertical, 28).frame(width: 520, height: 560)
        .background {
            MacMaterial(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
        }
        .shadow(color: .black.opacity(0.34), radius: 30, y: 18).padding(22)
    }

    private func appIdentity(_ session: LockSession) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.32)).frame(width: 82, height: 82)
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
            Image(nsImage: NSWorkspace.shared.icon(forFile: session.app.appURL.path)).resizable().interpolation(.high).frame(width: 56, height: 56)
        }
    }

    @ViewBuilder private func authenticationControls(_ session: LockSession) -> some View {
        switch session.phase {
        case .ready, .checkingTouchID:
            VStack(spacing: 14) {
                ProgressView().controlSize(.small)
                Text("Waiting for Touch ID…").font(.callout).foregroundStyle(.secondary)
                if session.method == .touchIDOrPassword { Button("Use password instead") { manager.usePassword() }.buttonStyle(.link) }
            }
        case .password:
            passwordForm(session)
        case .failed(let message):
            VStack(spacing: 14) {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
                if session.method == .password { Button("Try password again") { manager.usePassword() }.buttonStyle(AccentButtonStyle()) }
                else { Button("Use password") { manager.usePassword() }.buttonStyle(AccentButtonStyle()); Button("Try Touch ID again") { manager.retryTouchID() }.buttonStyle(.link) }
            }
        }
    }

    private func passwordForm(_ session: LockSession) -> some View {
        VStack(spacing: 14) {
            SecureField("AppVault password", text: $password)
                .textFieldStyle(.plain).padding(.horizontal, 15).padding(.vertical, 13)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(passwordIsFocused ? Color.accentColor : .white.opacity(0.16), lineWidth: passwordIsFocused ? 2 : 1) }
                .focused($passwordIsFocused).onSubmit { submitPassword() }.accessibilityLabel("AppVault password")
            Button("Unlock \(session.app.displayName)") { submitPassword() }.buttonStyle(AccentButtonStyle()).disabled(password.isEmpty)
            if session.method == .touchIDOrPassword { Button("Use Touch ID instead") { manager.retryTouchID() }.buttonStyle(.link) }
            Button("Cancel") { manager.cancel() }.buttonStyle(.plain).foregroundStyle(.secondary)
        }.onAppear { DispatchQueue.main.async { passwordIsFocused = true } }
    }

    private func submitPassword() {
        guard !password.isEmpty else { return }
        let attemptedPassword = password; password = ""
        Task { await manager.submitPassword(attemptedPassword) }
    }
}

private struct LockBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            MacMaterial(material: .underWindowBackground)
        }.ignoresSafeArea()
    }
}

private struct BrandGlyph: View {
    let size: CGFloat
    var body: some View {
        ZStack { RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color(red: 0.91, green: 0.28, blue: 0.2)); Image(systemName: "key.fill").font(.system(size: size * 0.48, weight: .bold)).foregroundStyle(.black.opacity(0.78)) }
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Shared compact brand mark for the regular vault and menu-bar surfaces.
struct VaultMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(red: 0.91, green: 0.28, blue: 0.2))
            Image(systemName: "key.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.black.opacity(0.78))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MacMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
