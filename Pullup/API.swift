import Foundation
import Security

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

// Only the session cookie is persisted. Passwords, QR tokens and tickets stay in memory.
enum SessionKeychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "at.pullup.ios", kSecAttrAccount as String: "session"]
    static func save(_ value: Data) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw APIError(status: 0, message: "Could not securely save your session. Please sign in again.")
        }
    }
    static func read() -> Data? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

@MainActor final class API {
    static let shared = API()
    static let origin = URL(string: "https://pullup.at")!
    private let session: URLSession
    private var cookie: String?
    private var expires: Date?
    private struct Credential: Codable { let value: String; let expires: Date }
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        session = URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
        if let data = SessionKeychain.read(), let saved = try? JSONDecoder().decode(Credential.self, from: data), saved.expires > Date() {
            cookie = saved.value; expires = saved.expires
        }
    }
    var hasSession: Bool { cookie != nil && (expires ?? .distantPast) > Date() }
    func clear() { cookie = nil; expires = nil; SessionKeychain.clear() }
    func webCookie() -> HTTPCookie? {
        guard hasSession, let cookie else { return nil }
        return HTTPCookie(properties: [.name: "pullup_session", .value: cookie, .domain: ".pullup.at", .path: "/", .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE", .expires: expires!])
    }
    func importCookie(_ item: HTTPCookie) throws {
        guard item.name == "pullup_session", ["pullup.at", ".pullup.at"].contains(item.domain), item.isSecure,
              let expiry = item.expiresDate, expiry > Date() else { return }
        try SessionKeychain.save(JSONEncoder().encode(Credential(value: item.value, expires: expiry)))
        cookie = item.value; expires = expiry
    }
    func data(_ path: String, method: String = "GET", body: [String: String]? = nil, form: [String: String]? = nil) async throws -> Data {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), let url = URL(string: path, relativeTo: Self.origin)?.absoluteURL,
              url.scheme == "https", url.host == Self.origin.host else { throw APIError(status: 0, message: "Invalid Pullup link.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://pullup.at", forHTTPHeaderField: "Origin")
        request.setValue("Pullup-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if hasSession, let cookie { request.setValue("pullup_session=\(cookie)", forHTTPHeaderField: "Cookie") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let form {
            let fields = form.map { API.segment($0.key) + "=" + API.segment($0.value) }.joined(separator: "&")
            request.httpBody = Data(fields.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, message: "No response. Please retry.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIMessage.self, from: data))?.error
            throw APIError(status: http.statusCode, message: message ?? "Pullup is temporarily unavailable. Please retry.")
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        for item in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) where item.name == "pullup_session" { try importCookie(item) }
        return data
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path, method: method, body: body))
    }
    static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.host == "pullup.at" && request.url?.scheme == "https" ? request : nil)
    }
}
