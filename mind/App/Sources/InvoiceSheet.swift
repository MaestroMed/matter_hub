import SwiftUI
import UIKit
import QuickLook
import DesignSystem
import GraphCore
import InvoiceKit
import Settings  // MINDPreferences

/// v0.31 — Replaces the v0.30 `StripeInvoicePlaceholderSheet`. Real
/// invoicing flow: amount + VAT toggle + auto-templated description,
/// preview the rendered PDF in QuickLook, share it via the system
/// share sheet (Mail / Messages / AirDrop), or flip the invoice
/// status to `.paid`.
///
/// Sheet life:
///   1. Sheet opens with a fresh `Invoice` minted via `InvoiceFactory`
///      (sequential number + Stripe Payment Link derived from prefs).
///   2. The user can adjust amount / description before re-generating
///      — each "Mettre à jour" re-mints the PDF without bumping the
///      invoice number (the existing draft is updated in-place).
///   3. "Aperçu PDF" presents a QuickLook preview of the current
///      draft.
///   4. "Envoyer par mail" opens the system share sheet with the PDF.
///      The first share flips the draft to `.sent`.
///   5. "Marquer payé" flips status to `.paid` + fires confetti.
///
/// Triggered from:
///   - `PipelineView` Won column drop (replaces the placeholder).
///   - `ClientDetailView` "+Facture" button (future-extensible).
struct InvoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = MINDPreferences.shared

    let clientNodeID: UUID
    let initialClientName: String
    let initialClientEmail: String?

    /// The freshly-minted invoice, mutated as the user adjusts the
    /// form. `nil` until the async `mintInitialDraft` task lands the
    /// first draft (sub-second on the cold path).
    @State private var draft: Invoice?

    /// Mirrors of the editable fields. Bound to TextFields, copied
    /// onto a fresh `Invoice` whenever the user taps "Mettre à jour".
    @State private var amountText: String = ""
    @State private var vatOn: Bool = true
    @State private var descriptionText: String = ""
    @State private var emailText: String = ""

    /// QuickLook preview state. The previewURL is the on-disk path
    /// to the temporary PDF we render on demand.
    @State private var previewURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    var body: some View {
        ZStack {
            LiquidBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let draft {
                        numberCard(invoice: draft)
                    }
                    formCard
                    statusCard
                    actionButtons
                    if MINDPreferences.currentStripePaymentLinkBase() == nil {
                        stripeMissingHint
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .task {
            await mintInitialDraft()
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showShareSheet) {
            InvoiceActivityView(items: shareItems)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("invoice.sheet.title", bundle: .main)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(initialClientName)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Invoice number card

    private func numberCard(invoice: Invoice) -> some View {
        LiquidCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 26))
                    .foregroundStyle(LiquidGradient.primary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invoice.number)
                        .font(.system(.headline, design: .monospaced, weight: .semibold))
                        .monospacedDigit()
                    Text(invoice.issueDate.formatted(date: .long, time: .omitted))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: invoice.status)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                // Amount.
                VStack(alignment: .leading, spacing: 6) {
                    Text("invoice.field.amount", bundle: .main)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    TextField(
                        String(localized: "invoice.field.amount.placeholder", bundle: .main),
                        text: $amountText
                    )
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .onChange(of: amountText) { _, _ in updateDraft() }
                }

                // VAT toggle.
                HStack {
                    Text("invoice.field.vat", bundle: .main)
                        .font(.system(.body, design: .rounded, weight: .medium))
                    Spacer()
                    LiquidToggle(isOn: Binding(
                        get: { vatOn },
                        set: { newValue in
                            vatOn = newValue
                            updateDraft()
                        }
                    ))
                }

                Divider().background(.white.opacity(0.18))

                // Description.
                VStack(alignment: .leading, spacing: 6) {
                    Text("invoice.field.description", bundle: .main)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    TextField("", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .rounded))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .onChange(of: descriptionText) { _, _ in updateDraft() }
                }

                // Client email.
                VStack(alignment: .leading, spacing: 6) {
                    Text("invoice.field.clientEmail", bundle: .main)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    TextField("client@example.com", text: $emailText)
                        .font(.system(.body, design: .rounded))
                        .textFieldStyle(.plain)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .onChange(of: emailText) { _, _ in updateDraft() }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Status card

    @ViewBuilder
    private var statusCard: some View {
        if let draft {
            LiquidCard(cornerRadius: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total TTC")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                        Text(formatEUR(draft.amountTTC))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Échéance")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                        Text(draft.dueDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(.body, design: .rounded, weight: .medium))
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            LiquidButton(
                title: String(localized: "invoice.action.preview", bundle: .main),
                systemImage: "eye.fill"
            ) {
                presentPreview()
            }
            .disabled(draft == nil)

            HStack(spacing: 10) {
                Button {
                    presentShare()
                } label: {
                    Label(
                        String(localized: "invoice.action.share", bundle: .main),
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous).fill(LiquidPalette.iris.opacity(0.85))
                    )
                    .foregroundStyle(.white)
                }
                .disabled(draft == nil)

                Button {
                    markPaid()
                } label: {
                    Label(
                        String(localized: "invoice.action.markPaid", bundle: .main),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    )
                    .foregroundStyle(.primary)
                }
                .disabled(draft == nil || draft?.status == .paid)
            }
        }
    }

    private var stripeMissingHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("invoice.stripe.missing", bundle: .main)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                }
        }
    }

    // MARK: - Logic

    private func mintInitialDraft() async {
        guard draft == nil else { return }
        let initialAmount: Double = 0
        let initialVAT: Double = 20
        let initialDescription = InvoiceFactory.defaultDescription(for: initialClientName)
        let branding = brandingFromPreferences()

        let invoice = await InvoiceFactory.mintDraft(
            clientNodeID: clientNodeID,
            clientName: initialClientName,
            clientEmail: initialClientEmail,
            amountEUR: initialAmount,
            vatPercent: initialVAT,
            description: initialDescription,
            stripePaymentLinkBase: MINDPreferences.currentStripePaymentLinkBase(),
            branding: branding
        )
        MINDTelemetry.info(
            "invoice.draft.created",
            data: [
                "invoiceID": invoice.id.uuidString,
                "number": invoice.number,
                "clientID": clientNodeID.uuidString,
            ]
        )
        draft = invoice
        amountText = ""
        vatOn = invoice.vatPercent > 0
        descriptionText = invoice.description
        emailText = initialClientEmail ?? ""
    }

    /// Reflect form mutations onto the draft and persist. Fired on
    /// every `.onChange` so the previewed PDF / share payload always
    /// matches what the user sees in the form.
    private func updateDraft() {
        guard let current = draft else { return }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let vat = vatOn ? 20.0 : 0.0
        let stripeURL: String? = {
            guard let base = MINDPreferences.currentStripePaymentLinkBase() else { return nil }
            return InvoiceStripeLinkBuilder.appendAmount(base: base, amountEUR: amount + amount * vat / 100.0)
        }()
        let updated = Invoice(
            id: current.id,
            number: current.number,
            issueDate: current.issueDate,
            dueDate: current.dueDate,
            clientNodeID: current.clientNodeID,
            clientName: current.clientName,
            clientEmail: emailText.isEmpty ? nil : emailText,
            amountEUR: amount,
            vatPercent: vat,
            description: descriptionText,
            status: current.status,
            paidAt: current.paidAt,
            stripePaymentLinkURL: stripeURL,
            consultantBranding: current.consultantBranding
        )
        draft = updated
        Task { await InvoiceStore.shared.save(updated) }
    }

    private func presentPreview() {
        guard let draft else { return }
        let pdfData = InvoicePDFRenderer.render(draft)
        guard let url = writeToTempFile(data: pdfData, filenameHint: draft.number) else { return }
        MINDTelemetry.info(
            "invoice.pdf.exported",
            data: ["invoiceID": draft.id.uuidString, "number": draft.number]
        )
        previewURL = url
    }

    private func presentShare() {
        guard let draft else { return }
        let pdfData = InvoicePDFRenderer.render(draft)
        guard let url = writeToTempFile(data: pdfData, filenameHint: draft.number) else { return }
        shareItems = [url]
        showShareSheet = true
        if draft.status == .draft {
            Task {
                _ = await InvoiceStore.shared.markSent(
                    draft.id,
                    stripePaymentLinkURL: draft.stripePaymentLinkURL
                )
                if let refreshed = await InvoiceStore.shared.load(draft.id) {
                    await MainActor.run { self.draft = refreshed }
                }
            }
        }
    }

    private func markPaid() {
        guard let draft else { return }
        Task {
            _ = await InvoiceStore.shared.markPaid(draft.id)
            if let refreshed = await InvoiceStore.shared.load(draft.id) {
                await MainActor.run {
                    self.draft = refreshed
                    LiquidHaptics.success()
                }
            }
        }
    }

    private func brandingFromPreferences() -> ConsultantBranding {
        ConsultantBranding(
            name: "Mehdi Nafaa",
            address: MINDPreferences.currentConsultantAddress(),
            siret: MINDPreferences.currentConsultantSIRET(),
            vatNumber: MINDPreferences.currentConsultantVATNumber(),
            iban: MINDPreferences.currentConsultantIBAN(),
            email: "meehdi.n@gmail.com",
            phone: nil
        )
    }

    private func writeToTempFile(data: Data, filenameHint: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filenameHint).pdf")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            MINDTelemetry.warning(
                "invoice.pdf.write.failed",
                data: ["error": String(describing: error)]
            )
            return nil
        }
    }

    private func formatEUR(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) €"
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    let status: InvoiceStatus

    var body: some View {
        let key: String.LocalizationValue
        let tint: Color
        switch status {
        case .draft:
            key = "invoice.status.draft"; tint = LiquidPalette.sky
        case .sent:
            key = "invoice.status.sent"; tint = LiquidPalette.iris
        case .paid:
            key = "invoice.status.paid"; tint = .green
        case .overdue:
            key = "invoice.status.overdue"; tint = .orange
        }
        return Text(String(localized: key, bundle: .main))
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous).fill(tint.opacity(0.9))
            )
    }
}

// MARK: - Share sheet bridge

/// UIKit bridge for `UIActivityViewController`. SwiftUI's `ShareLink`
/// can attach a file URL directly but doesn't expose the
/// `completionWithItemsHandler` we may want later for telemetry, so
/// we keep the explicit bridge for consistency with PortalActivityView.
private struct InvoiceActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
