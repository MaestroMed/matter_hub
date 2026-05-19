import SwiftUI

public struct LiquidPill: View {
    let title: String?
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    public init(
        title: String? = nil,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                if let title, isActive {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(.horizontal, isActive ? 16 : 12)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(LiquidGradient.primary)
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                isActive ? .white.opacity(0.4) : .white.opacity(0.2),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(
                color: isActive ? LiquidPalette.iris.opacity(0.4) : .clear,
                radius: 10,
                y: 4
            )
            .animation(LiquidMetrics.spring, value: isActive)
        }
        .buttonStyle(.plain)
    }
}
