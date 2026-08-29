import SwiftUI
import AuthenticationServices

/// First-launch welcome.
///
/// Signing in is optional and stays optional: 3DPrintKit is a fully offline
/// app, and an account only adds multi-device sync. The screen therefore says
/// what the app does before it asks for anything, and "Continue Without an
/// Account" is a real, equally reachable choice rather than a buried escape.
///
/// The completion flag is `@AppStorage` rather than `AppSettings`, whose
/// properties are all computed over `UserDefaults` and so are not tracked by
/// `@Observable`.
struct WelcomeView: View {
    /// Called when the user has either signed in or chosen to continue offline.
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auth = AuthManager.shared
    @State private var showServerField = false
    @State private var apiURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? PrintKitAPIConfiguration.defaultBaseURL
    @State private var appeared = false

    private var normalizedURL: String {
        apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSigningIn: Bool {
        if case .signingIn = auth.state { return true }
        return false
    }

    private var materialCount: Int { MaterialLibrary.shared.materials.count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PK.Spacing.xl) {
                    header
                    features
                    if showServerField { serverField }
                }
                .padding(.horizontal, PK.Spacing.xl)
                .padding(.top, PK.Spacing.xl)
                .padding(.bottom, PK.Spacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
        }
        .background(Color(.systemGroupedBackground))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: appeared)
        .onAppear { appeared = true }
        .onChange(of: auth.state) { _, state in
            if case .signedIn = state { onFinish() }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: PK.Spacing.lg) {
            // The app's own spool mark rather than a generic symbol.
            SpoolRingView(fraction: 0.72, filamentColor: .accentColor, lineWidth: 13)
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)

            VStack(spacing: PK.Spacing.sm) {
                Text("3DPrintKit")
                    .font(.largeTitle.bold())
                Text("Track your filament, printers, and print history — entirely on your iPhone.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Features

    private var features: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.lg) {
            FeatureRow(symbol: "circle.dashed.inset.filled",
                       title: "Every spool accounted for",
                       detail: "Weight, drying, storage, NFC tags, and what each print actually cost you.")
            FeatureRow(symbol: "books.vertical.fill",
                       title: "\(materialCount) materials, offline",
                       detail: "Nozzle and bed temperatures, drying guidance, and printer compatibility — no signal needed.")
            FeatureRow(symbol: "checkmark.shield.fill",
                       title: "Catch problems before they print",
                       detail: "A readiness check for the wet spool or wrong nozzle you'd rather not find 14 hours in.")
        }
    }

    // MARK: Optional server

    private var serverField: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.sm) {
            Text("3DPrintKit server")
                .font(.subheadline.weight(.medium))
            TextField("https://api.example.com", text: $apiURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .padding(PK.Spacing.md)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: PK.Radius.chip))
            Text("Only needed if you host your own 3DPrintKit Worker. The default works for most people.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .onChange(of: apiURL) { _, newValue in
            PrintKitAPIConfiguration.setBaseURL(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: PK.Spacing.md) {
            if case .failed(let message) = auth.state {
                PKCallout(status: .error, message: message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isSigningIn {
                ProgressView("Signing in…")
                    .frame(height: 50)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    auth.handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .disabled(normalizedURL.isEmpty)
                .accessibilityHint("Optional. Signing in syncs your workshop across devices.")
            }

            Button("Continue Without an Account") {
                onFinish()
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: PK.Radius.card))
            .disabled(isSigningIn)

            Text(normalizedURL.isEmpty
                 ? "Add a server URL to enable Sign in with Apple, or continue without an account."
                 : "3DPrintKit works fully offline. An account only syncs your workshop across devices — you can sign in later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(showServerField ? "Hide server settings" : "Use a custom server") {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    showServerField.toggle()
                }
            }
            .font(.caption.weight(.medium))
        }
        .padding(.horizontal, PK.Spacing.xl)
        .padding(.top, PK.Spacing.lg)
        .padding(.bottom, PK.Spacing.sm)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: PK.Spacing.lg) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
