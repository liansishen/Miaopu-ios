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
                        .accessibilityIdentifier("home-refresh")
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
    @State private var scrubIndex: Int?
    @State private var scrubTitle: String?
    @State private var scrubFraction: CGFloat = 0

    private var days: [MatchDay] {
        MatchDay.group(state.results(for: selected, search: search))
    }

    private var isLoading: Bool { state.loading.contains(selected) }

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if let failure = state.failures[selected] {
                        ErrorRow(message: failure) { Task { await state.load(selected, force: true) } }
                            .padding(24)
                    } else if isLoading && state.matches[selected] == nil {
                        ProgressView("正在加载赛程")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else if days.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .padding(.top, 48)
                    } else {
                        ForEach(days) { day in
                            Section {
                                ForEach(day.matches) { match in
                                    NavigationLink {
                                        MatchDetailScreen(match: match)
                                    } label: {
                                        MatchRow(match: match)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                    Divider().padding(.leading, 16)
                                }
                            } header: {
                                dayBand(day).id(day.id)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .overlay(alignment: .trailing) {
                if days.count > 1 { scrubber(proxy) }
            }
            .overlay { scrubBubble }
            .navigationTitle("赛事")
            .safeAreaInset(edge: .top) { sportPicker }
            .searchable(text: $search, prompt: "搜索队伍或赛事")
            .refreshable { await state.load(selected, force: true) }
            .task(id: selected) { await state.load(selected) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { jumpToToday(proxy) } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityIdentifier("jump-today")
                    .accessibilityLabel("跳到今天")
                    .disabled(days.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await state.load(selected, force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新赛程")
                    .accessibilityIdentifier("events-refresh")
                    .disabled(isLoading)
                }
            }
        }
    }

    private var sportPicker: some View {
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

    /// 日期分隔条：今天用强调色圆点标记，右侧显示当天场次数量。
    private func dayBand(_ day: MatchDay) -> some View {
        HStack(spacing: 8) {
            if day.id == todayKey {
                Circle().fill(MiaopuStyle.accent).frame(width: 7, height: 7)
            }
            Text(day.title).font(.footnote.bold())
            Spacer()
            Text("\(day.matches.count) 场")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.regularMaterial)
    }

    /// 右侧快速滚动条：按下即显示日期，拖动时按比例定位到对应日期。
    private func scrubber(_ proxy: ScrollViewProxy) -> some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let count = days.count
            let thumbHeight = max(32, height * min(1, 8 / CGFloat(max(count, 1))))
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                Capsule()
                    .fill(MiaopuStyle.accent)
                    .frame(width: 4, height: thumbHeight)
                    .offset(y: scrubIndex == nil ? 0 : (height - thumbHeight) * scrubFraction)
                    .opacity(scrubIndex == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard count > 0 else { return }
                        let ratio = min(max(value.location.y / height, 0), 0.9999)
                        let index = min(Int(ratio * CGFloat(count)), count - 1)
                        scrubFraction = ratio
                        guard index != scrubIndex else { return }
                        scrubIndex = index
                        scrubTitle = days[index].title
                        proxy.scrollTo(days[index].id, anchor: .top)
                    }
                    .onEnded { _ in
                        scrubIndex = nil
                        scrubTitle = nil
                    }
            )
        }
        .frame(width: 44)
    }

    @ViewBuilder
    private var scrubBubble: some View {
        if let scrubTitle {
            GeometryReader { geo in
                let height = max(geo.size.height, 1)
                ScrubBubble(text: scrubTitle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 60)
                    .offset(y: min(max(scrubFraction * height - 20, 0), max(height - 44, 0)))
            }
            .allowsHitTesting(false)
        }
    }

    private func jumpToToday(_ proxy: ScrollViewProxy) {
        guard !days.isEmpty else { return }
        let target = days.first { $0.id >= todayKey } ?? days[days.count - 1]
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(target.id, anchor: .top)
        }
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
