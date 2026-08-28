import Foundation
import AuthenticationServices

/// Sign in with Apple → PrintKit Worker session exchange.
///
/// Flow (per spec):
/// 1. User selects Sign in with Apple.
/// 2. iOS receives Apple authorization credentials.
/// 3. The identity token is sent to the Worker (POST /api/v1/auth/apple).
/// 4. The Worker verifies signature/issuer/audience/expiration/nonce and
///    issues a PrintKit session.
/// 5. Session credentials live only in the Keychain.
@Observable
final class AuthManager: NSObject {
    static let shared = AuthManager()

    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(displayName: String)
        case failed(String)
    }

    private(set) var state: State = .signedOut

    private override init() {
        super.init()
        if let name = KeychainService.read(.displayName), KeychainService.read(.accessToken) != nil {
            state = .signedIn(displayName: name)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    // MARK: - Native Sign in with Apple

    func signInWithApple() {
        state = .signingIn
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    /// Entry point for SwiftUI's `SignInWithAppleButton`, which presents the
    /// Apple sheet itself and hands us the result here.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            state = .signingIn
            process(authorization: authorization)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                state = .signedOut
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    fileprivate func process(authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            state = .failed("Apple did not return an identity token.")
            return
        }
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        Task {
            await exchange(identityToken: token,
                           displayName: name.isEmpty ? nil : name,
                           email: credential.email)
        }
    }

    private func exchange(identityToken: String, displayName: String?, email: String?) async {
        struct AuthRequest: Encodable {
            let identity_token: String
            let display_name: String?
            let email: String?
        }
        struct AuthResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let account_id: String
            let display_name: String
        }
        do {
            let response: AuthResponse = try await APIClient.shared.request(
                "POST", "/api/v1/auth/apple",
                body: AuthRequest(identity_token: identityToken, display_name: displayName, email: email),
                authenticated: false
            )
            KeychainService.save(response.access_token, for: .accessToken)
            KeychainService.save(response.refresh_token, for: .refreshToken)
            KeychainService.save(response.account_id, for: .accountID)
            KeychainService.save(response.display_name, for: .displayName)
            state = .signedIn(displayName: response.display_name)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshSessionIfNeeded() async {
        guard let refreshToken = KeychainService.read(.refreshToken) else { return }
        struct RefreshRequest: Encodable { let refresh_token: String }
        struct RefreshResponse: Decodable { let access_token: String; let refresh_token: String }
        do {
            let response: RefreshResponse = try await APIClient.shared.request(
                "POST", "/api/v1/auth/refresh",
                body: RefreshRequest(refresh_token: refreshToken),
                authenticated: false
            )
            KeychainService.save(response.access_token, for: .accessToken)
            KeychainService.save(response.refresh_token, for: .refreshToken)
        } catch {
            // A rejected refresh token means the session is gone.
            if case .unauthorized = error as? APIError { signOut() }
        }
    }

    func signOut() {
        struct Empty: Encodable {}
        Task {
            _ = try? await APIClient.shared.request("POST", "/api/v1/auth/logout", body: Empty()) as EmptyResponse
        }
        KeychainService.deleteAll()
        state = .signedOut
    }

    private struct EmptyResponse: Decodable {}
}

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        process(authorization: authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            state = .signedOut
        } else {
            state = .failed(error.localizedDescription)
        }
    }
}
