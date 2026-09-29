import SwiftUI

struct RemoteBadge: View {
    let url: URL?
    let name: String
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                    Text(String(name.prefix(1)))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }
}
