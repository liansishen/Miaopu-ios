import SwiftUI

/// 与安卓版对齐的尺寸、间距与配色令牌。颜色沿用应用现有的橙色强调色。
enum MiaopuStyle {
    static let accent = Color.orange
    static let danger = Color.red
    static let pageSpacing: CGFloat = 10
    static let cardMargin: CGFloat = 16
    static let cardRadius: CGFloat = 18

    static var cardBackground: Color { Color(.secondarySystemBackground) }
    static var trackBackground: Color { Color(.tertiarySystemFill) }
}

func formatScoreCount(_ count: Int) -> String {
    guard count >= 10_000 else { return String(count) }
    return String(format: "%.1f万", Double(count) / 10_000)
}

extension Color {
    init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let raw = UInt32(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((raw >> 16) & 0xFF) / 255,
            green: Double((raw >> 8) & 0xFF) / 255,
            blue: Double(raw & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 分数徽章配色：优先接口给出的日间/夜间色，否则按分数回退为主色或警示色。
func scoreColor(score: Double, dayHex: String?, nightHex: String?, scheme: ColorScheme) -> Color {
    let hex = scheme == .dark ? nightHex : dayHex
    if let hex, let color = Color(hexString: hex) { return color }
    return score >= 6.0 ? MiaopuStyle.danger : MiaopuStyle.accent
}

/// 页面主体：安卓版是背景之上的卡片流，卡片间距 10、底部留白 24。
struct CardFlow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: MiaopuStyle.pageSpacing) {
                content()
            }
            .padding(.top, MiaopuStyle.pageSpacing)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
    }
}

/// 整宽圆角卡片：左右外边距 16，内边距可调，可选点击。
struct MiaopuCard<Content: View>: View {
    var radius: CGFloat = MiaopuStyle.cardRadius
    var margin: CGFloat = MiaopuStyle.cardMargin
    var padding: CGFloat = 12
    var verticalPadding: CGFloat? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        cardSurface
            .padding(.horizontal, margin)
    }

    @ViewBuilder
    private var cardSurface: some View {
        let card = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding)
            .padding(.vertical, verticalPadding ?? padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(MiaopuStyle.cardBackground))
            .contentShape(RoundedRectangle(cornerRadius: radius))
        if let action {
            card.onTapGesture(perform: action)
        } else {
            card
        }
    }
}

enum DetailTabStyle {
    case page
    case map
    case team
}

/// 详情页标签：三种样式与安卓一致，超过三个标签时固定宽度并可横向滚动。
struct DetailTabs: View {
    let labels: [String]
    let selected: Int
    var style: DetailTabStyle = .map
    var logos: [URL?] = []
    let onSelect: (Int) -> Void

    private var connected: Bool { style != .map }
    private var spacing: CGFloat { connected ? 2 : 8 }
    private var overflowing: Bool { labels.count > 3 }
    private var fixedWidth: CGFloat? { overflowing ? 96 : nil }

    var body: some View {
        if labels.isEmpty {
            EmptyView()
        } else if overflowing {
            ScrollView(.horizontal, showsIndicators: false) {
                row.padding(.horizontal, 16)
            }
        } else {
            row.padding(.horizontal, 16)
        }
    }

    private var row: some View {
        HStack(spacing: spacing) {
            ForEach(labels.indices, id: \.self) { index in
                tab(index)
            }
        }
        .background {
            if connected {
                RoundedRectangle(cornerRadius: 50).fill(Color.primary.opacity(0.055))
            }
        }
    }

    private func tab(_ index: Int) -> some View {
        let active = index == selected
        let background: Color = connected
            ? (active ? indicatorColor : Color.clear)
            : (active ? MiaopuStyle.accent.opacity(0.14) : Color.primary.opacity(0.045))
        return Button { onSelect(index) } label: {
            HStack(spacing: 6) {
                if index < logos.count, let logo = logos[index] {
                    TeamLogo(url: logo, name: labels[index], size: 22)
                }
                Text(labels[index])
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(foreground(active: active))
            }
            .frame(maxWidth: fixedWidth == nil ? CGFloat.infinity : nil)
            .frame(width: fixedWidth)
            .frame(minHeight: connected ? 36 : 32)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 50).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(active)
    }

    private var indicatorColor: Color {
        style == .page ? MiaopuStyle.accent : Color(.secondarySystemBackground)
    }

    private func foreground(active: Bool) -> Color {
        guard active else { return .primary }
        switch style {
        case .page: return .white
        case .map: return MiaopuStyle.accent
        case .team: return .primary
        }
    }
}

/// 右对齐的文字排序选择器。
struct DetailOrderSelector: View {
    let labels: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                Button { onSelect(index) } label: {
                    Text(labels[index])
                        .font(.system(size: 11, weight: index == selected ? .semibold : .regular))
                        .foregroundStyle(index == selected ? MiaopuStyle.accent : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 统一的加载失败、加载中与空状态提示。
struct DetailNotice: View {
    let message: String
    var loading = false
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if loading {
                ProgressView()
            }
            if let onRetry {
                Button("重新加载", action: onRetry)
                    .buttonStyle(.borderless)
                    .foregroundStyle(MiaopuStyle.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

/// 队标：圆角方框、图片按容器缩放并内缩，无图时显示队名首字。
struct TeamLogo: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32)
                .fill(MiaopuStyle.trackBackground)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.15)
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
    }

    private var initial: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: max(11, size * 0.4), weight: .bold))
            .foregroundStyle(MiaopuStyle.accent)
    }
}

/// 选手头像：可选英雄小图角标。
struct PortraitView: View {
    let url: URL?
    var championURL: URL?
    let name: String
    var size: CGFloat = 48
    var cornerRadius: CGFloat?

    private var radius: CGFloat { cornerRadius ?? size * 0.18 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: radius).fill(MiaopuStyle.trackBackground)
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            initial
                        }
                    }
                } else {
                    initial
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius))

            if let championURL {
                let badge = max(14, size * 0.375)
                AsyncImage(url: championURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
                .frame(width: badge, height: badge)
                .clipShape(RoundedRectangle(cornerRadius: badge / 5))
                .padding(2)
                .background(RoundedRectangle(cornerRadius: badge / 4).fill(Color(.systemBackground)))
            }
        }
        .frame(width: size, height: size)
    }

    private var initial: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: max(12, size * 0.4), weight: .bold))
            .foregroundStyle(MiaopuStyle.accent)
    }
}

/// 分数徽章：宽度固定，底色为分数色的浅色。
struct ScoreBadge: View {
    let text: String
    var color: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color ?? .clear)
            .frame(width: 44)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill((color ?? .clear).opacity(0.1)))
    }
}

/// 小标签胶囊。
struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

/// 快速滚动时跟随手指显示的日期提示。
struct ScrubBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            )
    }
}

/// 热评条：浅色与深色使用不同的暖色底。
struct HotCommentBar: View {
    let text: String

    var body: some View {
        Text("“\(text)”")
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.hotCommentBackground))
    }
}

private extension Color {
    static var hotCommentBackground: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x38 / 255, green: 0x2F / 255, blue: 0x20 / 255, alpha: 1)
                : UIColor(red: 1, green: 0xF5 / 255, blue: 0xE3 / 255, alpha: 1)
        })
    }
}
