#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generates the three 1024×1024 PNGs MIND's AppIcon set expects so
// the Xcode asset compiler stops warning about missing files and
// TestFlight uploads stop being rejected at validation. The artwork
// is intentionally simple — a soft Liquid Glass gradient with a
// stylised "M" — meant as a placeholder until Mehdi commissions the
// final brand mark. Run with: `swift mind/tools/generate_app_icons.swift`.

let size = 1024
let outputDir = "mind/App/Resources/Assets.xcassets/AppIcon.appiconset"

enum Variant {
    case light
    case dark
    case tinted

    var filename: String {
        switch self {
        case .light:  return "MIND-AppIcon.png"
        case .dark:   return "MIND-AppIcon-Dark.png"
        case .tinted: return "MIND-AppIcon-Tinted.png"
        }
    }
}

// LiquidPalette mirrored from DesignSystem/Tokens.swift so the icon
// matches the in-app palette. Hex values are RGBA 0–255.
struct RGBA {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
    var cgColor: CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
}

let iris    = RGBA(r: 94,  g: 91,  b: 216, a: 1)   // #5E5BD8
let aqua    = RGBA(r: 94,  g: 233, b: 216, a: 1)   // #5EE9D8
let sky     = RGBA(r: 156, g: 195, b: 255, a: 1)   // #9CC3FF
let navy    = RGBA(r: 26,  g: 26,  b: 46,  a: 1)   // #1A1A2E
let twilight = RGBA(r: 15,  g: 52,  b: 96,  a: 1)  // #0F3460
let white   = RGBA(r: 255, g: 255, b: 255, a: 1)
let clear   = RGBA(r: 0,   g: 0,   b: 0,   a: 0)

func draw(_ variant: Variant) -> CGImage? {
    let bytesPerRow = size * 4
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ) else { return nil }

    // Background gradient or transparent fill depending on variant.
    let bgColors: [CGColor]
    switch variant {
    case .light:
        bgColors = [iris.cgColor, sky.cgColor, aqua.cgColor]
    case .dark:
        bgColors = [navy.cgColor, twilight.cgColor]
    case .tinted:
        // Apple's tinted variant uses an alpha-only mark over the
        // user's wallpaper-derived tint. Background must be fully
        // transparent so iOS owns the colour.
        bgColors = [clear.cgColor, clear.cgColor]
    }

    if variant != .tinted {
        let space = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: space,
            colors: bgColors as CFArray,
            locations: nil
        )!
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: CGFloat(size), y: CGFloat(size)),
            options: []
        )
    } else {
        // Make sure the buffer starts at fully transparent.
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Centered "M" glyph rendered as a vector path so it scales
    // crisply at 1024×1024 and downstream icon sizes (iOS auto-
    // generates @2x, @3x, app store at upload).
    let glyphColor: CGColor = (variant == .tinted) ? white.cgColor : white.cgColor
    ctx.setFillColor(glyphColor)
    ctx.setStrokeColor(glyphColor)
    ctx.setLineWidth(CGFloat(size) * 0.08)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // "M" silhouette: four points forming a peak-valley-peak.
    // Coordinates as fractions of the canvas so the proportions stay
    // consistent if we ever change `size`.
    let s = CGFloat(size)
    let p1 = CGPoint(x: s * 0.22, y: s * 0.30)  // bottom-left foot
    let p2 = CGPoint(x: s * 0.32, y: s * 0.72)  // top-left peak
    let p3 = CGPoint(x: s * 0.50, y: s * 0.42)  // middle valley
    let p4 = CGPoint(x: s * 0.68, y: s * 0.72)  // top-right peak
    let p5 = CGPoint(x: s * 0.78, y: s * 0.30)  // bottom-right foot

    ctx.beginPath()
    ctx.move(to: p1)
    ctx.addLine(to: p2)
    ctx.addLine(to: p3)
    ctx.addLine(to: p4)
    ctx.addLine(to: p5)
    ctx.strokePath()

    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// Generate each variant. Exit non-zero if any write fails so a CI
// invocation surfaces the problem instead of silently producing a
// half-empty asset catalog.
for variant in [Variant.light, .dark, .tinted] {
    guard let image = draw(variant) else {
        FileHandle.standardError.write(
            "Failed to draw \(variant.filename)\n".data(using: .utf8)!
        )
        exit(1)
    }
    let path = "\(outputDir)/\(variant.filename)"
    guard write(image, to: path) else {
        FileHandle.standardError.write(
            "Failed to write \(path)\n".data(using: .utf8)!
        )
        exit(2)
    }
    print("Wrote \(path)")
}
print("Done.")
