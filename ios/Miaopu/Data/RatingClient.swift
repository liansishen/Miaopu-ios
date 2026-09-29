import Foundation

public struct RatingNode: Equatable, Sendable {
    public let id: String
    public let name: String
    public let scoreAverage: Double?
    public let scoreCount: Int
    public let commentCount: Int
    public let bizType: String?
    public let bizId: String?
    public let imageURL: URL?
    public let description: String?
    public let hotComment: String?
    public let teamID: String?
    public let championURL: URL?

    public init(id: String, name: String, scoreAverage: Double?, scoreCount: Int, commentCount: Int,
                bizType: String?, bizId: String?, imageURL: URL? = nil, description: String? = nil,
                hotComment: String? = nil, teamID: String? = nil, championURL: URL? = nil) {
        self.id = id
        self.name = name
        self.scoreAverage = scoreAverage
        self.scoreCount = scoreCount
        self.commentCount = commentCount
        self.bizType = bizType
        self.bizId = bizId
        self.imageURL = imageURL
        self.description = description
        self.hotComment = hotComment
        self.teamID = teamID
        self.championURL = championURL
    }
}

public struct RatingDetail: Equatable, Sendable {
    public let root: RatingNode
    public let children: [RatingNode]

    public init(root: RatingNode, children: [RatingNode]) {
        self.root = root
        self.children = children
    }
}

public enum RatingClientError: Error, Equatable {
    case invalidURL
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case apiFailure(Int)
}

public struct RatingClient: Sendable {
    public static let endpoint = URL(string: "https://games.mobileapi.hupu.com/1/8.2.99/bplcommentapi/bpl/score_tree/getCurAndSubNodeByBizKey")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(type: String, number: String) async throws -> RatingDetail {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "outBizType", value: type),
            URLQueryItem(name: "outBizNo", value: number),
            URLQueryItem(name: "relation", value: "CHILD"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        guard let url = components?.url else { throw RatingClientError.invalidURL }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "games.mobileapi.hupu.com" else {
            throw RatingClientError.insecureURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Miaopu-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RatingClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw RatingClientError.httpStatus(response.statusCode) }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> RatingDetail {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = integer(envelope["code"]), code == 1,
              let success = envelope["success"] as? Bool, success,
              let payload = envelope["data"] as? [String: Any],
              let selfData = payload["self"] as? [String: Any],
              let rootData = selfData["node"] as? [String: Any],
              let root = node(rootData, id: "root"),
              let pageResult = payload["pageResult"] as? [String: Any],
              let rows = pageResult["data"] as? [Any] else {
            if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = integer(envelope["code"]), code != 1 {
                throw RatingClientError.apiFailure(code)
            }
            throw RatingClientError.invalidPayload
        }
        let children = try rows.map { item -> RatingNode in
            guard let entry = item as? [String: Any] else { throw RatingClientError.invalidPayload }
            let row = (entry["node"] as? [String: Any]) ?? entry
            guard let name = string(row["name"]),
                  let child = node(row, id: string(row["bizId"]) ?? name) else {
                throw RatingClientError.invalidPayload
            }
            return child
        }
        return RatingDetail(root: root, children: children)
    }

    private static func node(_ value: [String: Any], id: String) -> RatingNode? {
        guard let name = string(value["name"]),
              let directCount = integer(value["scorePersonCount"]),
              let commentCount = integer(value["commentCount"]) else { return nil }
        let scoreCount = directCount == 0 ? (integer(value["summedScorePersonCount"]) ?? 0) : directCount
        let info = value["infoJson"] as? [String: Any] ?? [:]
        return RatingNode(
            id: id,
            name: name,
            scoreAverage: directCount == 0 ? nil : decimal(value["scoreAvg"]),
            scoreCount: scoreCount,
            commentCount: commentCount,
            bizType: string(value["bizType"]),
            bizId: string(value["bizId"]),
            imageURL: (value["image"] as? [String])?.first.flatMap(imageURL),
            description: (info["desc"] as? [String])?.first,
            hotComment: (value["hottestComments"] as? [String])?.first,
            teamID: (info["teamId"] as? [String])?.first,
            championURL: (info["auxiliaryPic"] as? [String])?.first.flatMap(imageURL)
        )
    }

    private static func imageURL(_ value: String) -> URL? {
        guard var parts = URLComponents(string: value), let host = parts.host?.lowercased(),
              host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn"),
              parts.scheme == "http" || parts.scheme == "https" else { return nil }
        parts.scheme = "https"
        return parts.url
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

    private static func decimal(_ raw: Any?) -> Double? {
        guard let raw else { return nil }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}
