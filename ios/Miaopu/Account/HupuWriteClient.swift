import Foundation

public struct HupuOutBizKey: Encodable, Equatable, Sendable {
    public let outBizType: String
    public let outBizNo: String

    public init(outBizType: String, outBizNo: String) {
        self.outBizType = outBizType
        self.outBizNo = outBizNo
    }
}

public enum HupuWriteClientError: Error, Equatable {
    case unauthenticated
    case invalidInput
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case apiFailure(Int)
    case apiRejected
}

public final class HupuWriteClient {
    public static let host = "games.mobileapi.hupu.com"
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    @discardableResult
    public func score(outBizKey: HupuOutBizKey, score: Int, cookies: [HTTPCookie]) async throws -> Data {
        guard [2, 4, 6, 8, 10].contains(score) else { throw HupuWriteClientError.invalidInput }
        return try await post(path: "/1/8.2.99/bplcommentapi/bpl/score/save", body: ["outBizKey": keyJSON(outBizKey), "score": score, "source": ""], cookies: cookies)
    }

    @discardableResult
    public func comment(content: String, outBizKey: HupuOutBizKey, cookies: [HTTPCookie]) async throws -> Data {
        return try await post(path: "/1/8.2.99/bplcommentapi/bpl/comment/m/publish", body: ["content": content, "outBizKey": keyJSON(outBizKey), "subjectId": "", "source": "m"], cookies: cookies)
    }

    @discardableResult
    public func reply(content: String, outBizKey: HupuOutBizKey, parentCommentId: String, cookies: [HTTPCookie]) async throws -> Data {
        return try await post(path: "/1/8.2.58/bplcommentapi/bpl/comment/publish", body: ["outBizKey": keyJSON(outBizKey), "parentCommentId": parentCommentId, "content": content, "images": [], "ancillaryContents": []], cookies: cookies)
    }

    @discardableResult
    public func light(commentId: String, subjectId: String, cookies: [HTTPCookie]) async throws -> Data {
        try await post(path: "/1/8.2.58/bplcommentapi/bpl/comment/light", body: ["commentKey": ["commentId": commentId, "subjectId": subjectId]], cookies: cookies)
    }

    private func post(path: String, body: [String: Any], cookies: [HTTPCookie]) async throws -> Data {
        let url = URL(string: "https://\(Self.host)\(path)")!
        let now = Date()
        let eligible = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let pathMatches = url.path == cookie.path || url.path.hasPrefix(cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/")
            return (domain == Self.host || Self.host.hasSuffix("." + domain)) && cookie.isSecure && pathMatches && (cookie.expiresDate == nil || cookie.expiresDate! > now)
        }
        guard eligible.contains(where: { $0.name.caseInsensitiveCompare("ua") == .orderedSame && !$0.value.isEmpty }) else {
            throw HupuWriteClientError.unauthenticated
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HTTPCookie.requestHeaderFields(with: eligible)["Cookie"], forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HupuWriteClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw HupuWriteClientError.httpStatus(response.statusCode) }
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HupuWriteClientError.invalidPayload }
        if let code = envelope["code"] as? Int, code != 1 { throw HupuWriteClientError.apiFailure(code) }
        if let success = envelope["success"] as? Bool, !success { throw HupuWriteClientError.apiRejected }
        guard envelope["code"] != nil || envelope["success"] != nil else { throw HupuWriteClientError.invalidPayload }
        return data
    }

    private func keyJSON(_ key: HupuOutBizKey) -> [String: String] {
        ["outBizType": key.outBizType, "outBizNo": key.outBizNo]
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
