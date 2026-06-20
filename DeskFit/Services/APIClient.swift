import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected server response."
        case .server(_, let message): return message
        case .decoding: return "Could not read the server response."
        case .transport: return "Could not reach the server. Check your connection."
        }
    }
}

/// Thin async wrapper around URLSession for the DeskFit backend.
struct APIClient {
    // Backend base URL is centralized in AppConfig (auto-selects localhost on the
    // Simulator vs. your Mac's LAN IP on a physical device).
    static let baseURL = AppConfig.backendBaseURL

    private let tokenStore: KeychainTokenStore

    init(tokenStore: KeychainTokenStore = .shared) {
        self.tokenStore = tokenStore
    }

    // MARK: - Public helpers

    @discardableResult
    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        authorized: Bool = false,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await send(path, method: "POST", body: body, authorized: authorized)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// POST without a decoded response (e.g. analytics events).
    func post<Body: Encodable>(_ path: String, body: Body, authorized: Bool = true) async throws {
        _ = try await send(path, method: "POST", body: body, authorized: authorized)
    }

    func put<Body: Encodable>(_ path: String, body: Body, authorized: Bool = true) async throws {
        _ = try await send(path, method: "PUT", body: body, authorized: authorized)
    }

    /// GET with a decoded response (e.g. fetching the current weekly/meal plan).
    @discardableResult
    func get<Response: Decodable>(
        _ path: String,
        authorized: Bool = false,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await sendNoBody(path, method: "GET", authorized: authorized)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: - Core request

    @discardableResult
    private func send<Body: Encodable>(
        _ path: String,
        method: String,
        body: Body,
        authorized: Bool
    ) async throws -> Data {
        var request = URLRequest(url: APIClient.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authorized, let token = tokenStore.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(body)

        let urlString = request.url?.absoluteString ?? path
        print("[DeskFit API] → \(method) \(urlString)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[DeskFit API] ✗ \(method) \(urlString) — transport error: \(error.localizedDescription)")
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            print("[DeskFit API] ✗ \(method) \(urlString) — invalid (non-HTTP) response")
            throw APIError.invalidResponse
        }
        print("[DeskFit API] ← \(http.statusCode) \(method) \(urlString)")
        guard (200...299).contains(http.statusCode) else {
            let message = Self.message(from: data, status: http.statusCode)
            print("[DeskFit API] ✗ \(http.statusCode) \(method) \(urlString) — \(message)")
            throw APIError.server(status: http.statusCode, message: message)
        }
        return data
    }

    /// Core request for verbs without a request body (GET / DELETE).
    @discardableResult
    private func sendNoBody(
        _ path: String,
        method: String,
        authorized: Bool
    ) async throws -> Data {
        var request = URLRequest(url: APIClient.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authorized, let token = tokenStore.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let urlString = request.url?.absoluteString ?? path
        print("[DeskFit API] → \(method) \(urlString)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[DeskFit API] ✗ \(method) \(urlString) — transport error: \(error.localizedDescription)")
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        print("[DeskFit API] ← \(http.statusCode) \(method) \(urlString)")
        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.message(from: data, status: http.statusCode))
        }
        return data
    }

    private static func message(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["message"] as? String { return msg }
            if let arr = obj["message"] as? [String], !arr.isEmpty { return arr.joined(separator: "\n") }
        }
        return "Request failed (\(status))."
    }
}
