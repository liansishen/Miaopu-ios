import SwiftUI

struct CommentsView: View {
    let type: String
    let number: String
    let title: String
    @EnvironmentObject private var session: HupuSession

    @State private var comments: [Comment] = []
    @State private var cursor: CommentCursor?
    @State private var hasMore = false
    @State private var loading = false
    @State private var failure: String?
    @State private var loaded = false
    @State private var showingComposer = false
    @State private var showingLoginPrompt = false

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
        .toolbar {
            Button("发表评论", systemImage: "square.and.pencil") {
                if session.isAuthenticated { showingComposer = true }
                else { showingLoginPrompt = true }
            }
        }
        .alert("需要登录", isPresented: $showingLoginPrompt) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请先在「我的」中登录虎扑账号。")
        }
        .sheet(isPresented: $showingComposer) {
            CommentComposerView(title: "发表评论") { content in
                _ = try await HupuWriteClient().comment(
                    content: content,
                    outBizKey: HupuOutBizKey(outBizType: type, outBizNo: number),
                    cookies: session.cookies
                )
                await refresh()
            }
        }
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
    @EnvironmentObject private var session: HupuSession

    @State private var replies: [Comment] = []
    @State private var failure: String?
    @State private var cursor: CommentCursor?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loaded = false
    @State private var showingComposer = false
    @State private var showingLoginPrompt = false

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
        .toolbar {
            Button("回复", systemImage: "arrowshape.turn.up.left") {
                if session.isAuthenticated { showingComposer = true }
                else { showingLoginPrompt = true }
            }
        }
        .alert("需要登录", isPresented: $showingLoginPrompt) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请先在「我的」中登录虎扑账号。")
        }
        .sheet(isPresented: $showingComposer) {
            CommentComposerView(title: "回复评论") { content in
                _ = try await HupuWriteClient().reply(
                    content: content,
                    outBizKey: HupuOutBizKey(outBizType: type, outBizNo: number),
                    parentCommentId: parent.commentID, cookies: session.cookies
                )
                await load(reset: true)
            }
        }
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
    @EnvironmentObject private var session: HupuSession
    @State private var liked: Bool
    @State private var count: Int
    @State private var busy = false
    @State private var message = ""
    @State private var showingMessage = false

    init(comment: Comment) {
        self.comment = comment
        _liked = State(initialValue: comment.hasLight)
        _count = State(initialValue: comment.lightCount)
    }

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
            if !comment.imageURLs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(comment.imageURLs, id: \.absoluteString) { url in
                            NavigationLink {
                                CommentImageViewer(url: url)
                            } label: {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 96, height: 96)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            Button {
                if !session.isAuthenticated {
                    message = "请先在「我的」中登录虎扑账号。"
                    showingMessage = true
                } else if comment.subjectID.isEmpty {
                    message = "这条评论暂时无法点赞。"
                    showingMessage = true
                } else {
                    Task { await toggleLight() }
                }
            } label: {
                Label("\(count)", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.caption)
                    .foregroundStyle(liked ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(busy)
        }
        .alert("评论", isPresented: $showingMessage) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private func toggleLight() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await HupuWriteClient().light(
                commentId: comment.commentID, subjectId: comment.subjectID,
                enabled: !liked, cookies: session.cookies
            )
            count = max(0, count + (liked ? -1 : 1))
            liked.toggle()
        } catch {
            message = error.localizedDescription
            showingMessage = true
        }
    }
}
