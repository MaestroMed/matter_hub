import SwiftUI

public struct LiquidSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    public init(text: Binding<String>, placeholder: String = "Search…") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(focused ? LiquidPalette.iris : .secondary)

            TextField(placeholder, text: $text)
                .focused($focused)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            focused ? LiquidPalette.iris.opacity(0.7) : .white.opacity(0.3),
                            lineWidth: focused ? 1.5 : 1
                        )
                }
        }
        .shadow(color: focused ? LiquidPalette.iris.opacity(0.3) : .clear, radius: 10, y: 4)
        .animation(LiquidMetrics.spring, value: focused)
        .animation(LiquidMetrics.spring, value: text.isEmpty)
    }
}
