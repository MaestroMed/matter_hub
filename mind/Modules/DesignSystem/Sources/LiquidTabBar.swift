import SwiftUI

public struct LiquidTab<Tag: Hashable>: Identifiable {
    public let id = UUID()
    public let icon: String
    public let tag: Tag

    public init(icon: String, tag: Tag) {
        self.icon = icon
        self.tag = tag
    }
}

public struct LiquidTabBar<Tag: Hashable>: View {
    @Binding var selection: Tag
    let leadingTabs: [LiquidTab<Tag>]
    let trailingTabs: [LiquidTab<Tag>]
    let onCapture: () -> Void

    public init(
        selection: Binding<Tag>,
        leading: [LiquidTab<Tag>],
        trailing: [LiquidTab<Tag>],
        onCapture: @escaping () -> Void
    ) {
        self._selection = selection
        self.leadingTabs = leading
        self.trailingTabs = trailing
        self.onCapture = onCapture
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(leadingTabs) { tab in
                pill(icon: tab.icon, tag: tab.tag)
            }

            Button {
                // Medium thump on the central +. Capture is the most
                // commit-flavoured action in the tab bar — meds a stronger
                // confirmation than a regular tap.
                LiquidHaptics.select()
                onCapture()
            } label: {
                ZStack {
                    Circle()
                        .fill(LiquidGradient.primary)
                        .frame(width: 56, height: 56)
                        .shadow(color: LiquidPalette.iris.opacity(0.5), radius: 14, y: 6)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .accessibilityLabel("Quick capture")

            ForEach(trailingTabs) { tab in
                pill(icon: tab.icon, tag: tab.tag)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(LiquidGradient.glassFill)
                        .opacity(0.4)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
    }

    @ViewBuilder
    private func pill(icon: String, tag: Tag) -> some View {
        Button {
            // Light tap on every tab switch — matches the standard
            // iOS tab bar feel and reassures the user the touch was
            // registered even when the underlying view takes a beat
            // to compose.
            LiquidHaptics.tap()
            withAnimation(LiquidMetrics.spring) { selection = tag }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selection == tag ? LiquidPalette.iris : .secondary)
                .frame(width: 48, height: 40)
        }
        // VoiceOver: every pill announces the tab it switches to.
        // Without this, the user just hears "icon" with no context.
        .accessibilityLabel(tabAccessibilityLabel(for: icon))
        .accessibilityAddTraits(selection == tag ? .isSelected : [])
    }

    /// Maps SF Symbol names to a human-readable label for VoiceOver.
    /// Centralised here because the same icon name is used in multiple
    /// callers; if we ever change the icon the label still makes sense.
    private func tabAccessibilityLabel(for icon: String) -> String {
        switch icon {
        case "house.fill":                                     return "Home"
        case "doc.text.fill":                                  return "Notes"
        case "point.3.filled.connected.trianglepath.dotted":   return "Graph"
        case "person.text.rectangle.fill":                     return "Clients"
        case "gearshape.fill":                                 return "Settings"
        default:                                               return "Tab"
        }
    }
}
