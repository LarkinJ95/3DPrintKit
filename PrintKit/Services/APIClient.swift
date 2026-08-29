import Foundation

/// Typed client for the PrintKit Cloudflare Worker API.
///
/// The base URL is configurable (Settings → Sync). When no server is
/// configured the app remains fully functional offline and every cloud
/// surface reports itself as unavailable rather than simulating anything.
struct PrintKitAPIConfiguration {
    /// Default deployed Worker URL. It can be overridden in Settings → Sync.
    static let defaultBaseURL = "https://api.3dprintkit.app"
    private static let legacyDefaultBaseURLs = [
        "https://printkit-api.jlarkin-e6e.workers.dev"
    ]

    static var baseURL: URL? {
        let stored = UserDefaults.standard.string(forKey: "apiBaseURL") ?? defaultBaseURL
        if legacyDefaultBaseURLs.contains(stored) {
            UserDefaults.standard.set(defaultBaseURL, forKey: "apiBaseURL")
            return URL(string: defaultBaseURL)
        }
        guard !stored.isEmpty else { return nil }
        return URL(string: stored)
    }

    static func setBaseURL(_ string: String) {
        UserDefaults.standard.set(string, forKey: "apiBaseURL")
    }
}

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case server(status: Int, code: String?, message: String?)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No 3DPrintKit server configured. Add your API URL in Settings → Sync & Account."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .server(_, _, let message):
            return message ?? "The server reported an error."
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .decoding:
            return "The server response could not be read."
        }
    }
}

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorBody?
    let requestID: String?
    let serverTime: Date?

    enum CodingKeys: String, CodingKey {
        case success, data, error
        case requestID = "request_id"
        case serverTime = "server_time"
    }
}

struct APIErrorBody: Decodable {
    let code: String?
    let message: String?
}

actor APIClient {
    static let shared = APIClient()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    nonisolated var isConfigured: Bool { PrintKitAPIConfiguration.baseURL != nil }

    func request<T: Decodable>(_ method: String,
                               _ path: String,
                               body: (any Encodable)? = nil,
                               query: [String: String] = [:],
                               authenticated: Bool = true) async throws -> T {
        guard var components = PrintKitAPIConfiguration.baseURL.flatMap({ URLComponents(url: $0.appending(path: path), resolvingAgainstBaseURL: false) }) else {
            throw APIError.notConfigured
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = KeychainService.read(.accessToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.unauthorized }

        let envelope: APIEnvelope<T>
        do {
            envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
        guard envelope.success, let payload = envelope.data else {
            throw APIError.server(status: status, code: envelope.error?.code, message: envelope.error?.message)
        }
        return payload
    }
}

/// Type-erased Encodable wrapper.
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeClosure = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}
