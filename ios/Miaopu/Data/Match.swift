import Foundation

public enum SportCategory: String, CaseIterable, Identifiable, Sendable {
    case lol
    case valorant
    case cs2
    case basketball
    case football

    public var id: String { rawValue }
}

public struct FeaturedRating: Equatable, Sendable {
    public let name: String
    public let imageURL: URL?
    public let teamLogoURL: URL?
    public let score: String?
    public let countText: String?
    public let hotComment: String?
    public let bizType: String?
    public let bizId: String?

    public init(name: String, imageURL: URL?, teamLogoURL: URL?, score: String?, countText: String?,
                hotComment: String?, bizType: String?, bizId: String?) {
        self.name = name
        self.imageURL = imageURL
        self.teamLogoURL = teamLogoURL
        self.score = score
        self.countText = countText
        self.hotComment = hotComment
        self.bizType = bizType
        self.bizId = bizId
    }
}

public struct Match: Identifiable, Equatable, Sendable {
    public let id: String
    public let sport: SportCategory
    public let league: String
    public let startTime: Date
    public let homeName: String
    public let awayName: String
    public let homeScore: Int?
    public let awayScore: Int?
    public let status: String
    public let outBizType: String?
    public let outBizNo: String?
    public let homeLogoURL: URL?
    public let awayLogoURL: URL?
    public let homeID: String?
    public let awayID: String?
    public let scoreCountText: String?
    public let featuredRating: FeaturedRating?
    public let dayKey: String
    public let dayTitle: String

    public init(id: String, sport: SportCategory, league: String, startTime: Date,
                homeName: String, awayName: String, homeScore: Int? = nil, awayScore: Int? = nil,
                status: String, outBizType: String? = nil, outBizNo: String? = nil,
                homeLogoURL: URL? = nil, awayLogoURL: URL? = nil, scoreCountText: String? = nil,
                featuredRating: FeaturedRating? = nil, dayKey: String? = nil, dayTitle: String? = nil,
                homeID: String? = nil, awayID: String? = nil) {
        self.id = id
        self.sport = sport
        self.league = league
        self.startTime = startTime
        self.homeName = homeName
        self.awayName = awayName
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.status = status
        self.outBizType = outBizType
        self.outBizNo = outBizNo
        self.homeLogoURL = homeLogoURL
        self.awayLogoURL = awayLogoURL
        self.homeID = homeID
        self.awayID = awayID
        self.scoreCountText = scoreCountText
        self.featuredRating = featuredRating
        self.dayKey = dayKey ?? String(Int(Calendar.current.startOfDay(for: startTime).timeIntervalSince1970))
        self.dayTitle = dayTitle ?? startTime.formatted(.dateTime.month().day().weekday(.wide))
    }
}

public struct MatchDay: Identifiable {
    public let id: String
    public let title: String
    public let matches: [Match]

    public static func group(_ matches: [Match]) -> [MatchDay] {
        var groups: [MatchDay] = []
        for match in matches {
            if let index = groups.firstIndex(where: { $0.id == match.dayKey }) {
                let previous = groups[index]
                groups[index] = MatchDay(id: previous.id, title: previous.title, matches: previous.matches + [match])
            } else {
                groups.append(MatchDay(id: match.dayKey, title: match.dayTitle, matches: [match]))
            }
        }
        return groups
    }

    public static func home(_ matches: [Match], now: Date = Date(), calendar: Calendar = .current) -> [MatchDay] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -2, to: today),
              let end = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }
        let lower = formatter.string(from: start)
        let upper = formatter.string(from: end)
        var seen = Set<String>()
        let nearby = matches.filter { match in
            (lower...upper).contains(match.dayKey) && seen.insert("\(match.sport.rawValue):\(match.id)").inserted
        }
        let order = Dictionary(uniqueKeysWithValues: SportCategory.allCases.enumerated().map { ($0.element, $0.offset) })
        let sorted = nearby.sorted {
            if $0.dayKey != $1.dayKey { return $0.dayKey < $1.dayKey }
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            if $0.sport != $1.sport { return (order[$0.sport] ?? 0) < (order[$1.sport] ?? 0) }
            return $0.id < $1.id
        }
        return group(sorted)
    }
}
