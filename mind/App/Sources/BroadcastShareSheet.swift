import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import DesignSystem
import GraphCore
import LiveBroadcastKit

/// v0.22 — Bottom sheet surfaced the moment a live broadcast is
/// minted. Shows the broadcast URL, a Liquid-Glass tile with a
/// generated QR code, a "Copier le lien" button + native `ShareLink`,
/// and a footer hint explaining how to expose the local folder over
/// `cloudflared tunnel`, `ngrok`, `tailscale serve` or Vercel.
///
/// Lives outside `AuditSheet.swift` so the audit sheet keeps a tight
/// scope (mirrors the v0.21 `PortalSuccessSheet` split).
struct BroadcastShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Freshly-minted broadcast. The session's `suggestedURL` is the
    /// `file://…/<token>/index.html` Mehdi can immediately open in
    /// Safari to preview the live feed. Once exposed via cloudflared
    /// or Vercel, he updates the URL in the row inline if needed.
    let session: LiveBroadcastSession
    let clientName: String

    /// Fired the moment the user taps the "Copier le lien" button so
    /// the parent can pop a confirmation toast.
    var onCopied: () -> Void

    /// Editable surface for the URL — defaults to the
    /// `session.suggestedURL`, but Mehdi can paste the cloudflared
    /// tunnel URL right inside the sheet so the QR + copy actions
    /// reflect the truly public address.
    @State private var publicURLString: String

    init(
        session: LiveBroadcastSession,
        clientName: String,
        onCopied: @escaping () -> Void = {}
    ) {
        self.session = session
        self.clientName = clientName
        self.onCopied = onCopied
        _publicURLString = State(initialValue: session.suggestedURL.absoluteString)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                urlCard
                qrCard
                deployHint
                folderRow
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear {
            MINDTelemetry.info("liveBroadcast.shareSheet.opened", data: [
                "token_prefix": String(session.token.prefix(8)),
            ])
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(LiquidPalette.iris)
                    Text("audit.broadcast.sheet.title", bundle: .main)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                }
                Text("audit.broadcast.sheet.subtitle", bundle: .main)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(clientName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(.top, 2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - URL card

    private var urlCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "audit.broadcast.sheet.title", bundle: .main).uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                TextField("https://…", text: $publicURLString)
                    .textFieldStyle(.plain)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = publicURLString
                        LiquidHaptics.success()
                        MINDTelemetry.info("liveBroadcast.url.copied", data: [
                            "token_prefix": String(session.token.prefix(8)),
                        ])
                        onCopied()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc.fill")
                            Text("audit.broadcast.url.copy", bundle: .main)
                        }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(LiquidPalette.iris.opacity(0.16))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(LiquidPalette.iris.opacity(0.55), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)

                    if let url = URL(string: publicURLString) {
                        ShareLink(item: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text("audit.broadcast.url.copy", bundle: .main)
                                    .opacity(0)
                                    .overlay(alignment: .leading) {
                                        Text(verbatim: "Share")
                                    }
                                    .fixedSize()
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - QR card

    private var qrCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(spacing: 12) {
                Text("audit.broadcast.qr.title", bundle: .main)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                if let image = QRCodeGenerator.image(for: publicURLString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.system(size: 80))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Deploy hint

    private var deployHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "Deploy")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            Text("audit.broadcast.deploy.hint", bundle: .main)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
        }
    }

    // MARK: - Folder reveal

    private var folderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(LiquidPalette.iris)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.folderURL.lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: session.folderURL.deletingLastPathComponent().lastPathComponent + "/")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(item: session.folderURL) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(LiquidPalette.iris)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - QR generator

/// Wraps `CIQRCodeGenerator` so the share sheet doesn't have to deal
/// with `CIImage` / `CIContext` plumbing inline.
private enum QRCodeGenerator {
    static func image(for string: String) -> UIImage? {
        guard !string.isEmpty,
              let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // Higher error correction so the QR survives screenshots /
        // small displays.
        filter.correctionLevel = "H"
        guard let ciImage = filter.outputImage else { return nil }
        let scale: CGFloat = 8
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
