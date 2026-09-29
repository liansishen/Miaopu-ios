import Foundation

public enum HupuClientError: Error, Equatable {
    case invalidURL
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
}

public struct HupuClient: Sendable {
    public static let endpoint = URL(string: "https://match-api.hupu.com/1/8.2.10/matchallapi/bff/standard/getScheduleListByTagForH5")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchSchedules(for sport: SportCategory) async throws -> [Match] {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "businessType", value: "common"),
            URLQueryItem(name: "businessId", value: Self.businessID(for: sport)),
            URLQueryItem(name: "datasource", value: "navigation")
        ]
        guard let url = components?.url else { throw HupuClientError.invalidURL }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "match-api.hupu.com" else {
            throw HupuClientError.insecureURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HupuClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw HupuClientError.httpStatus(response.statusCode) }
        return try HupuScheduleParser.parse(data, sport: sport)
    }

    private static func businessID(for sport: SportCategory) -> String {
        switch sport {
        case .lol: return "lol"
        case .valorant: return "val"
        case .cs2: return "cs2"
        case .basketball: return "nba"
        case .football: return "epl"
        }
    }
}

public enum HupuScheduleParser {
    public static func parse(_ data: Data, sport: SportCategory) throws -> [Match] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let days = result["dayGameData"] as? [Any] else {
            throw HupuClientError.invalidPayload
        }
        let formatter = ISO8601DateFormatter()
        return days.flatMap { day -> [Match] in
            guard let day = day as? [String: Any],
                  let games = day["matchData"] as? [Any] else { return [] }
            return games.compactMap { item in
                guard let row = item as? [String: Any],
                      let id = string(row["matchId"]),
                      let members = (row["againstInfo"] as? [String: Any])?["memberInfos"] as? [Any],
                      members.count >= 2,
                      let home = members[0] as? [String: Any],
                      let away = members[1] as? [String: Any],
                      let homeName = string(home["memberName"]),
                      let awayName = string(away["memberName"]),
                      let rawTime = string(row["matchStartTimeStamp"]),
                      let time = date(rawTime, formatter: formatter) else { return nil }
                let scoreKey = row["scoreItemKey"] as? [String: Any]
                return Match(
                    id: id,
                    sport: sport,
                    league: string(row["matchIntroduction"]) ?? string(row["matchName"]) ?? "",
                    startTime: time,
                    homeName: homeName,
                    awayName: awayName,
                    homeScore: integer(home["memberBaseScore"]),
                    awayScore: integer(away["memberBaseScore"]),
                    status: string(row["matchStatusDesc"]) ?? "",
                    outBizType: string(scoreKey?["outBizType"]),
                    outBizNo: string(scoreKey?["outBizNo"])
                )
            }
        }
    }

    private static func string(_ raw: Any?) -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    private static func integer(_ raw: Any?) -> Int? {
        guard let text = string(raw) else { return nil }
        return Int(text)
    }

    private static func date(_ raw: String, formatter: ISO8601DateFormatter) -> Date? {
        if let milliseconds = Double(raw) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        return formatter.date(from: raw)
    }
}
