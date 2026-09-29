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
    @State private var selectedTab = 0
    @State private var homePath: [String] = []
    @AppStorage("subscribedSports") private var subscribedSports = "lol,valorant,cs2,basketball,football"

    private var subscribed: [SportCategory] {
        var seen = Set<SportCategory>()
        return subscribedSports.split(separator: ",")
            .compactMap { SportCategory(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                HomeScreen(state: state, sports: subscribed)
                    .navigationDestination(for: String.self) { id in
                        if let match = state.matches.values.flatMap({ $0 }).first(where: { $0.id == id }) {
                            MatchDetailScreen(match: match)
                        } else {
                            ContentUnavailableView("未找到比赛", systemImage: "sportscourt")
                        }
                    }
            }
            .tabItem { Label("首页", systemImage: "house") }
            .tag(0)

            NavigationStack {
                EventsScreen(state: state)
            }
            .tabItem { Label("赛事", systemImage: "calendar") }
            .tag(1)

            NavigationStack {
                ProfileScreen(subscribedSports: $subscribedSports, session: session)
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .tag(2)
        }
        .tint(.orange)
        .environmentObject(session)
        .task { await session.restore() }
        .onChange(of: subscribedSports) {
            WidgetSnapshotStore.save(from: subscribed.flatMap { state.matches[$0] ?? [] })
        }
        .onReceive(state.$matches) { available in
            WidgetSnapshotStore.save(from: subscribed.flatMap { available[$0] ?? [] })
        }
        .onOpenURL(perform: openWidgetLink)
    }

    private func openWidgetLink(_ url: URL) {
        guard url.scheme == "miaopu", url.host == "match",
              let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return }
        selectedTab = 0
        Task {
            for sport in SportCategory.allCases {
                if state.matches.values.contains(where: { $0.contains(where: { $0.id == id }) }) { break }
                await state.load(sport)
            }
            homePath = [id]
        }
    }
}

private struct HomeScreen: View {
    @ObservedObject var state: ScheduleState
    let sports: [SportCategory]

    private var days: [MatchDay] {
        MatchDay.home(sports.flatMap { state.matches[$0] ?? [] })
    }

    private var isLoading: Bool {
        sports.contains { state.loading.contains($0) }
    }

    private func refresh() async {
        for sport in sports { await state.load(sport, force: true) }
    }

    var body: some View {
        List {
            if sports.isEmpty {
                ContentUnavailableView("还没有订阅赛事", systemImage: "calendar.badge.plus", description: Text("在「我的」中选择关注的赛事。"))
            } else {
                Section {
                    if days.isEmpty && isLoading {
                        ProgressView("正在加载赛程")
                    } else if days.isEmpty {
                        Text("近期暂无比赛")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("近期赛程")
                        Spacer()
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("刷新赛程")
                        .disabled(isLoading)
                    }
                }
                ForEach(days) { day in
                    Section(day.title) {
                        ForEach(day.matches) { match in
                            NavigationLink {
                                MatchDetailScreen(match: match)
                            } label: {
                                MatchRow(match: match)
                            }
                        }
                    }
                }
                ForEach(sports.filter { state.failures[$0] != nil }) { sport in
                    Section(sportName(sport)) {
                        ErrorRow(message: state.failures[sport] ?? "加载失败") {
                            Task { await state.load(sport, force: true) }
                        }
                    }
                }
            }
        }
        .navigationTitle("喵扑")
        .refreshable { await refresh() }
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
                ForEach(MatchDay.group(state.results(for: selected, search: search))) { day in
                    Section(day.title) {
                        ForEach(day.matches) { match in
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
        .navigationTitle("赛事")
        .safeAreaInset(edge: .top) {
            Picker("赛事项目", selection: $selected) {
                ForEach(SportCategory.allCases) { sport in
                    Text(sportName(sport)).tag(sport)
                }
            }
            .accessibilityIdentifier("sport-picker")
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
        VStack(alignment: .leading, spacing: 10) {
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
                team(match.homeName, logo: match.homeLogoURL)
                Spacer(minLength: 4)
                Text(score(match.homeScore))
                    .font(.title3.bold())
                Text(":")
                    .foregroundStyle(.secondary)
                Text(score(match.awayScore))
                    .font(.title3.bold())
                Spacer(minLength: 4)
                team(match.awayName, logo: match.awayLogoURL)
            }
            HStack {
                Text(dateText(match.startTime))
                Spacer()
                if let count = match.scoreCountText { Text(count) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("match-\(match.id)")
    }

    private func team(_ name: String, logo: URL?) -> some View {
        VStack(spacing: 4) {
            TeamLogo(url: logo, name: name, size: 32)
            Text(name).lineLimit(1).font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    private func score(_ value: Int?) -> String { value.map(String.init) ?? "-" }
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
            Section("应用") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        .foregroundStyle(.secondary)
                }
                Link("查看 CI 构建", destination: URL(string: "https://github.com/liansishen/Miaopu-ios/actions/workflows/ios.yml")!)
                Text("CI 提供的 IPA 未签名，安装前需另行签名。")
                    .font(.caption)
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

    private var ordered: [SportCategory] {
        var seen = Set<SportCategory>()
        let chosen = subscribedSports.split(separator: ",")
            .compactMap { SportCategory(rawValue: String($0)) }
        return (chosen + SportCategory.allCases).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            ForEach(ordered) { sport in
                Button {
                    var ids = subscribedSports.split(separator: ",").map(String.init)
                    if ids.contains(sport.rawValue) {
                        ids.removeAll { $0 == sport.rawValue }
                    } else {
                        ids.append(sport.rawValue)
                    }
                    subscribedSports = ids.joined(separator: ",")
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
            .onMove { offsets, destination in
                var items = ordered
                items.move(fromOffsets: offsets, toOffset: destination)
                subscribedSports = items.filter { selected.contains($0.rawValue) }
                    .map(\.rawValue).joined(separator: ",")
            }
        }
        .navigationTitle("赛事订阅")
        .toolbar { EditButton() }
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
