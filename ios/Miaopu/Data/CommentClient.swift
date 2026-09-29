import Foundation

struct Comment: Equatable, Sendable, Identifiable {
    let commentID: String
    let userName: String
    let content: String
    let lightCount: Int
    let publishTime: Int64
    let subCommentCount: Int
    let subjectID: String
    let hasLight: Bool
    let imageURLs: [URL]
    let avatarURL: URL?
    let score: Int
    let dateText: String?
    let location: String?
    let replyCount: Int
    let previewReplies: [Comment]
    let badgeName: String?

    var id: String { commentID }

    init(
        commentID: String,
        userName: String,
        content: String,
        lightCount: Int,
        publishTime: Int64,
        subCommentCount: Int,
        subjectID: String = "",
        hasLight: Bool = false,
        imageURLs: [URL] = [],
        avatarURL: URL? = nil,
        score: Int = 0,
        dateText: String? = nil,
        location: String? = nil,
        replyCount: Int? = nil,
        previewReplies: [Comment] = [],
        badgeName: String? = nil
    ) {
        self.commentID = commentID
        self.userName = userName
        self.content = content
        self.lightCount = lightCount
        self.publishTime = publishTime
        self.subCommentCount = subCommentCount
        self.subjectID = subjectID
        self.hasLight = hasLight
        self.imageURLs = imageURLs
        self.avatarURL = avatarURL
        self.score = score
        self.dateText = dateText
        self.location = location
        self.replyCount = replyCount ?? subCommentCount
        self.previewReplies = previewReplies
        self.badgeName = badgeName
    }
}

struct CommentCursor: Equatable, Sendable {
    let publishTime: Int64

    init(publishTime: Int64) {
        self.publishTime = publishTime
    }
}

struct CommentPage: Equatable, Sendable {
    let comments: [Comment]
    let cursor: CommentCursor
    let hasMore: Bool
    let commentCount: Int

    init(comments: [Comment], cursor: CommentCursor, hasMore: Bool, commentCount: Int) {
        self.comments = comments
        self.cursor = cursor
        self.hasMore = hasMore
        self.commentCount = commentCount
    }
}

enum CommentClientError: Error, Equatable {
    case invalidURL
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case apiFailure(Int)
}

enum CommentOrder: Int, CaseIterable {
    case hot
    case latest

    var label: String { self == .hot ? "最热" : "最新" }

    static var labels: [String] { allCases.map(\.label) }
}

/// 与安卓一致的合并规则：热门评论按官方顺序排在前，其余保持原有热度顺序去重。
func mergeComments(byHeat existing: [Comment], incoming: [Comment], officialHot: [String] = []) -> [Comment] {
    var unique: [String: Comment] = [:]
    var order: [String] = []
    for comment in existing + incoming where unique[comment.commentID] == nil {
        unique[comment.commentID] = comment
        order.append(comment.commentID)
    }
    var result: [Comment] = []
    for id in officialHot {
        if let comment = unique.removeValue(forKey: id) {
            result.append(comment)
            order.removeAll { $0 == id }
        }
    }
    result.append(contentsOf: order.compactMap { unique[$0] })
    return result
}

struct CommentClient: Sendable {
    static let endpoint = URL(string: "https://games.mobileapi.hupu.com/1/8.2.99/bplcommentapi/bpl/comment/list/primarySingleRow")!
    private static let host = "games.mobileapi.hupu.com"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(type: String, number: String, cursor: CommentCursor? = nil) async throws -> CommentPage {
        try await request(url: Self.endpoint, type: type, number: number, cursor: cursor, parentID: nil)
    }

    func replies(type: String, number: String, parentID: String, cursor: CommentCursor? = nil) async throws -> CommentPage {
        try await request(
            url: Self.endpoint.appendingPathComponent("getMore"),
            type: type, number: number, cursor: cursor, parentID: parentID
        )
    }

    /// 热门评论：接口返回数组，用于「最热」排序时置顶官方热评。
    func hottest(type: String, number: String) async throws -> [Comment] {
        var components = URLComponents(url: Self.endpoint.appendingPathComponent("hottest"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "outBizType", value: type),
            URLQueryItem(name: "outBizNo", value: number),
            URLQueryItem(name: "clientCode", value: "")
        ]
        guard let url = components?.url, url.scheme?.lowercased() == "https",
              url.host?.lowercased() == Self.host else { throw CommentClientError.insecureURL }
        let data = try await send(URLRequest(url: url))
        return try Self.parseHottest(data)
    }

