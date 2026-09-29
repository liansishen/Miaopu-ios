import Foundation

struct MatchPlayerScore: Equatable {
    let name: String
    let score: String
    let dayHex: String?
    let nightHex: String?

    init(name: String, score: String, dayHex: String? = nil, nightHex: String? = nil) {
        self.name = name
        self.score = score
        self.dayHex = dayHex
        self.nightHex = nightHex
    }
}

struct MatchTeamScores: Equatable {
    let name: String
    let logoURL: URL?
    let players: [MatchPlayerScore]
}

struct MatchAllScores: Equatable {
    let teams: [MatchTeamScores]

    var hasScores: Bool {
        teams.contains { $0.players.contains { (Double($0.score) ?? 0) > 0 } }
    }
}

struct MatchScoreClient {
    func fetch(match: Match) async throws -> MatchAllScores {
        let esports = match.sport == .lol
        let base = esports
            ? "https://games.mobileapi.hupu.com/1/8.2.58/player/v1/lol/getAllPlayerScore"
            : "https://match-api.hupu.com/1/8.2.58/matchallapi/queryMatchAllScoreInfo"
        var components = URLComponents(string: base)!
        components.queryItems = esports
            ? [URLQueryItem(name: "matchId", value: match.id)]
            : [URLQueryItem(name: "businessType", value: "common_match"), URLQueryItem(name: "matchId", value: match.id)]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Miaopu-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw HupuClientError.invalidResponse
        }
        return try Self.parse(data, esports: esports)
    }

    static func parse(_ data: Data, esports: Bool) throws -> MatchAllScores {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HupuClientError.invalidPayload
        }
        if esports {
            guard (root["code"] as? Int) == 1, let payload = root["data"] as? [String: Any] else {
                throw HupuClientError.invalidPayload
            }
            let info = payload["matchInfo"] as? [String: Any] ?? [:]
            let entries = payload["teamScoreInfo"] as? [[String: Any]] ?? []
            let ordered = entries.sorted { ($0["home"] as? Bool == true) && ($1["home"] as? Bool != true) }
            return MatchAllScores(teams: ordered.enumerated().map { index, entry in
                let side = (entry["home"] as? Bool).map { $0 ? 1 : 2 } ?? index + 1
                let players = (entry["playerInfo"] as? [[String: Any]] ?? []).compactMap { row -> MatchPlayerScore? in
                    guard let name = text(row["playerName"]) else { return nil }
                    let value = text(row["playerScore"]).flatMap(Double.init)
                    let score = value.flatMap { $0.isFinite && $0 > 0 && $0 <= 10 ? String(format: "%.1f", $0) : nil } ?? "—"
                    return MatchPlayerScore(name: name, score: score,
                                            dayHex: text(row["scoreDayColor"]), nightHex: text(row["scoreNightColor"]))
                }
                return MatchTeamScores(name: text(info["team\(side)_name"]) ?? "",
                                       logoURL: imageURL(info["team\(side)_logo"]), players: players)
            })
        }
        guard (root["success"] as? Bool) == true,
              let payload = root["result"] as? [String: Any] else { throw HupuClientError.invalidPayload }
        let basics = payload["memberBasicInfos"] as? [[String: Any]] ?? []
        let scoreRows = payload["memberScoreInfos"] as? [Any] ?? []
        return MatchAllScores(teams: (0..<max(basics.count, scoreRows.count)).map { index in
            let basic = index < basics.count ? basics[index] : [:]
            var players: [MatchPlayerScore] = []
            func collect(_ value: Any) {
                if let rows = value as? [Any] { rows.forEach(collect) }
                else if let row = value as? [String: Any], let name = text(row["memberName"]) {
                    players.append(MatchPlayerScore(name: name, score: text(row["memberAllAvgScore"]) ?? "—",
                                                    dayHex: text(row["scoreDayColor"]), nightHex: text(row["scoreNightColor"])))
                }
            }
            if index < scoreRows.count { collect(scoreRows[index]) }
            return MatchTeamScores(name: text(basic["memberName"]) ?? "",
                                   logoURL: imageURL(basic["memberLogo"]), players: players)
        })
    }

    private static func text(_ value: Any?) -> String? {
        if let value = value as? String { return value.isEmpty ? nil : value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func imageURL(_ value: Any?) -> URL? {
        guard let raw = text(value), var parts = URLComponents(string: raw),
              let host = parts.host?.lowercased(),
              host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn"),
              parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = "https"
        return parts.url
    }
}
