import Foundation

struct StatsCell: Equatable {
    let text: String
    let imageURL: URL?
}

struct StatsTeam: Equatable {
    let name: String
    let logoURL: URL?
    let score: String?
    let columns: [String]
    let players: [[StatsCell]]
}

struct StatsMap: Equatable, Identifiable {
    let id: String
    let name: String
}

struct MatchStats: Equatable {
    let maps: [StatsMap]
    let defaultMapID: String?
    let teams: [StatsTeam]

    static let empty = MatchStats(maps: [], defaultMapID: nil, teams: [])

    var hasData: Bool {
        teams.contains { team in
            team.players.contains { row in
                row.dropFirst().contains { !$0.text.isEmpty && $0.text != "—" }
            }
        }
    }
}

/// 技术统计：地图列表与各队球员数据表。
struct MatchStatsClient: Sendable {
    static let endpoint = URL(string: "https://match-api.hupu.com/1/8.0.0/matchallapi/stat/queryMatchStatsByMatchInfo/v2")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(matchID: String, mapID: String = "0") async throws -> MatchStats {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "matchId", value: matchID),
            URLQueryItem(name: "boNumber", value: mapID)
        ]
        guard let url = components?.url else { throw HupuClientError.invalidURL }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "match-api.hupu.com" else {
            throw HupuClientError.insecureURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Miaopu-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HupuClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw HupuClientError.httpStatus(response.statusCode) }
        return Self.parse(data)
    }

    /// 接口在缺少统计时返回 `success = false`，这里按空结果处理而不是报错。
    static func parse(_ data: Data) -> MatchStats {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["success"] as? Bool) == true,
              let result = root["result"] as? [String: Any],
              let blocks = result["stats"] as? [Any] else {
            return .empty
        }
        let rows = blocks.compactMap { $0 as? [String: Any] }
        let mapBlocks = rows.filter { string($0["componentCode"]) == "bo_components" }
        let maps = mapBlocks.first.flatMap { block -> [StatsMap] in
            let cells = (block["headingInfo"] as? [String: Any])?["tableDataInfo"] as? [Any] ?? []
            return cells.compactMap { raw -> StatsMap? in
                guard let cell = raw as? [String: Any], let id = string(cell["requestValue"]) else { return nil }
                return StatsMap(id: id, name: id == "0" ? "全场" : (string(cell["showName"]) ?? id))
            }
        } ?? []
        var defaultMapID: String?
        if let block = mapBlocks.first, !(block["defaultAnchor"] is NSNull),
           let anchor = integer(block["defaultAnchor"]), anchor >= 0, anchor < maps.count {
            defaultMapID = maps[anchor].id
        }
        var scores: [String: String] = [:]
        for block in rows where string(block["componentCode"]) == "single_horizontal_display" {
            for raw in (block["bodyInfo"] as? [Any] ?? []) {
                guard let row = raw as? [String: Any], let position = string(row["memberPosition"]) else { continue }
                let data = (row["bodyDataInfo"] as? [Any] ?? [])
                let value = data.count > 1 ? (data[1] as? [String: Any]) : nil
                scores[position] = string(value?["showName"])
            }
        }
        let teams = rows.filter { string($0["componentCode"]) == "list_display_components" }.compactMap { block -> StatsTeam? in
            guard let heading = block["headingInfo"] as? [String: Any] else { return nil }
            let columns = (heading["tableDataInfo"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            guard let first = columns.first else { return nil }
            let players = (block["bodyInfo"] as? [Any] ?? []).compactMap { raw -> [StatsCell]? in
                guard let row = raw as? [String: Any] else { return nil }
                let cells = row["bodyDataInfo"] as? [Any] ?? []
                return columns.indices.map { index -> StatsCell in
                    let cell = index < cells.count ? cells[index] as? [String: Any] : nil
                    return StatsCell(text: string(cell?["showName"]) ?? "—", imageURL: imageURL(cell?["logo"]))
                }
            }
            let camp = string(block["belongingCamp"]) ?? string(heading["memberPosition"])
            return StatsTeam(
                name: string(first["showName"]) ?? "",
                logoURL: imageURL(first["logo"]),
                score: camp.flatMap { scores[$0] },
                columns: columns.map { string($0["showName"]) ?? "—" },
                players: players
            )
        }
        return MatchStats(maps: maps, defaultMapID: defaultMapID, teams: teams)
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

    private static func imageURL(_ raw: Any?) -> URL? {
        guard let value = string(raw), var parts = URLComponents(string: value),
              let host = parts.host?.lowercased(),
              host == "hoopchina.com.cn" || host.hasSuffix(".hoopchina.com.cn"),
              parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = "https"
        return parts.url
    }
}