    static func parseHottest(_ data: Data) throws -> [Comment] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommentClientError.invalidPayload
        }
        guard let code = integer(root["code"]), code == 1, (root["success"] as? Bool) == true else {
            throw CommentClientError.apiFailure(integer(root["code"]) ?? -1)
        }
        let rows = root["data"] as? [Any] ?? []
        return rows.compactMap { comment(from: $0, includePreviews: false) }
    }

    private func request(url: URL, type: String, number: String, cursor: CommentCursor?, parentID: String?) async throws -> CommentPage {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == Self.host else {
            throw CommentClientError.insecureURL
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let initialTime: Int64 = parentID == nil ? Int64(Date().timeIntervalSince1970 * 1000) : 31_507_200_000
        let publishTime = cursor?.publishTime ?? initialTime
        var items = [
            URLQueryItem(name: "publishTime", value: String(publishTime)),
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
        let data = try await send(URLRequest(url: requestURL))
        return try Self.parse(data)
    }

    private func send(_ base: URLRequest) async throws -> Data {
        var request = base
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Miaopu-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CommentClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw CommentClientError.httpStatus(response.statusCode) }
        return data
    }

    static func parse(_ data: Data) throws -> CommentPage {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommentClientError.invalidPayload
        }
        guard let code = integer(envelope["code"]), code == 1,
              (envelope["success"] as? Bool) == true else {
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
        let comments = rows.compactMap { comment(from: $0, includePreviews: true) }
        guard comments.count == rows.count else { throw CommentClientError.invalidPayload }
        return CommentPage(
            comments: comments,
            cursor: CommentCursor(publishTime: cursorTime),
            hasMore: hasMore,
            commentCount: commentCount
        )
    }

    static func comment(from raw: Any, includePreviews: Bool) -> Comment? {
        guard let row = raw as? [String: Any],
              let id = string(row["commentId"]),
              let user = string(row["commentUserName"]) else { return nil }
        let images = (row["commentContentImages"] as? [[String: Any]] ?? []).compactMap { item -> URL? in
            guard string(item["commentContentType"]) == "IMAGE",
                  let text = string(item["commentContent"]), let url = URL(string: text),
                  let host = url.host?.lowercased(),
                  host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn") ||
                  host == "hupu.com" || host.hasSuffix(".hupu.com") else { return nil }
            return url
        }
        let badge = (row["commentUserTakeBadge"] as? [String: Any]).flatMap { string($0["name"]) }
        let previews: [Comment] = includePreviews
            ? (row["subCommentList"] as? [Any] ?? []).compactMap { comment(from: $0, includePreviews: false) }
            : []
        return Comment(
            commentID: id,
            userName: user,
            content: string(row["commentContent"]) ?? "",
            lightCount: integer(row["lightCount"]) ?? 0,
            publishTime: int64(row["publishTime"]) ?? 0,
            subCommentCount: integer(row["subCommentCount"]) ?? 0,
            subjectID: string(row["subjectId"]) ?? "",
            hasLight: row["hasLight"] as? Bool ?? false,
            imageURLs: images,
            avatarURL: trustedImage(string(row["commentUserHeadImg"])),
            score: integer(row["score"]) ?? 0,
            dateText: string(row["commentDate"]),
            location: string(row["ipLocation"]),
            replyCount: integer(row["descendantCount"]) ?? integer(row["subCommentCount"]),
            previewReplies: previews,
            badgeName: badge
        )
    }

    private static func trustedImage(_ value: String?) -> URL? {
        guard let value, var parts = URLComponents(string: value),
              let host = parts.host?.lowercased(),
              host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn") ||
              host == "hupu.com" || host.hasSuffix(".hupu.com"),
              parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = "https"
        return parts.url
    }

    private static func string(_ raw: Any?) -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? String { return value.isEmpty ? nil : value }
        if let value = raw as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ raw: Any?) -> Int? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func int64(_ raw: Any?) -> Int64? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let value = raw as? Int64 { return value }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String { return Int64(value) }
        return nil
    }
}
