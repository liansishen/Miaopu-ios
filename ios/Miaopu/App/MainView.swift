import SwiftUI

@MainActor
final class ScheduleState: ObservableObject {
    @Published private(set) var matches: [SportCategory: [Match]] = [:]
    @Published private(set) var failures: [SportCategory: String] = [:]
    @Published private(set) var loading: Set<SportCategory> = []

    func load(_ sport: SportCategory, force: Bool = false) async {
        guard !loading.contains(sport), force || matches[sport] == nil else { return }
        loading.insert(sport)
        failures[sport] = nil
        defer { loading.remove(sport) }
        do {
            matches[sport] = try await HupuClient().fetchSchedules(for: sport)
        } catch {
            failures[sport] = error.localizedDescription
        }
    }

    func results(for sport: SportCategory, search: String = "") -> [Match] {
        let all = matches[sport] ?? []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.homeName.localizedStandardContains(query) ||
            $0.awayName.localizedStandardContains(query) ||
            $0.league.localizedStandardContains(query)
        }
    }
}

private func sportName(_ sport: SportCategory) -> String {
    switch sport {
    case .lol: "英雄联盟"
    case .valorant: "无畏契约"
    case .cs2: "CS2"
    case .basketball: "篮球"
    case .football: "足球"
    }
}

private func dateText(_ date: Date) -> String {
    date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).weekday(.wide).hour().minute())
}

struct MainView: View {
    @StateObject private var state = ScheduleState()
    @StateObject private var session = HupuSession()
    @AppStorage("subscribedSports") private var subscribedSports = "lol,valorant,cs2,basketball,football"

    private var subscribed: [SportCategory] {
        let ids = Set(subscribedSports.split(separator: ",").map(String.init))
        return SportCategory.allCases.filter { ids.contains($0.rawValue) }
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeScreen(state: state, sports: subscribed)
            }
            .tabItem { Label("首页", systemImage: "house") }

            NavigationStack {
                EventsScreen(state: state)
            }
            .tabItem { Label("赛事", systemImage: "calendar") }

            NavigationStack {
                ProfileScreen(subscribedSports: $subscribedSports, session: session)
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(.orange)
        .task { await session.restore() }
    }
}

private struct HomeScreen: View {
    @ObservedObject var state: ScheduleState
    let sports: [SportCategory]

