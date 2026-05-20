import Foundation

/// v1.0-alpha.17 — Watch-target localization helper. The Watch target
/// ships its own `Localizable.xcstrings` (Watch/Resources/) with the
/// 12 wrist-sized strings the cockpit needs in FR + EN. This helper
/// matches the iPhone host's `.localized` extension shape so the
/// views read the same `key.watchLocalized` idiom.
///
/// Bundle resolution lives in `Bundle.main` because the Watch app is
/// a stand-alone bundle (no embedded frameworks the strings could
/// live in). Calling `NSLocalizedString` directly is fine — every
/// string ships in the per-language `Localizable.xcstrings` already.
extension String {
    var watchLocalized: String {
        NSLocalizedString(self, bundle: .main, comment: "")
    }
}
