import Foundation

public enum SportCategory: String, CaseIterable, Identifiable, Sendable {
    case lol
    case valorant
    case cs2
    case basketball
    case football

    public var id: String { rawValue }
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

    public init(id: String, sport: SportCategory, league: String, startTime: Date,
                homeName: String, awayName: String, homeScore: Int? = nil, awayScore: Int? = nil,
                status: String, outBizType: String? = nil, outBizNo: String? = nil) {
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
    }
}
