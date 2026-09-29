import Foundation

/// 评分对象（单局里的选手、体育项目里的球员/教练，或比赛根节点）。
struct RatingTarget: Equatable, Identifiable, Sendable {
    let nodeID: Int64?
    let bizType: String
    let bizNo: String
    let name: String
    let description: String?
    let stageName: String?
    let labels: [String]
    let imageURL: URL?
    let championURL: URL?
    let scoreAverage: Double
    let scoreCount: Int
    let commentCount: Int
    let userScore: Int
    let canScore: Bool
    let canComment: Bool
    let hotComment: String?
    let scoreDistribution: [Int: Int]
    let category: String?
    let teamID: String?
    let subNodeCount: Int

    var id: String { "\(bizType):\(bizNo)" }

    var hasScore: Bool { scoreCount > 0 }

    init(
        nodeID: Int64?,
        bizType: String,
        bizNo: String,
        name: String,
        description: String? = nil,
        stageName: String? = nil,
        labels: [String] = [],
        imageURL: URL? = nil,
        championURL: URL? = nil,
        scoreAverage: Double = 0,
        scoreCount: Int = 0,
        commentCount: Int = 0,
        userScore: Int = 0,
        canScore: Bool = false,
        canComment: Bool = false,
        hotComment: String? = nil,
        scoreDistribution: [Int: Int] = [:],
        category: String? = nil,
        teamID: String? = nil,
        subNodeCount: Int = 0
    ) {
        self.nodeID = nodeID
        self.bizType = bizType
        self.bizNo = bizNo
        self.name = name
        self.description = description
        self.stageName = stageName
        self.labels = labels
        self.imageURL = imageURL
        self.championURL = championURL
        self.scoreAverage = scoreAverage
        self.scoreCount = scoreCount
        self.commentCount = commentCount
        self.userScore = userScore
        self.canScore = canScore
        self.canComment = canComment
        self.hotComment = hotComment
        self.scoreDistribution = scoreDistribution
        self.category = category
        self.teamID = teamID
        self.subNodeCount = subNodeCount
    }

    func with(stageName: String?) -> RatingTarget {
        RatingTarget(
            nodeID: nodeID, bizType: bizType, bizNo: bizNo, name: name, description: description,
            stageName: stageName, labels: labels, imageURL: imageURL, championURL: championURL,
            scoreAverage: scoreAverage, scoreCount: scoreCount, commentCount: commentCount,
            userScore: userScore, canScore: canScore, canComment: canComment, hotComment: hotComment,
            scoreDistribution: scoreDistribution, category: category, teamID: teamID,
            subNodeCount: subNodeCount
        )
    }
}

/// 比赛详情里的单局标签。
struct RatingStageRef: Equatable, Identifiable, Sendable {
    let name: String
    let bizType: String
    let bizNo: String
    let targetCount: Int

    var id: String { "\(bizType):\(bizNo)" }
}

/// 单局下的队伍或分组（篮球/足球为球队，趣评为话题分组）。
struct RatingGroup: Equatable, Identifiable, Sendable {
    let rootNodeID: Int64
    let name: String
    let sort: Int
    let logoURL: URL?
    let teamID: String?
    let childCount: Int
    let targets: [RatingTarget]

    var id: Int64 { rootNodeID }

    var isFun: Bool { name == "趣评" }

    func with(targets: [RatingTarget]) -> RatingGroup {
        RatingGroup(
            rootNodeID: rootNodeID, name: name, sort: sort, logoURL: logoURL,
            teamID: teamID, childCount: childCount, targets: targets
        )
    }
}

/// 单局详情：标题、说明、直接评分对象与分组。
struct StageDetail: Equatable, Sendable {
    let title: String
    let description: String?
    let imageURL: URL?
    let targets: [RatingTarget]
    let groups: [RatingGroup]

    static let empty = StageDetail(title: "单局详情", description: nil, imageURL: nil, targets: [], groups: [])
}

/// 选手评分排序方式。
enum TargetOrder: Int, CaseIterable {
    case hot
    case latest
    case highScore
    case lowScore

    var label: String {
        switch self {
        case .hot: return "热门"
        case .latest: return "最新"
        case .highScore: return "高分"
        case .lowScore: return "低分"
        }
    }

    static var labels: [String] { allCases.map(\.label) }
}

func orderTargets(_ targets: [RatingTarget], by order: TargetOrder) -> [RatingTarget] {
    switch order {
    case .hot:
        return targets
    case .latest:
        return targets.sorted { ($0.nodeID ?? Int64.min) > ($1.nodeID ?? Int64.min) }
    case .highScore:
        return targets.sorted {
            $0.scoreAverage == $1.scoreAverage
                ? $0.scoreCount > $1.scoreCount
                : $0.scoreAverage > $1.scoreAverage
        }
    case .lowScore:
        return targets.sorted { left, right in
            let leftUnscored = left.scoreCount == 0
            let rightUnscored = right.scoreCount == 0
            if leftUnscored != rightUnscored { return !leftUnscored }
            if left.scoreAverage != right.scoreAverage { return left.scoreAverage < right.scoreAverage }
            return left.scoreCount > right.scoreCount
        }
    }
}
