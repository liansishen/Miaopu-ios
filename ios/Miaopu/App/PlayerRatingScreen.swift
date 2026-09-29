import SwiftUI

/// 选手评分：资料卡、评分分布、我的评分与评论列表。
struct PlayerRatingScreen: View {
    let target: RatingTarget
    let matchLabel: String

    @EnvironmentObject private var session: HupuSession
    @State private var current: RatingTarget
    @State private var comments: [Comment] = []
    @State private var hotComments: [Comment] = []
    @State private var cursor: CommentCursor?
    @State private var hasMore = false
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var failure: String?
    @State private var orderIndex = 0
    @State private var selectedScore = 0
    @State private var composing = false
    @State private var composerScore = 0
    @State private var replyTarget: Comment?
    @State private var repliesParent: Comment?
    @State private var showingLoginPrompt = false
    @State private var actionMessage = ""
    @State private var showingMessage = false
    @State private var busy = false

    init(target: RatingTarget, matchLabel: String) {
        self.target = target
        self.matchLabel = matchLabel
        _current = State(initialValue: target)
        _selectedScore = State(initialValue: target.userScore)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                identitySection
                commentSection
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .navigationTitle("选手评分")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loaded { await refreshComments() }
        }
        .sheet(isPresented: $composing) {
            CommentComposerSheet(
                title: composerTitle,
                placeholder: composerPlaceholder,
                actionTitle: session.isAuthenticated ? "发布" : "登录",
                allowsScoreOnly: replyTarget == nil && current.canScore && composerScore > 0 && composerScore != current.userScore
            ) { text in
                try await publish(text: text)
            }
        }
        .sheet(item: $repliesParent) { parent in
            CommentRepliesSheet(target: current, parent: parent)
        }
        .alert("需要登录", isPresented: $showingLoginPrompt) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请先在「我的」中登录虎扑账号。")
        }
        .alert("提示", isPresented: $showingMessage) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage)
        }
    }

    // MARK: - 资料与评分

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MiaopuCard(padding: 14) {
                HStack(alignment: .center, spacing: 10) {
                    PortraitView(
                        url: current.imageURL,
                        championURL: current.championURL,
                        name: current.name,
                        size: 62,
                        cornerRadius: 10
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.name)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(2)
                        ForEach(detailLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(current.hasScore ? String(format: "%.1f", current.scoreAverage) : "—")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(MiaopuStyle.accent)
                        Text("\(formatScoreCount(current.scoreCount))人评分")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MiaopuCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("评分分布").font(.system(size: 14, weight: .semibold))
                    let total = current.scoreDistribution.values.reduce(0, +)
                    ForEach([10, 8, 6, 4, 2], id: \.self) { score in
                        distributionRow(score: score, total: total)
                    }
                }
            }

            if current.canScore {
                MiaopuCard(padding: 14, verticalPadding: 8) {
                    HStack(spacing: 4) {
                        Text("我的评分").font(.system(size: 13))
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                guard session.isAuthenticated else {
                                    showingLoginPrompt = true
                                    return
                                }
                                selectedScore = star * 2
                                composerScore = star * 2
                                replyTarget = nil
                                composing = true
                            } label: {
                                Image(systemName: selectedScore >= star * 2 ? "star.fill" : "star")
                                    .font(.system(size: 25))
                                    .foregroundStyle(MiaopuStyle.accent)
                                    .frame(width: 32, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(star) 星")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var detailLines: [String] {
        var lines: [String] = []
        for value in [matchLabel, current.stageName, current.description] {
            guard let value, !value.isEmpty, value != "评分" else { continue }
            if !lines.contains(value) { lines.append(value) }
        }
        return Array(lines.prefix(3))
    }

    private func distributionRow(score: Int, total: Int) -> some View {
        let count = current.scoreDistribution[score] ?? 0
        let fraction = total > 0 ? min(max(Double(count) / Double(total), 0), 1) : 0
        return HStack(spacing: 0) {
            Text("\(score)分")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(MiaopuStyle.trackBackground)
                    if fraction > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(MiaopuStyle.accent)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
            }
            .frame(height: 6)
            Text(total > 0 ? "\(Int(fraction * 100))%" : "—")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 19)
    }

    // MARK: - 评论

    @ViewBuilder
    private var commentSection: some View {
        if let failure {
            DetailNotice(message: failure, onRetry: { Task { await refreshComments() } })
        } else if loading && !loaded {
            DetailNotice(message: "正在加载评论", loading: true)
        } else {
            HStack(alignment: .center) {
                Text("全部评论 \(total)")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                DetailOrderSelector(labels: CommentOrder.labels, selected: orderIndex) { orderIndex = $0 }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)

            if visibleComments.isEmpty {
                DetailNotice(message: "还没有评论，来说说你的看法")
            } else {
                ForEach(visibleComments) { comment in
                    PlayerCommentCard(
                        comment: comment,
                        onLike: { Task { await toggleLike(comment) } },
                        onReply: { openComposer(replyTo: comment) },
                        onReplies: { repliesParent = comment }
                    )
                }
            }

            if hasMore {
                Button(loading ? "正在加载…" : "上滑加载更多") {
                    Task { await loadMore() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
    }

    private var visibleComments: [Comment] {
        if orderIndex == 0 {
            return mergeComments(byHeat: comments, incoming: hotComments, officialHot: hotComments.map(\.commentID))
        }
        return comments.sorted { $0.publishTime > $1.publishTime }
    }

    private var composerTitle: String {
        replyTarget == nil ? "发表评论 · \(composerScore)分" : "回复评论"
    }

    private var composerPlaceholder: String {
        session.isAuthenticated ? "说说你的看法…" : "登录后发表评论"
    }

    private func openComposer(replyTo: Comment?) {
        guard session.isAuthenticated else {
            showingLoginPrompt = true
            return
        }
        replyTarget = replyTo
        composerScore = selectedScore
        composing = true
    }

    private func refreshComments() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CommentClient().fetch(type: current.bizType, number: current.bizNo)
            comments = page.comments
            cursor = page.cursor
            hasMore = page.hasMore
            total = page.commentCount
            failure = nil
            loaded = true
            hotComments = (try? await CommentClient().hottest(type: current.bizType, number: current.bizNo)) ?? []
        } catch {
            failure = error.localizedDescription
            loaded = true
        }
    }

    private func loadMore() async {
        guard hasMore, !loading, let cursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CommentClient().fetch(type: current.bizType, number: current.bizNo, cursor: cursor)
            let existing = Set(comments.map(\.commentID))
            comments += page.comments.filter { !existing.contains($0.commentID) }
            self.cursor = page.cursor
            hasMore = page.hasMore && page.cursor != cursor
            total = max(total, page.commentCount)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func publish(text: String) async throws {
        let key = HupuOutBizKey(outBizType: current.bizType, outBizNo: current.bizNo)
        if let replyTarget {
            _ = try await HupuWriteClient().reply(
                content: text,
                outBizKey: key,
                parentCommentId: replyTarget.commentID,
                cookies: session.cookies
            )
        } else {
            if current.canScore, composerScore > 0, composerScore != current.userScore {
                _ = try await HupuWriteClient().score(outBizKey: key, score: composerScore, cookies: session.cookies)
                selectedScore = composerScore
                await refreshTarget()
            }
            if !text.isEmpty {
                _ = try await HupuWriteClient().comment(content: text, outBizKey: key, cookies: session.cookies)
            }
        }
        replyTarget = nil
        await refreshComments()
    }

    private func refreshTarget() async {
        if let updated = try? await RatingClient().fetchTarget(type: current.bizType, number: current.bizNo) {
            current = updated
        }
    }

    private func toggleLike(_ comment: Comment) async {
        guard session.isAuthenticated else {
            showingLoginPrompt = true
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await HupuWriteClient().light(
                commentId: comment.commentID,
                subjectId: comment.subjectID,
                enabled: !comment.hasLight,
                cookies: session.cookies
            )
            await refreshComments()
        } catch {
            actionMessage = "操作失败：\(error.localizedDescription)"
            showingMessage = true
        }
    }
}

/// 评论卡片：头像、作者、评分徽章、点赞、正文与回复预览。
struct PlayerCommentCard: View {
    let comment: Comment
    let onLike: () -> Void
    let onReply: () -> Void
    let onReplies: () -> Void

    var body: some View {
        MiaopuCard(radius: 18, padding: 14, action: onReply) {
            VStack(alignment: .leading, spacing: 0) {
                row
                if !replyText.isEmpty {
                    Button(action: onReplies) {
                        VStack(alignment: .leading, spacing: 5) {
                            if let preview = comment.previewReplies.first {
                                Text("\(preview.userName)：\(preview.content)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 2) {
                                Text("查看全部 \(max(comment.replyCount, comment.previewReplies.count)) 条回复")
                                    .font(.system(size: 12))
                                    .foregroundStyle(MiaopuStyle.accent)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MiaopuStyle.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 44)
                    .padding(.top, 7)
                }
            }
        }
    }

    private var replyText: String {
        comment.previewReplies.isEmpty && comment.replyCount == 0 ? "" : "replies"
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(MiaopuStyle.trackBackground)
                if let avatar = comment.avatarURL {
                    AsyncImage(url: avatar) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { initial }
                    }
                } else {
                    initial
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(comment.userName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let badge = badgeText {
                        Text(badge)
                            .font(.system(size: 10))
                            .foregroundStyle(MiaopuStyle.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(MiaopuStyle.accent.opacity(0.1)))
                    }
                    Spacer(minLength: 8)
                    Button(action: onLike) {
                        HStack(spacing: 4) {
                            Image(systemName: comment.hasLight ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 13))
                            Text("\(comment.lightCount)").font(.system(size: 11))
                        }
                        .foregroundStyle(comment.hasLight ? MiaopuStyle.accent : Color.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(comment.content).font(.system(size: 14))
                if !comment.imageURLs.isEmpty {
                    CommentImageStrip(urls: comment.imageURLs)
                }
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var initial: some View {
        Text(String(comment.userName.prefix(1)))
            .font(.system(size: 13))
            .foregroundStyle(MiaopuStyle.accent)
    }

    private var badgeText: String? {
        if comment.score > 0 { return "\(comment.score)分" }
        return comment.badgeName
    }

    private var metadata: String {
        [comment.dateText, comment.location]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// 评论图片：横向排列并支持点开查看与保存。
struct CommentImageStrip: View {
    let urls: [URL]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(urls, id: \.absoluteString) { url in
                    NavigationLink {
                        CommentImageViewer(url: url)
                    } label: {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 评论输入弹层：文字与分数一并提交。
struct CommentComposerSheet: View {
    let title: String
    let placeholder: String
    let actionTitle: String
    var allowsScoreOnly = false
    let publish: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("comment-content")
                }
                if let failure {
                    Text(failure).foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "正在提交" : actionTitle) {
                        Task { await submit() }
                    }
                    .disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !allowsScoreOnly))
                }
            }
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        do {
            try await publish(text.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// 回复列表弹层。
struct CommentRepliesSheet: View {
    let target: RatingTarget
    let parent: Comment

    @Environment(\.dismiss) private var dismiss
    @State private var replies: [Comment] = []
    @State private var cursor: CommentCursor?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            CardFlow {
                MiaopuCard(radius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parent.userName).font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(parent.content).font(.system(size: 14))
                    }
                }
                if let failure {
                    DetailNotice(message: failure, onRetry: { Task { await load(reset: true) } })
                } else if loading && replies.isEmpty {
                    DetailNotice(message: "正在加载回复", loading: true)
                } else if replies.isEmpty && loaded {
                    DetailNotice(message: "暂无回复")
                } else {
                    ForEach(replies) { reply in
                        MiaopuCard(radius: 18, padding: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reply.userName).font(.system(size: 12)).foregroundStyle(.secondary)
                                Text(reply.content).font(.system(size: 14))
                            }
                        }
                    }
                    if hasMore {
                        Button(loading ? "正在加载…" : "加载更多") {
                            Task { await load(reset: false) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                    }
                }
            }
            .navigationTitle("评论回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { if !loaded { await load(reset: true) } }
        }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await CommentClient().replies(
                type: target.bizType,
                number: target.bizNo,
                parentID: parent.commentID,
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
            loaded = true
        }
    }
}
