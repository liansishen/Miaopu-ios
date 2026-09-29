import SwiftUI

struct RatingSummary: View {
    let detail: RatingDetail

    var body: some View {
        Section("全场评分") {
            RatingLine(node: detail.root)
            ScoreActionView(node: detail.root)
            if let type = detail.root.bizType, let number = detail.root.bizId {
                NavigationLink("查看评论") {
                    CommentsView(type: type, number: number, title: detail.root.name)
                }
            }
        }
        if !detail.children.isEmpty {
            Section("分局与选手") {
                ForEach(detail.children, id: \.id) { node in
                    NavigationLink {
                        RatingNodeScreen(node: node)
                    } label: {
                        RatingLine(node: node)
                    }
                }
            }
        }
    }
}

private struct RatingNodeScreen: View {
    let node: RatingNode
    @State private var detail: RatingDetail?
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                RatingLine(node: node)
                if let type = node.bizType, let number = node.bizId {
                    NavigationLink("查看评论") {
                        CommentsView(type: type, number: number, title: node.name)
                    }
                }
            }
            if let detail {
                RatingSummary(detail: detail)
            } else if let failure {
                Section {
                    Text(failure)
                        .foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                }
            } else if node.bizType != nil && node.bizId != nil {
                ProgressView("正在加载评分")
            }
        }
        .navigationTitle(node.name)
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

private struct RatingLine: View {
    let node: RatingNode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.headline)
                Text("\(node.scoreCount) 人评分 · \(node.commentCount) 条评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let score = node.scoreAverage {
                Text(score.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            }
        }
    }
}
