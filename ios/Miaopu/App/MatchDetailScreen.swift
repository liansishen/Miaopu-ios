import SwiftUI

/// 比赛详情：英雄卡、评分/数据标签页、全场评分、单局与队伍标签、排序与选手卡片。
struct MatchDetailScreen: View {
    let match: Match
    @StateObject private var model = MatchDetailModel()

    var body: some View {
        CardFlow {
            hero
            if model.hasStatistics {
                DetailTabs(labels: ["评分", "数据"], selected: model.page, style: .page) { model.selectPage($0) }
            }
            if model.page == 0 {
                ratingSection
            } else {
                statsSection
            }
        }
        .navigationTitle("比赛详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.bind(match) }
    }

    // MARK: - 英雄卡

    private var hero: some View {
        MiaopuCard(padding: 16, verticalPadding: 12) {
            VStack(spacing: 6) {
                Text(match.league.isEmpty ? "\(match.homeName) vs \(match.awayName)" : match.league)
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                if !match.status.isEmpty {
                    Text(match.status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
                HStack(alignment: .center, spacing: 8) {
                    heroTeam(name: match.homeName, logo: match.homeLogoURL)
                    Text(scoreText)
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    heroTeam(name: match.awayName, logo: match.awayLogoURL)
                }
                .padding(.top, 2)
            }
        }
    }

    private var scoreText: String {
        guard let home = match.homeScore, let away = match.awayScore else { return "VS" }
        return "\(home) : \(away)"
    }

    private func heroTeam(name: String, logo: URL?) -> some View {
        VStack(spacing: 6) {
            TeamLogo(url: logo, name: name, size: 40)
            Text(name.isEmpty ? "待定" : name)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 评分页

    @ViewBuilder
    private var ratingSection: some View {
        if let scores = model.scores, scores.hasScores {
            AllMatchScoreCard(scores: scores)
        }
        if let failure = model.ratingFailure {
            DetailNotice(message: failure, onRetry: { Task { await model.reloadRating() } })
        } else if model.ratingLoading && model.stages.isEmpty {
            DetailNotice(message: "正在加载单局评分", loading: true)
        } else if model.stages.isEmpty {
            DetailNotice(message: "这场比赛暂时没有可评分的选手")
        } else {
            DetailTabs(labels: model.stageLabels, selected: model.selectedTabPosition, style: .map) { position in
                Task { await model.selectTab(position) }
            }
            stageContent
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        if let failure = model.stageFailure, model.targets.isEmpty {
            DetailNotice(message: failure, onRetry: { Task { await model.reloadStage() } })
        } else {
            if !model.groups.isEmpty && !model.funSelected {
                DetailTabs(
                    labels: model.groups.map(\.name),
                    selected: model.selectedGroupIndex,
                    style: .team,
                    logos: model.groups.map(\.logoURL)
                ) { model.selectGroup($0) }
            }
            if !model.targets.isEmpty || !model.stageLoading {
                HStack {
                    Spacer()
                    DetailOrderSelector(labels: TargetOrder.labels, selected: model.orderIndex) { model.orderIndex = $0 }
                }
                .padding(.horizontal, 16)
            }
            if model.stageLoading && model.targets.isEmpty {
                DetailNotice(message: "正在加载这一局的评分", loading: true)
            } else if model.targets.isEmpty {
                DetailNotice(message: "这个分组暂时没有评分对象")
            } else {
                ForEach(model.orderedTargets) { target in
                    NavigationLink {
                        PlayerRatingScreen(target: target, matchLabel: matchLabel)
                    } label: {
                        RatingTargetCard(target: target)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var matchLabel: String {
        let home = [match.homeName, match.homeScore.map(String.init)].compactMap { $0 }.joined(separator: " ")
        let away = [match.awayName, match.awayScore.map(String.init)].compactMap { $0 }.joined(separator: " ")
        let label = "\(home) : \(away)"
        return label.trimmingCharacters(in: .whitespaces) == ":" ? "" : label
    }

    // MARK: - 数据页

    @ViewBuilder
    private var statsSection: some View {
        if let failure = model.statsFailure {
            DetailNotice(message: failure, onRetry: { Task { await model.reloadStats() } })
        } else if model.statsLoading && model.stats.teams.isEmpty {
            DetailNotice(message: "正在加载比赛数据", loading: true)
        } else if model.stats.teams.isEmpty {
            DetailNotice(message: "这场比赛暂时没有技术统计")
        } else {
            if model.stats.maps.count > 1 {
                DetailTabs(labels: model.stats.maps.map(\.name), selected: model.selectedMapPosition) { position in
                    Task { await model.selectMap(position) }
                }
            }
            ForEach(Array(model.stats.teams.enumerated()), id: \.offset) { _, team in
                MatchStatsTableView(team: team)
            }
        }
    }
}

/// 全场评分：两队选手左右对照，分数徽章使用接口给出的配色。
struct AllMatchScoreCard: View {
    let scores: MatchAllScores
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MiaopuCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("全场评分").font(.system(size: 16, weight: .bold))
                Text("根据单局评分综合得出").font(.system(size: 11)).foregroundStyle(.secondary)
                let teams = Array(scores.teams.prefix(2))
                if let home = teams.first {
                    HStack {
                        teamHeading(home, trailing: false)
                        Spacer(minLength: 8)
                        if teams.count > 1 { teamHeading(teams[1], trailing: true) }
                    }
                    .padding(.vertical, 8)
                    let rows = max(home.players.count, teams.count > 1 ? teams[1].players.count : 0)
                    ForEach(0..<rows, id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 0.5)
                        }
                        HStack(alignment: .center, spacing: 6) {
                            playerRow(index < home.players.count ? home.players[index] : nil, trailing: false)
                            Text("Ⅰ")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            playerRow(teams.count > 1 && index < teams[1].players.count ? teams[1].players[index] : nil, trailing: true)
                        }
                        .frame(minHeight: 32)
                    }
                }
            }
        }
    }

    private func teamHeading(_ team: MatchTeamScores, trailing: Bool) -> some View {
        HStack(spacing: 8) {
            if !trailing, let logo = team.logoURL { TeamLogo(url: logo, name: team.name, size: 22) }
            Text(team.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if trailing, let logo = team.logoURL { TeamLogo(url: logo, name: team.name, size: 22) }
        }
    }

    private func playerRow(_ player: MatchPlayerScore?, trailing: Bool) -> some View {
        HStack(spacing: 6) {
            if trailing { badge(player) }
            Text(player?.name ?? "")
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
            if !trailing { badge(player) }
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(_ player: MatchPlayerScore?) -> some View {
        let score = player.flatMap { Double($0.score) } ?? 0
        let color = player.map { scoreColor(score: score, dayHex: $0.dayHex, nightHex: $0.nightHex, scheme: scheme) }
        return ScoreBadge(text: player?.score ?? "", color: color)
    }
}

/// 选手卡片：头像、简介与标签、均分与人数、热评。
struct RatingTargetCard: View {
    let target: RatingTarget

    var body: some View {
        MiaopuCard(radius: 16, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    PortraitView(
                        url: target.imageURL,
                        championURL: target.championURL,
                        name: target.name,
                        size: 48,
                        cornerRadius: 8
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let description = target.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let label = target.labels.first {
                                TagPill(text: label)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(target.hasScore ? String(format: "%.1f", target.scoreAverage) : "—")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(MiaopuStyle.accent)
                        Text("\(formatScoreCount(target.scoreCount))人评分")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                if let hot = target.hotComment, !hot.isEmpty {
                    HotCommentBar(text: hot)
                }
            }
        }
    }
}

/// 技术统计表：左侧固定选手列，右侧统计列可横向滚动。
struct MatchStatsTableView: View {
    let team: StatsTeam

    var body: some View {
        MiaopuCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if let logo = team.logoURL { TeamLogo(url: logo, name: team.name, size: 24) }
                    Text(team.name).font(.system(size: 16, weight: .bold))
                    Spacer()
                    if let score = team.score { Text(score).font(.system(size: 16, weight: .bold)) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            headerCell("选手", width: 136, alignment: .leading)
                            ForEach(Array(team.columns.dropFirst().enumerated()), id: \.offset) { _, column in
                                headerCell(column, width: 68, alignment: .center)
                            }
                        }
                        ForEach(Array(team.players.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 0) {
                                playerCell(row.first, alternate: index % 2 == 1)
                                ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { _, cell in
                                    Text(cell.text)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                        .frame(width: 68, height: 30)
                                        .background(rowBackground(index))
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(width: width, height: 34, alignment: alignment)
            .padding(.leading, alignment == .leading ? 12 : 0)
            .background(Color.primary.opacity(0.035))
    }

    private func playerCell(_ cell: StatsCell?, alternate: Bool) -> some View {
        HStack(spacing: 6) {
            if let url = cell?.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            }
            Text(cell?.text ?? "—")
                .font(.system(size: 12))
                .lineLimit(2)
        }
        .frame(width: 136, height: 30, alignment: .leading)
        .padding(.leading, 10)
        .background(rowBackground(alternate ? 1 : 0))
    }

    private func rowBackground(_ index: Int) -> Color {
        index % 2 == 0 ? MiaopuStyle.cardBackground : Color.primary.opacity(0.025)
    }
}

@MainActor
final class MatchDetailModel: ObservableObject {
    @Published private(set) var scores: MatchAllScores?
    @Published private(set) var stages: [RatingStageRef] = []
    @Published private(set) var stageDetail: StageDetail?
    @Published private(set) var seedTargets: [String: [RatingTarget]] = [:]
    @Published private(set) var ratingLoading = false
    @Published private(set) var ratingFailure: String?
    @Published private(set) var stageLoading = false
    @Published private(set) var stageFailure: String?
    @Published private(set) var stats: MatchStats = .empty
    @Published private(set) var statsLoading = false
    @Published private(set) var statsFailure: String?
    @Published private(set) var hasStatistics = false
    @Published private(set) var selectedStageIndex = 0
    @Published private(set) var funSelected = false
    @Published private(set) var selectedGroupIndex = 0
    @Published var orderIndex = 0
    @Published var page = 0

    private var match: Match?
    private var stageCache: [String: StageDetail] = [:]
    private var statsCache: [String: MatchStats] = [:]

    var stageLabels: [String] {
        var labels = stages.map(\.name)
        if funGroup != nil, !labels.isEmpty {
            labels.insert("趣评", at: min(1, labels.count))
        }
        return labels
    }

    var selectedTabPosition: Int {
        if funSelected, funGroup != nil { return min(1, stages.count) }
        return min(selectedStageIndex, max(stages.count - 1, 0))
    }

    var funGroup: RatingGroup? {
        stageDetail?.groups.first { $0.isFun && !$0.targets.isEmpty }
    }

    var groups: [RatingGroup] {
        guard let detail = stageDetail else { return [] }
        return detail.groups
            .filter { !$0.isFun && !$0.targets.isEmpty }
            .sorted { left, right in
                let leftIndex = teamIndex(left.name) ?? Int.max
                let rightIndex = teamIndex(right.name) ?? Int.max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
                return left.sort > right.sort
            }
    }

    var targets: [RatingTarget] {
        if funSelected { return funGroup?.targets ?? [] }
        if !groups.isEmpty, groups.indices.contains(selectedGroupIndex) {
            return groups[selectedGroupIndex].targets
        }
        if let detail = stageDetail, !detail.targets.isEmpty { return detail.targets }
        if stages.indices.contains(selectedStageIndex) {
            return seedTargets[stages[selectedStageIndex].id] ?? []
        }
        return []
    }

    var orderedTargets: [RatingTarget] {
        orderTargets(targets, by: TargetOrder(rawValue: orderIndex) ?? .hot)
    }

    var selectedMapPosition: Int {
        guard let id = stats.maps.first(where: { $0.id == selectedMapID })?.id else { return 0 }
        return stats.maps.firstIndex { $0.id == id } ?? 0
    }

    private(set) var selectedMapID: String = "0"

    func bind(_ next: Match) async {
        guard match?.id != next.id else { return }
        match = next
        scores = nil
        stages = []
        stageDetail = nil
        seedTargets = [:]
        stageCache = [:]
        statsCache = [:]
        stats = .empty
        hasStatistics = false
        selectedStageIndex = 0
        funSelected = false
        selectedGroupIndex = 0
        orderIndex = 0
        page = 0
        ratingFailure = nil
        stageFailure = nil
        statsFailure = nil
        async let summary: Void = loadSummary(next)
        async let statsTask: Void = loadStats(next, mapID: "0")
        async let rating: Void = loadRating(next)
        _ = await (summary, statsTask, rating)
    }

    func selectPage(_ value: Int) {
        page = value
    }

    func selectTab(_ position: Int) async {
        let funPosition = funGroup == nil ? -1 : min(1, stages.count)
        if position == funPosition {
            funSelected = true
            if !groups.isEmpty { selectedGroupIndex = 0 }
            return
        }
        let index = position > funPosition && funPosition >= 0 ? position - 1 : position
        guard stages.indices.contains(index) else { return }
        funSelected = false
        selectedStageIndex = index
        await loadStage(stages[index])
    }

    func selectGroup(_ index: Int) {
        selectedGroupIndex = index
    }

    func reloadRating() async {
        guard let match else { return }
        await loadRating(match)
    }

    func reloadStage() async {
        guard stages.indices.contains(selectedStageIndex) else { return }
        let stage = stages[selectedStageIndex]
        stageCache[stage.id] = nil
        await loadStage(stage)
    }

    func reloadStats() async {
        guard let match else { return }
        statsCache[selectedMapID] = nil
        await loadStats(match, mapID: selectedMapID)
    }

    func selectMap(_ position: Int) async {
        guard stats.maps.indices.contains(position), let match else { return }
        await loadStats(match, mapID: stats.maps[position].id)
    }

    private func loadSummary(_ match: Match) async {
        scores = try? await MatchScoreClient().fetch(match: match)
    }

    private func loadRating(_ match: Match) async {
        guard let type = match.outBizType, let number = match.outBizNo else {
            ratingFailure = "这场比赛暂无评分入口"
            return
        }
        ratingLoading = true
        defer { ratingLoading = false }
        do {
            let data = try await RatingClient().treeData(type: type, number: number)
            let tree = try RatingClient.parseTree(data)
            stages = tree.children.map {
                RatingStageRef(name: $0.name, bizType: $0.bizType, bizNo: $0.bizNo, targetCount: $0.subNodeCount)
            }
            seedTargets = RatingClient.parseStageSeeds(data)
            ratingFailure = nil
            if !stages.isEmpty {
                selectedStageIndex = 0
                funSelected = false
                await loadStage(stages[0])
            }
        } catch {
            ratingFailure = error.localizedDescription
        }
    }

    private func loadStage(_ stage: RatingStageRef) async {
        selectedGroupIndex = 0
        if let cached = stageCache[stage.id] {
            stageDetail = cached
            stageFailure = nil
            return
        }
        stageDetail = nil
        stageLoading = true
        defer { stageLoading = false }
        do {
            let detail = try await RatingClient().fetchStageDetail(type: stage.bizType, number: stage.bizNo)
            stageCache[stage.id] = detail
            stageDetail = detail
            stageFailure = nil
        } catch {
            stageFailure = error.localizedDescription
        }
    }

    private func loadStats(_ match: Match, mapID: String) async {
        if let cached = statsCache[mapID] {
            stats = cached
            selectedMapID = mapID
            return
        }
        statsLoading = true
        defer { statsLoading = false }
        do {
            let value = try await MatchStatsClient().fetch(matchID: match.id, mapID: mapID)
            statsCache[mapID] = value
            stats = value
            selectedMapID = mapID
            if value.hasData { hasStatistics = true }
            statsFailure = nil
        } catch {
            statsFailure = error.localizedDescription
        }
    }

    private func teamIndex(_ name: String) -> Int? {
        guard let match else { return nil }
        if name == match.homeName { return 0 }
        if name == match.awayName { return 1 }
        return nil
    }
}
