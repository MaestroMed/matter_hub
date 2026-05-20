import UIKit

/// Centralised haptic feedback so every CTA across MIND speaks the
/// same tactile language. Using UIKit's UIFeedbackGenerator under the
/// hood (SwiftUI's `.sensoryFeedback(_:)` modifier shipped in iOS 17
/// but the imperative call here lets us trigger from any closure, not
/// just on view-state changes — e.g. from FocusController.end(), from
/// AuditController completion, from QuickCaptureSheet save).
///
/// Naming intent matches Apple's terminology so the right feel matches
/// the right semantic:
///   - `.tap()`     — light touch, used on every primary CTA press
///   - `.select()`  — medium thump, used when committing a choice
///                    (Save key, Start focus)
///   - `.success()` — three-pulse "done", used when something the user
///                    started actually completed (audit ready, focus
///                    session finished cleanly)
///   - `.warning()` — yellow-alert pulse, used for recoverable
///                    failures (audit failed, key invalid)
///   - `.error()`   — red-alert pulse, used for hard fails (network
///                    timeout, save failed)
///
/// All methods are `@MainActor` because UIFeedbackGenerator requires
/// the main thread, and they `prepare()` the generator before firing
/// so the haptic engine wakes up in time (saves the ~50ms cold-start
/// delay that otherwise makes the tap feel mushy).
@MainActor
public enum LiquidHaptics {
    /// Light tap. Default for "user pressed something" events.
    public static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Medium thump. Use when the user commits a meaningful choice
    /// (save key, start focus session, run audit).
    public static func select() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Three-pulse "done". Use when an async task the user kicked off
    /// completes successfully (audit synthesis ready, focus session
    /// ran to completion, save persisted to CloudKit).
    public static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Yellow-alert. Use for recoverable failures the user can fix
    /// (empty API key, invalid URL).
    public static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Hard error. Use when something the user asked for failed in a
    /// way they can't immediately recover from (network timeout, save
    /// failed).
    public static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
