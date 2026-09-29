import Foundation
import WidgetKit

public struct WidgetMatchSnapshot: Codable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let homeTeam: String
    public let awayTeam: String
    public let homeScore: Int?
    public let awayScore: Int?
    public let competition: String
    public let deepLinkURL: URL

    public init(id: String, date: Date, homeTeam: String, awayTeam: String,
                homeScore: Int?, awayScore: Int?, competition: String, deepLinkURL: URL) {
        self.id = id
        self.date = date
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.competition = competition
        self.deepLinkURL = deepLinkURL
    }
}

public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.liansishen.miaopu"
    private static let matchesKey = "widget.matchSnapshots"

    public static func load() -> [WidgetMatchSnapshot] {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: matchesKey),
              let matches = try? JSONDecoder().decode([WidgetMatchSnapshot].self, from: data) else {
            return []
        }
        return matches
    }

    public static func save(_ snapshots: [WidgetMatchSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots),
              let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(data, forKey: matchesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func save(from matches: [Match]) {
        let recent = matches.sorted { abs($0.startTime.timeIntervalSinceNow) < abs($1.startTime.timeIntervalSinceNow) }
        let snapshots = recent.prefix(4).compactMap { match -> WidgetMatchSnapshot? in
            guard let encoded = match.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let link = URL(string: "miaopu://match/\(encoded)") else { return nil }
            return WidgetMatchSnapshot(id: match.id, date: match.startTime,
                                       homeTeam: match.homeName, awayTeam: match.awayName,
                                       homeScore: match.homeScore, awayScore: match.awayScore,
                                       competition: match.league, deepLinkURL: link)
        }
        save(snapshots)
    }
}