    var body: some View {
        List {
            if sports.isEmpty {
                ContentUnavailableView("还没有订阅赛事", systemImage: "calendar.badge.plus", description: Text("在「我的」中选择关注的赛事。"))
            }
            ForEach(sports) { sport in
                Section(sportName(sport)) {
                    if let failure = state.failures[sport] {
                        ErrorRow(message: failure) { Task { await state.load(sport, force: true) } }
                    } else if state.loading.contains(sport) && state.matches[sport] == nil {
                        ProgressView("正在加载赛程")
                    } else if state.results(for: sport).isEmpty {
                        Text("暂无比赛")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.results(for: sport)) { match in
                            NavigationLink {
                                MatchDetailScreen(match: match)
                            } label: {
                                MatchRow(match: match)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("喵扑")
        .refreshable {
            for sport in sports { await state.load(sport, force: true) }
        }
        .task(id: sports.map(\.rawValue).joined(separator: ",")) {
            for sport in sports { await state.load(sport) }
        }
    }
}

private struct EventsScreen: View {
    @ObservedObject var state: ScheduleState
    @State private var selected: SportCategory = .lol
    @State private var search = ""

    var body: some View {
        List {
            if let failure = state.failures[selected] {
                ErrorRow(message: failure) { Task { await state.load(selected, force: true) } }
            } else if state.loading.contains(selected) && state.matches[selected] == nil {
                ProgressView("正在加载赛程")
            } else if state.results(for: selected, search: search).isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ForEach(state.results(for: selected, search: search)) { match in
                    NavigationLink {
                        MatchDetailScreen(match: match)
                    } label: {
                        MatchRow(match: match)
                    }
                }
            }
        }
        .navigationTitle("赛事")
        .safeAreaInset(edge: .top) {
            Picker("赛事项目", selection: $selected) {
                ForEach(SportCategory.allCases) { sport in
                    Text(sportName(sport)).tag(sport)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .background(.regularMaterial)
        }
        .searchable(text: $search, prompt: "搜索队伍或赛事")
        .refreshable { await state.load(selected, force: true) }
        .task(id: selected) { await state.load(selected) }
    }
}

private struct MatchRow: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.league)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(match.status)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Text(match.homeName)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(score(match.homeScore))
                    .fontWeight(.semibold)
                Text(":")
                    .foregroundStyle(.secondary)
                Text(score(match.awayScore))
                    .fontWeight(.semibold)
                Text(match.awayName)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.subheadline)
            Text(dateText(match.startTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("match-\(match.id)")
    }

    private func score(_ value: Int?) -> String { value.map(String.init) ?? "-" }
}

private struct MatchDetailScreen: View {
    let match: Match
    @State private var rating: RatingDetail?
    @State private var ratingError: String?

    private var detailURL: URL? {
        guard let type = match.outBizType, let number = match.outBizNo else { return nil }
        var parts = URLComponents(string: "https://offline-download.hupu.com/online/prod/310016/detail.html")
        parts?.queryItems = [
            URLQueryItem(name: "outBizType", value: type),
            URLQueryItem(name: "outBizNo", value: number),
            URLQueryItem(name: "isCheckInfo", value: "1")
        ]
        return parts?.url
    }

    var body: some View {
        List {
            Section {
                MatchRow(match: match)
            }
            if let rating {
                RatingSummary(detail: rating)
            } else if let ratingError {
                Section("赛事评分") {
                    Text(ratingError).foregroundStyle(.secondary)
                    Button("重试") { Task { await loadRatings() } }
                }
            } else if match.outBizType != nil && match.outBizNo != nil {
                Section("赛事评分") { ProgressView("正在加载评分") }
            } else {
                Section("赛事评分") {
                    Text("这场比赛暂无评分入口")
                        .foregroundStyle(.secondary)
                }
            }
            if let url = detailURL {
                Section("虎扑比赛页面") {
                    Link("查看比赛原页面", destination: url)
                }
            }
        }
        .navigationTitle("比赛详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: match.id) { await loadRatings() }
    }

    private func loadRatings() async {
        guard let type = match.outBizType, let number = match.outBizNo else { return }
        do {
            rating = try await RatingClient().fetch(type: type, number: number)
            ratingError = nil
        } catch {
            ratingError = error.localizedDescription
        }
    }
}

private struct ProfileScreen: View {
    @Binding var subscribedSports: String
    @ObservedObject var session: HupuSession

    var body: some View {
        List {
            Section("赛事") {
                NavigationLink("赛事订阅") {
                    SubscriptionsScreen(subscribedSports: $subscribedSports)
                }
            }
            Section("账号") {
                if session.isAuthenticated {
                    Label("已登录虎扑", systemImage: "checkmark.circle.fill")
                    Button("退出登录", role: .destructive) {
                        Task { await session.logout() }
                    }
                } else {
                    NavigationLink("登录虎扑") {
                        LoginView(session: session, jumpURL: URL(string: "https://offline-download.hupu.com/online/prod/310016/detail.html")!)
                            .navigationTitle("登录虎扑")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            Section {
                Text("第三方赛事客户端")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
    }
}

private struct SubscriptionsScreen: View {
    @Binding var subscribedSports: String

    private var selected: Set<String> {
        Set(subscribedSports.split(separator: ",").map(String.init))
    }

    var body: some View {
        List {
            ForEach(SportCategory.allCases) { sport in
                Button {
                    var ids = selected
                    if ids.contains(sport.rawValue) {
                        ids.remove(sport.rawValue)
                    } else {
                        ids.insert(sport.rawValue)
                    }
                    subscribedSports = SportCategory.allCases
                        .filter { ids.contains($0.rawValue) }
                        .map(\.rawValue)
                        .joined(separator: ",")
                } label: {
                    HStack {
                        Text(sportName(sport))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(sport.rawValue) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .accessibilityIdentifier("subscription-\(sport.rawValue)")
            }
        }
        .navigationTitle("赛事订阅")
    }
}

private struct ErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .foregroundStyle(.secondary)
            Button("重试", action: retry)
        }
    }
}
