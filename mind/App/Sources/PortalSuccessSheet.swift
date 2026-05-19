import SwiftUI
import DesignSystem

/// v0.21 — Identifier wrapper so `.sheet(item:)` binding works with a
/// plain URL (which isn't `Identifiable` by default). Hashing on the
/// absolute string keeps the diff cheap and avoids accidentally re-
/// presenting the sheet when the user dismisses and re-opens the
/// AuditSheet on the same audit.
struct PortalShareItem: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Bottom sheet shown after the user taps "Generate Client Portal" on
/// the AuditSheet's ExportSheet. Surfaces the freshly-written folder
/// with two CTAs:
///
///   - **Open in Files** — opens the system Files app at the folder
///     so the user can drag-drop it onto Vercel / Cloudflare Pages
///     or AirDrop it to a teammate.
///   - **Share folder** — `UIActivityViewController` lets the user
///     share via Messages, AirDrop, Files, etc. The system picks the
///     right activity per-app (Files compresses to .zip on drag).
///
/// The sheet's body is intentionally minimal — the value is the
/// generated folder, not this view. Liquid Glass card + iris accent
/// to match the rest of the AuditSheet.
struct PortalSuccessSheet: View {
    let folderURL: URL
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isPresentingActivity: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("audit.export.portal.success.title", bundle: .main)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(folderURL.lastPathComponent)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("audit.export.portal.success.body", bundle: .main)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Button(action: openInFiles) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("audit.export.portal.success.openInFiles", bundle: .main)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LiquidPalette.iris.opacity(0.18), in: .rect(cornerRadius: 14))
                    .foregroundStyle(LiquidPalette.iris)
                }
                .buttonStyle(.plain)

                Button(action: { isPresentingActivity = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("audit.export.portal.success.share", bundle: .main)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background { LiquidBackground().ignoresSafeArea() }
        .sheet(isPresented: $isPresentingActivity) {
            PortalActivityView(activityItems: [folderURL])
        }
    }

    /// Opens the Files app at the destination folder. iOS routes
    /// `shareddocuments://` URLs into Files when the app target
    /// declares `UISupportsDocumentBrowser`; for a sandbox path we
    /// fall back to `file://` which Files also handles on iOS 17+.
    private func openInFiles() {
        // Map `~/Library/.../Documents/client-portals/<slug>` to the
        // Files-app-readable `shareddocuments://` scheme. Strip the
        // sandbox prefix so the user lands at the right folder.
        let raw = folderURL.path
        let sharedURLString = "shareddocuments://\(raw)"
        if let url = URL(string: sharedURLString) {
            openURL(url)
        } else {
            // Fallback: open the file:// URL — iOS will route it to
            // Files (or the user's default file manager).
            openURL(folderURL)
        }
    }
}

/// UIKit bridge for `UIActivityViewController`. SwiftUI's `ShareLink`
/// can't share a folder URL on iOS 18; the activity controller route
/// is the only one that lets the user pick "Save to Files" / AirDrop /
/// Messages with a directory payload.
private struct PortalActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
