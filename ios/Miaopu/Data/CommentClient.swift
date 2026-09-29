import Foundation

public struct Comment: Equatable, Sendable {
    public let commentID: String
    public let userName: String
    public let content: String
    public let lightCount: Int
    public let publishTime: Int64
    public let subCommentCount: Int

    public init(commentID: String, userName: String, content: String, lightCount: Int, publishTime: Int64, subCommentCount: Int) {
        self.commentID = commentID
        self.userName = userName
        self.content = content
        self.lightCount = lightCount
        self.publishTime = publishTime
        self.subCommentCount = subCommentCount
    }
}

public struct CommentCursor: Equatable, Sendable {
    public let publishTime: Int64

    public init(publishTime: Int64) {
        self.publishTime = publishTime
    }
}

public struct CommentPage: Equatable, Sendable {
    public let comments: [Comment]
    public let cursor: CommentCursor
    public let hasMore: Bool
    public let commentCount: Int

    public init(comments: [Comment], cursor: CommentCursor, hasMore: Bool, commentCount: Int) {
        self.comments = comments
        self.cursor = cursor
        self.hasMore = hasMore
        self.commentCount = commentCount
    }
}

public enum CommentClientError: Error, Equatable {
    case invalidURL
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case apiFailure(Int)
}

public struct CommentClient: Sendable {
    public static let endpoint = URL(string: "https://games.mobileapi.hupu.com/1/8.2.99/bplcommentapi/bpl/comment/list/primarySingleRow")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(type: String, number: String, cursor: CommentCursor? = nil) async throws -> CommentPage {
        try await request(type: type, number: number, cursor: cursor, parentID: nil)
    }

    public func replies(type: String, number: String, parentID: String, cursor: CommentCursor? = nil) async throws -> CommentPage {
        try await request(type: type, number: number, cursor: cursor, parentID: parentID)
    }

    private func request(type: String, number: String, cursor: CommentCursor?, parentID: String?) async throws -> CommentPage {
        let url = parentID == nil ? Self.endpoint : Self.endpoint.appendingPathComponent("getMore")
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "games.mobileapi.hupu.com" else {
            throw CommentClientError.insecureURL
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "publishTime", value: String(cursor?.publishTime ?? (parentID == nil ? Int64(Date().timeIntervalSince1970 * 1000) : 0)))
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "outBizType", value: type),
            URLQueryItem(name: "outBizNo", value: number),
            URLQueryItem(name: "clientCode", value: ""),
            URLQueryItem(name: "cid", value: "")
        ]
        if let parentID {
            items.append(URLQueryItem(name: "parentCommentId", value: parentID))
            items.append(URLQueryItem(name: "pageSize", value: "20"))
        }
        components?.queryItems = items
        guard let requestURL = components?.url else { throw CommentClientError.invalidURL }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CommentClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw CommentClientError.httpStatus(response.statusCode) }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> CommentPage {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommentClientError.invalidPayload
        }
        guard let code = integer(envelope["code"]), code == 1,
              let success = envelope["success"] as? Bool, success else {
            throw CommentClientError.apiFailure(integer(envelope["code"]) ?? -1)
        }
        guard let payload = envelope["data"] as? [String: Any],
              let rows = payload["comments"] as? [Any],
              let cursorData = payload["cursor"] as? [String: Any],
              let cursorTime = int64(cursorData["publishTime"]),
              let hasMore = payload["hasMore"] as? Bool,
              let commentCount = integer(payload["commentCount"]) else {
            throw CommentClientError.invalidPayload
        }
        let comments = try rows.map { raw -> Comment in
            guard let row = raw as? [String: Any],
                  let id = string(row["commentId"]),
                  let user = string(row["commentUserName"]),
                  let content = string(row["commentContent"]),
                  let lightCount = integer(row["lightCount"]),
                  let publishTime = int64(row["publishTime"]),
                  let subCount = integer(row["subCommentCount"]) else {
                throw CommentClientError.invalidPayload
            }
            return Comment(commentID: id, userName: user, content: content, lightCount: lightCount, publishTime: publishTime, subCommentCount: subCount)
        }
        return CommentPage(comments: comments, cursor: CommentCursor(publishTime: cursorTime), hasMore: hasMore, commentCount: commentCount)
    }

    private static func string(_ raw: Any?) -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? String { return value }
        if let value = raw as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        if let value = raw as? Int { return value }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func int64(_ raw: Any?) -> Int64? {
        guard let raw else { return nil }
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? String { return Int64(value) }
        return nil
    }
}
