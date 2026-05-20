import SwiftUI

/// Mirror of the MIND Liquid palette, hard-coded here so the widget
/// extension doesn't have to embed DesignSystem's full Asset Catalog.
/// Values are the same as `Modules/DesignSystem/Sources/Tokens.swift` and
/// the matching `.colorset` files under `App/Resources/Assets.xcassets`.
enum WidgetPalette {
    static let lavender = Color(red: 0xD7 / 255, green: 0xCB / 255, blue: 0xFF / 255)
    static let iris     = Color(red: 0xB7 / 255, green: 0xAB / 255, blue: 0xFF / 255)
    static let aqua     = Color(red: 0xA8 / 255, green: 0xE6 / 255, blue: 0xE0 / 255)
    static let sky      = Color(red: 0xCB / 255, green: 0xE6 / 255, blue: 0xF5 / 255)
    static let blush    = Color(red: 0xFF / 255, green: 0xDB / 255, blue: 0xE6 / 255)
    static let pearl    = Color(red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xFA / 255)

    static let background = LinearGradient(
        colors: [lavender, iris.opacity(0.85), aqua.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
