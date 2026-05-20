import Foundation

/// v0.22.1 — Pure assembler that folds a stream of partial SFSpeech
/// results into a single canonical transcript string. Lives outside
/// the (future) `WatchVoiceCapture` actor so the SwiftUI surface +
/// the eventual CloudKit mirror agree on exactly the same
/// post-processing pipeline — newline-stripped, whitespace-collapsed,
/// duplicate-prefix-deduped — and so the contract is testable in
/// microseconds without spinning up `AVAudioEngine`.
///
/// SFSpeech partials grow monotonically: each new partial is the
/// best-guess full transcript so far, NOT a delta. The watchOS app's
/// recognition loop calls `assemble(_:)` with every partial as it
/// lands; the latest call wins. The static convenience
/// `assemble(from:)` accepts the array of every partial fragment
/// instead, picks the longest one, and applies the same normalisation
/// — used in the unit tests + the offline drain path that re-derives
/// a record from a fragment log.
public enum WatchCaptureTranscriptAssembler {

    /// Normalises a raw transcript fragment:
    ///
    /// 1. Strip leading + trailing whitespace and newlines.
    /// 2. Collapse any internal run of whitespace (incl. `\n`, `\t`)
    ///    into a single ASCII space — SFSpeech sometimes emits
    ///    line-broken fragments on watchOS when the recogniser
    ///    flushes mid-utterance.
    /// 3. Strip control characters (anything in
    ///    `CharacterSet.controlCharacters`).
    /// 4. Trim again post-collapse so a fragment that was all
    ///    whitespace returns `""`.
    public static func assemble(_ fragment: String) -> String {
        let stripped = fragment
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    /// Picks the *longest* fragment in the supplied array (SFSpeech
    /// partials are monotonically growing, so the longest is always
    /// the most complete), then normalises it via `assemble(_:)`.
    /// Returns `""` for an empty input — the caller decides whether
    /// to mark the record as `.failed` based on
    /// `hasUsableTranscript`.
    public static func assemble(from fragments: [String]) -> String {
        guard let longest = fragments.max(by: { lhs, rhs in
            lhs.count < rhs.count
        }) else {
            return ""
        }
        return assemble(longest)
    }

    /// Derives a short title from a transcript suitable for the
    /// `.capture` Node's `title` field. Takes the first sentence
    /// (split on `.` / `?` / `!` / `\n`), trims, and truncates to
    /// `maxLength` chars with a trailing ellipsis if cut. Returns
    /// `"Capture vocale"` for an empty transcript so the Node row
    /// always has a non-empty title — matches the existing iPhone
    /// `VoiceCapture` UX.
    public static func deriveTitle(
        from transcript: String,
        maxLength: Int = 60
    ) -> String {
        let normalised = assemble(transcript)
        guard !normalised.isEmpty else { return "Capture vocale" }

        let sentenceEnders: Set<Character> = [".", "?", "!"]
        var firstSentence = ""
        for char in normalised {
            if sentenceEnders.contains(char) { break }
            firstSentence.append(char)
        }
        let candidate = firstSentence.trimmingCharacters(in: .whitespaces)
        let base = candidate.isEmpty ? normalised : candidate

        if base.count <= maxLength { return base }
        let cutoff = base.index(base.startIndex, offsetBy: maxLength)
        return base[..<cutoff].trimmingCharacters(in: .whitespaces) + "…"
    }
}
