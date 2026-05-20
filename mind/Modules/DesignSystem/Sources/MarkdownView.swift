import SwiftUI

/// Pure markdown → AttributedString helper, isolated from any SwiftUI
/// view so the renderer can be exercised in unit tests without booting
/// a host app. Powers `MarkdownView` (block hierarchy) and the v0.5
/// Note editor's blur-to-render preview (whole-document attributed
/// string with inline emphasis + heading point sizes + .link
/// attributes via NSAttributedString.MarkdownParsingOptions).
public enum MarkdownRenderer {

    /// Parse the full document with `.full` syntax interpretation so
    /// headings, bullet/ordered lists, and links surface as distinct
    /// runs. Walks the result once and applies font + foreground
    /// styling per `presentationIntent` so the AttributedString feels
    /// rendered, not raw — and stays Liquid Glass-friendly.
    public static func attributedString(from markdown: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.allowsExtendedAttributes = true
        guard var attributed = try? AttributedString(
            markdown: markdown,
            options: options,
            baseURL: nil
        ) else {
            return AttributedString(markdown)
        }
        applyPresentationStyling(to: &attributed)
        return attributed
    }

    /// Walk every run; promote headings to a bigger rounded font,
    /// keep list/quote runs readable, and ensure links are visibly
    /// distinct via the inline `.link` attribute.
    private static func applyPresentationStyling(to attributed: inout AttributedString) {
        for run in attributed.runs {
            let range = run.range
            if let intent = run.presentationIntent {
                for component in intent.components {
                    switch component.kind {
                    case .header(level: let level):
                        let size = headerPointSize(for: level)
                        attributed[range].font = .system(
                            size: size,
                            weight: .semibold,
                            design: .rounded
                        )
                    case .blockQuote:
                        attributed[range].foregroundColor = .secondary
                    case .codeBlock:
                        attributed[range].font = .system(.callout, design: .monospaced)
                    default:
                        break
                    }
                }
            }
            if run.link != nil {
                attributed[range].foregroundColor = LiquidPalette.iris
                attributed[range].underlineStyle = .single
            }
        }
    }

    /// Heading point sizes mirror SwiftUI's title/title2/title3 stack
    /// so the editor preview matches the rest of MIND's typography.
    /// Exposed `public` so MarkdownRenderingTests can verify the
    /// monotonic decrease from level 1 → 6 without bridging through
    /// SwiftUI's opaque `Font` type.
    public static func headerPointSize(for level: Int) -> CGFloat {
        switch level {
        case 1:  return 28
        case 2:  return 22
        case 3:  return 19
        case 4:  return 17
        case 5:  return 15
        default: return 14
        }
    }

    /// True when the AttributedString contains at least one run whose
    /// presentation intent declares a header of the given level. Used
    /// by tests (and by the editor preview if it ever needs to scroll
    /// to a heading anchor).
    public static func containsHeader(level: Int, in attributed: AttributedString) -> Bool {
        for run in attributed.runs {
            guard let intent = run.presentationIntent else { continue }
            for component in intent.components {
                if case .header(level: let candidate) = component.kind, candidate == level {
                    return true
                }
            }
        }
        return false
    }
}

/// Block-level markdown renderer for the kind of text Claude returns
/// (headings, bullet lists, blockquotes, fenced code blocks, paragraphs
/// with inline emphasis / links / inline code).
///
/// SwiftUI's built-in `Text(AttributedString(markdown:))` is great for
/// the inline parts but flattens block syntax into one run, so headings
/// and lists lose their visual hierarchy. This view does the block
/// parsing itself and delegates inline parsing back to AttributedString.
public struct MarkdownView: View {
    private let source: String

    public init(_ source: String) {
        self.source = source
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block parsing

    private var blocks: [MarkdownBlock] {
        Self.parse(source)
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var inCodeFence = false
        var codeLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let joined = paragraphLines.joined(separator: " ")
            result.append(.paragraph(joined))
            paragraphLines.removeAll()
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCodeFence {
                if trimmed.hasPrefix("```") {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCodeFence = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                inCodeFence = true
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Headings
            if let level = headingLevel(of: trimmed) {
                flushParagraph()
                let stripped = trimmed
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                result.append(.heading(level: level, text: String(stripped)))
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                result.append(.bullet(text: String(trimmed.dropFirst(2))))
                continue
            }

            // Numbered list ("1. ", "12. ", etc.)
            if let dot = trimmed.firstIndex(of: "."),
               trimmed[trimmed.startIndex..<dot].allSatisfy({ $0.isNumber }),
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)].isWhitespace {
                flushParagraph()
                let number = Int(trimmed[trimmed.startIndex..<dot]) ?? 1
                let body = trimmed[trimmed.index(after: dot)...]
                    .trimmingCharacters(in: .whitespaces)
                result.append(.numbered(index: number, text: String(body)))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                result.append(.quote(text: String(trimmed.dropFirst(2))))
                continue
            }

            // Plain paragraph line — group consecutive lines
            paragraphLines.append(trimmed)
        }
        flushParagraph()
        if inCodeFence { result.append(.code(codeLines.joined(separator: "\n"))) }
        return result
    }

    static func headingLevel(of line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        guard count > 0, count <= 6 else { return nil }
        // Markdown requires a space after the # run.
        let after = line.index(line.startIndex, offsetBy: count, limitedBy: line.endIndex)
        guard let after, after < line.endIndex, line[after].isWhitespace else { return nil }
        return count
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(headingFont(for: level), design: .rounded, weight: .semibold))
                .padding(.top, level <= 2 ? 4 : 2)
                .padding(.bottom, 2)

        case let .paragraph(text):
            Text(inline(text))
                .font(.system(.subheadline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                Text(inline(text))
                    .font(.system(.subheadline, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case let .numbered(index, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index).")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .monospacedDigit()
                Text(inline(text))
                    .font(.system(.subheadline, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(LiquidPalette.iris.opacity(0.45))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .code(text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .textSelection(.enabled)
        }
    }

    private func headingFont(for level: Int) -> Font.TextStyle {
        switch level {
        case 1:  return .title2
        case 2:  return .title3
        case 3:  return .headline
        default: return .subheadline
        }
    }

    /// Apply Apple's inline markdown parser to a single line: bold,
    /// italic, links, inline code, strikethrough. Falls back to a plain
    /// AttributedString if parsing fails.
    private func inline(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

// MARK: - Block model

public enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String)
    case numbered(index: Int, text: String)
    case quote(text: String)
    case code(String)

    public var id: String {
        switch self {
        case let .heading(level, text):     return "h\(level)-\(text.hashValue)"
        case let .paragraph(text):          return "p-\(text.hashValue)"
        case let .bullet(text):             return "b-\(text.hashValue)"
        case let .numbered(index, text):    return "n\(index)-\(text.hashValue)"
        case let .quote(text):              return "q-\(text.hashValue)"
        case let .code(text):               return "c-\(text.hashValue)"
        }
    }
}
