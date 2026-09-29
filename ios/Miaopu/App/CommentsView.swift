import SwiftUI

struct CommentsView: View {
    let type: String
    let number: String
    let title: String

    @State private var comments: [Comment] = []
    @State private var cursor: CommentCursor?
    @State private var hasMore = false
    @State private var loading = false
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        List {
            if let failure {
                Section {
                    Text(failure).foregroundStyle(.secondary)
                    Button("重试") { Task { await refresh() } }
                }
            }
            if loading && !loaded {
                ProgressView("正在加载评论")
            } else if comments.isEmpty && failure == nil {
                ContentUnavailableView("暂无评论", systemImage: "bubble.left")
            } else {
                ForEach(comments, id: \.commentID) { comment in
                    VStack(alignment: .leading, spacing: 10) {
                        CommentRow(comment: comment)
                        if comment.subCommentCount > 0 {
                            NavigationLink("查看 \(comment.subCommentCount) 条回复") {
                                RepliesView(type: type, number: number, parent: comment)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if hasMore {
                Button(loading ? "正在加载" : "加载更多") {
                    Task { await loadMore() }
                }
                .disabled(loading)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { if !loaded { await refresh() } }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CommentClient().fetch(type: type, number: number)
            comments = page.comments
            cursor = page.cursor
            hasMore = page.hasMore
            failure = nil
            loaded = true
        } catch {
            failure = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore, !loading, let cursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CommentClient().fetch(type: type, number: number, cursor: cursor)
            let existing = Set(comments.map(\.commentID))
            comments += page.comments.filter { !existing.contains($0.commentID) }
            self.cursor = page.cursor
            hasMore = page.hasMore && page.cursor != cursor
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct RepliesView: View {
    let type: String
    let number: String
    let parent: Comment

    @State private var replies: [Comment] = []
    @State private var failure: String?
    @State private var cursor: CommentCursor?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        List {
            Section("原评论") { CommentRow(comment: parent) }
            Section("回复") {
                if let failure {
                    Text(failure).foregroundStyle(.secondary)
                    Button("重试") { Task { await load(reset: true) } }
                } else if replies.isEmpty && loaded {
                    Text("暂无回复").foregroundStyle(.secondary)
                }
                ForEach(replies, id: \.commentID) { reply in
                    CommentRow(comment: reply)
                }
                if hasMore {
                    Button(loading ? "正在加载" : "加载更多") { Task { await load(reset: false) } }
                        .disabled(loading)
                }
                if loading && replies.isEmpty { ProgressView("正在加载回复") }
            }
        }
        .navigationTitle("评论回复")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CommentClient().replies(
                type: type, number: number, parentID: parent.commentID,
                cursor: reset ? nil : cursor
            )
            let existing = Set(replies.map(\.commentID))
            replies = reset ? page.comments : replies + page.comments.filter { !existing.contains($0.commentID) }
            hasMore = page.hasMore && (reset || page.cursor != cursor)
            cursor = page.cursor
            failure = nil
            loaded = true
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comment.userName).font(.subheadline.bold())
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(comment.publishTime) / 1000).formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(comment.content)
                .font(.body)
            Label("\(comment.lightCount)", systemImage: "hand.thumbsup")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
