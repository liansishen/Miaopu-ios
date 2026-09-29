import Foundation
import SwiftUI
import WebKit
import Security

@MainActor
public final class HupuSession: ObservableObject {
    @Published public private(set) var cookies: [HTTPCookie] = []
    @Published public private(set) var isAuthenticated = false

    private let keychainService: String
    private weak var activeWebView: WKWebView?
    private var cookieObserver: CookieStoreObserver?

    public init(keychainService: String = Bundle.main.bundleIdentifier ?? "HupuSession") {
        self.keychainService = keychainService
    }

    public static func loginURL(jumpURL: URL, from: String = "") -> URL? {
        var components = URLComponents(string: "https://passport.hupu.com/v2/login")
        components?.queryItems = [
            URLQueryItem(name: "phone", value: "1"),
            URLQueryItem(name: "jumpurl", value: jumpURL.absoluteString),
            URLQueryItem(name: "from", value: from.isEmpty ? jumpURL.absoluteString : from)
        ]
        guard let base = components?.url,
              let value = URL(string: base.absoluteString + "#/") else { return nil }
        return value
    }

    public func restore() async {
        guard let data = readKeychain(),
              let records = try? JSONDecoder().decode([CookieRecord].self, from: data) else {
            cookies = []
            isAuthenticated = false
            return
        }
        let restored = records.compactMap(\.cookie).filter { Self.isTrustedCookieDomain($0.domain) }
        cookies = restored
        isAuthenticated = Self.hasLoginCookie(restored)
        guard let store = activeWebView?.configuration.websiteDataStore.httpCookieStore else { return }
        for cookie in restored { await store.setCookie(cookie) }
    }

    public func logout() async {
        cookies = []
        isAuthenticated = false
        deleteKeychain()
        if let webView = activeWebView, let cookieObserver {
            webView.configuration.websiteDataStore.httpCookieStore.remove(cookieObserver)
        }
        cookieObserver = nil
        let store = activeWebView?.configuration.websiteDataStore ?? .default()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    fileprivate func attach(_ webView: WKWebView) {
        activeWebView = webView
        let observer = CookieStoreObserver { [weak self] store in
            Task { @MainActor in await self?.captureCookies(from: store) }
        }
        cookieObserver = observer
        webView.configuration.websiteDataStore.httpCookieStore.add(observer)
        Task { await restore() }
    }

    private func captureCookies(from store: WKHTTPCookieStore) async {
        let all = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let safe = all.filter { Self.isTrustedCookieDomain($0.domain) }
        cookies = safe
        isAuthenticated = Self.hasLoginCookie(safe)
        if let data = try? JSONEncoder().encode(safe.map(CookieRecord.init)) { writeKeychain(data) }
    }

    fileprivate static func isTrustedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "hupu.com" || host.hasSuffix(".hupu.com") || host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn")
    }

    private static func isTrustedCookieDomain(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "hupu.com" || host.hasSuffix(".hupu.com") || host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn")
    }

    private static func hasLoginCookie(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { $0.name.caseInsensitiveCompare("ua") == .orderedSame && !$0.value.isEmpty }
    }

    private func writeKeychain(_ data: Data) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "hupu.cookies"]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func readKeychain() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "hupu.cookies", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeychain() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "hupu.cookies"] as CFDictionary)
    }
}

private final class CookieStoreObserver: NSObject, WKHTTPCookieStoreObserver {
    private let changed: (WKHTTPCookieStore) -> Void
    init(changed: @escaping (WKHTTPCookieStore) -> Void) { self.changed = changed }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { changed(cookieStore) }
}

private struct CookieRecord: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        expires = cookie.expiresDate; isSecure = cookie.isSecure; isHTTPOnly = cookie.isHTTPOnly
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: isSecure ? "TRUE" : "FALSE"]
        if let expires { properties[.expires] = expires }
        if isHTTPOnly { properties[.init("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

public struct LoginView: UIViewRepresentable {
    @ObservedObject private var session: HupuSession
    private let loginURL: URL

    public init(session: HupuSession, jumpURL: URL, from: String = "") {
        self.session = session
        self.loginURL = HupuSession.loginURL(jumpURL: jumpURL, from: from) ?? URL(string: "https://passport.hupu.com/v2/login?phone=1&jumpurl=https%3A%2F%2Fhupu.com&from=#/")!
    }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        session.attach(webView)
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {}
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, HupuSession.isTrustedURL(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            guard let url = navigationResponse.response.url, HupuSession.isTrustedURL(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
