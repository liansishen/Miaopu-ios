import SwiftUI
import WidgetKit

private struct MatchesEntry: TimelineEntry {
    let date: Date
    let matches: [WidgetMatchSnapshot]
}

private struct MatchesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatchesEntry {
        MatchesEntry(date: .now, matches: [WidgetMatchSnapshot(
            id: "sample", date: .now, homeTeam: "主队", awayTeam: "客队", homeScore: nil,
            awayScore: nil, competition: "赛事", deepLinkURL: URL(string: "miaopu://match/sample")!
        )])
    }

    func getSnapshot(in context: Context, completion: @escaping (MatchesEntry) -> Void) {
        completion(MatchesEntry(date: .now, matches: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatchesEntry>) -> Void) {
        let entry = MatchesEntry(date: .now, matches: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private struct SingleMatchWidgetView: View {
    let entry: MatchesEntry

    var body: some View {
        Group {
            if let match = entry.matches.first {
                VStack(alignment: .leading, spacing: 9) {
                    Text(match.competition).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack {
                        Text(match.homeTeam).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(score(match)).font(.title3.bold()).monospacedDigit()
                        Spacer(minLength: 4)
                        Text(match.awayTeam).lineLimit(1)
                    }
                    Text(match.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
                .widgetURL(match.deepLinkURL)
            } else {
                ContentUnavailableView("暂无赛况", systemImage: "sportscourt", description: Text("打开喵扑查看赛程"))
                    .widgetURL(URL(string: "miaopu://match"))
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func score(_ match: WidgetMatchSnapshot) -> String {
        guard let home = match.homeScore, let away = match.awayScore else { return "vs" }
        return "\(home) - \(away)"
    }
}

private struct RecentMatchesWidgetView: View {
    let entry: MatchesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近期赛程").font(.headline)
            if entry.matches.isEmpty {
                Text("暂无赛程").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.matches.prefix(4)) { match in
                    Link(destination: match.deepLinkURL) {
                        HStack(spacing: 6) {
                            Text(match.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                .frame(width: 42, alignment: .leading)
                            Text(match.homeTeam).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(score(match)).fontWeight(.semibold).monospacedDigit()
                            Spacer(minLength: 2)
                            Text(match.awayTeam).lineLimit(1)
                        }
                        .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding()
        .widgetURL(entry.matches.first?.deepLinkURL ?? URL(string: "miaopu://match"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func score(_ match: WidgetMatchSnapshot) -> String {
        guard let home = match.homeScore, let away = match.awayScore else { return "vs" }
        return "\(home):\(away)"
    }
}

struct MatchWidget: Widget {
    let kind = "MiaopuSingleMatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatchesProvider()) { entry in
            SingleMatchWidgetView(entry: entry)
        }
        .configurationDisplayName("单场赛况")
        .description("查看最近一场比赛的比分")
        .supportedFamilies([.systemSmall])
    }
}

struct RecentMatchesWidget: Widget {
    let kind = "MiaopuRecentMatchesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatchesProvider()) { entry in
            RecentMatchesWidgetView(entry: entry)
        }
        .configurationDisplayName("近期赛程")
        .description("快速浏览近期比赛")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct MiaopuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MatchWidget()
        RecentMatchesWidget()
    }
}
