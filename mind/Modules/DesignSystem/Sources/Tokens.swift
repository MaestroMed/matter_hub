import SwiftUI

public enum LiquidPalette {
    public static let lavender = Color("Lavender", bundle: .main)
    public static let iris = Color("Iris", bundle: .main)
    public static let aqua = Color("Aqua", bundle: .main)
    public static let sky = Color("Sky", bundle: .main)
    public static let blush = Color("Blush", bundle: .main)
    public static let pearl = Color("Pearl", bundle: .main)
}

public enum LiquidGradient {
    public static let primary = LinearGradient(
        colors: [LiquidPalette.lavender, LiquidPalette.iris, LiquidPalette.sky],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let aurora = LinearGradient(
        colors: [LiquidPalette.iris.opacity(0.7), LiquidPalette.aqua.opacity(0.6), LiquidPalette.blush.opacity(0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let glassFill = LinearGradient(
        colors: [.white.opacity(0.55), .white.opacity(0.18)],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let glassStroke = LinearGradient(
        colors: [.white.opacity(0.85), .white.opacity(0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public enum LiquidMetrics {
    public static let cornerSmall: CGFloat = 16
    public static let cornerMedium: CGFloat = 24
    public static let cornerLarge: CGFloat = 32
    public static let cornerBlob: CGFloat = 48
    public static let spring: Animation = .spring(response: 0.45, dampingFraction: 0.72)
    public static let bounce: Animation = .spring(response: 0.35, dampingFraction: 0.55)
}
