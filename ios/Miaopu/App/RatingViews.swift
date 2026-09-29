import SwiftUI

struct AllMatchScoreCard: View {
    let scores: MatchAllScores

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("根据单局评分综合得出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(Array(scores.teams.prefix(2).enumerated()), id: \.offset) { _, team in
                        HStack(spacing: 6) {
                            RemoteBadge(url: team.logoURL, name: team.name, size: 24)
                            Text(team.name).font(.subheadline.bold()).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                let teams = Array(scores.teams.prefix(2))
                if let first = teams.first {
                    ForEach(0..<max(first.players.count, teams.count > 1 ? teams[1].players.count : 0), id: \.self) { index in
                        HStack(spacing: 8) {
                            player(index < first.players.count ? first.players[index] : nil, trailing: false)
                            Text("Ⅰ").font(.caption2).foregroundStyle(.tertiary)
                            player(teams.count > 1 && index < teams[1].players.count ? teams[1].players[index] : nil, trailing: true)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("全场评分")
        }
    }

    private func player(_ item: MatchPlayerScore?, trailing: Bool) -> some View {
        HStack(spacing: 4) {
            if trailing { badge(item?.score) }
            Text(item?.name ?? "")
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
            if !trailing { badge(item?.score) }
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(_ value: String?) -> some View {
        Text(value ?? "")
            .font(.caption.bold())
            .foregroundStyle(.orange)
            .frame(width: 34)
    }
}

struct RatingSummary: View {
    let detail: RatingDetail
    var match: Match? = nil

    var body: some View {
        Section("赛事评分") {
            RatingLine(node: detail.root)
            ScoreActionView(node: detail.root)
            if let type = detail.root.bizType, let number = detail.root.bizId {
                NavigationLink("查看评论") {
                    CommentsView(type: type, number: number, title: detail.root.name)
                }
            }
        }
        if !detail.children.isEmpty {
            Section(detail.children.allSatisfy { $0.bizType?.hasSuffix("_item") == true } ? "选手评分" : "单局评分") {
                ForEach(Array(detail.children.enumerated()), id: \.offset) { _, node in
                    NavigationLink {
                        RatingNodeScreen(node: node, match: match)
                    } label: {
                        RatingLine(node: node)
                    }
                }
            }
        }
    }
}

struct RatingNodeScreen: View {
    let node: RatingNode
    var match: Match? = nil
    @State private var detail: RatingDetail?
    @State private var failure: String?
    @State private var selectedTeam = "全部"
    @State private var order = "热门"

    private var teams: [String] {
        guard let match else { return ["全部"] }
        var values = ["全部"]
        if detail?.children.contains(where: { $0.teamID == match.homeID && $0.teamID != nil }) == true { values.append(match.homeName) }
        if detail?.children.contains(where: { $0.teamID == match.awayID && $0.teamID != nil }) == true { values.append(match.awayName) }
        return values
    }

    private var visible: [RatingNode] {
        let nodes = (detail?.children ?? []).filter { item in
            guard let match, selectedTeam != "全部" else { return true }
            return item.teamID == (selectedTeam == match.homeName ? match.homeID : match.awayID)
        }
        switch order {
        case "高分": return nodes.sorted { ($0.scoreAverage ?? -1) > ($1.scoreAverage ?? -1) }
        case "低分": return nodes.sorted { ($0.scoreAverage ?? 11) < ($1.scoreAverage ?? 11) }
        case "最新": return Array(nodes.reversed())
        default: return nodes.sorted { $0.scoreCount > $1.scoreCount }
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    RemoteBadge(url: detail?.root.imageURL ?? node.imageURL, name: node.name, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(node.name).font(.title3.bold())
                        if let description = detail?.root.description ?? node.description {
                            Text(description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            if let detail {
                if detail.children.isEmpty {
                    Section("选手评分") {
                        RatingLine(node: detail.root)
                        ScoreActionView(node: detail.root)
                        if let type = detail.root.bizType, let number = detail.root.bizId {
                            NavigationLink("查看评论") {
                                CommentsView(type: type, number: number, title: detail.root.name)
                            }
                        }
                    }
                } else {
                    Section {
                        if teams.count > 1 {
                            Picker("队伍", selection: $selectedTeam) {
                                ForEach(teams, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        Picker("排序", selection: $order) {
                            ForEach(["热门", "最新", "高分", "低分"], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Text("\(visible.count) 名选手")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, player in
                        NavigationLink {
                            RatingNodeScreen(node: player, match: match)
                        } label: {
                            RatingPlayerCard(node: player)
                        }
                    }
                }
            } else if let failure {
                Section {
                    Text(failure).foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                }
            } else {
                ProgressView("正在加载评分")
            }
        }
        .navigationTitle(node.bizType?.contains("bo") == true ? "单局详情" : node.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: node.id) { await load() }
    }

    private func load() async {
        guard let type = node.bizType, let number = node.bizId else { return }
        do {
            detail = try await RatingClient().fetch(type: type, number: number)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct RatingPlayerCard: View {
    let node: RatingNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteBadge(url: node.imageURL, name: node.name, size: 48)
                    if let champion = node.championURL {
                        RemoteBadge(url: champion, name: "英雄", size: 18)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).font(.headline)
                    if let description = node.description {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(node.scoreAverage.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                        .font(.title2.bold()).foregroundStyle(.orange)
                    Text("\(node.scoreCount)人评分")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let comment = node.hotComment, !comment.isEmpty {
                Text("“\(comment)”")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 5)
    }
}

private struct RatingLine: View {
    let node: RatingNode

    var body: some View {
        HStack(spacing: 12) {
            RemoteBadge(url: node.imageURL, name: node.name, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name).font(.headline)
                Text("\(node.scoreCount) 人评分 · \(node.commentCount) 条评论")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let score = node.scoreAverage {
                Text(score.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.bold()).foregroundStyle(.orange)
            }
        }
    }
}
