import XCTest
import Foundation
@testable import InvoiceKit

/// v0.31 — One-shot helper that emits a sample MIND invoice PDF for
/// vision verification. Run via:
///
///   xcodebuild test -only-testing:MINDTests/InvoiceSampleEmitter
///
/// Writes to `mind/screenshots/v0.31-invoice.pdf` so the iteration
/// agent can hand the artefact to Mehdi (he opens it in Preview to
/// review the layout). Idempotent — running it twice produces the
/// same bytes (modulo `issueDate`, which we pin to a fixed date so
/// the file content is reproducible).
final class InvoiceSampleEmitter: XCTestCase {

    func test_emitInvoiceSamplePDF() throws {
        let issueDate = Date(timeIntervalSinceReferenceDate: 770_000_000)  // 2025-05-19-ish
        let branding = ConsultantBranding(
            name: "Mehdi Nafaa",
            address: "12 rue du Code\n75011 Paris",
            siret: "12345678901234",
            vatNumber: "FR12345678901",
            iban: "FR76 3000 6000 0112 3456 7890 189",
            email: "meehdi.n@gmail.com",
            phone: "+33 6 12 34 56 78"
        )
        let invoice = Invoice(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            number: "MIND-2026-0042",
            issueDate: issueDate,
            dueDate: Invoice.defaultDueDate(from: issueDate),
            clientNodeID: UUID(),
            clientName: "Acme SAS",
            clientEmail: "ops@acme.com",
            amountEUR: 4_500,
            vatPercent: 20,
            description:
                "Mission audit + recommandations pour Acme SAS\n" +
                "Sondes : performance, SEO, sécurité, brand, mobile.\n" +
                "Livrables : rapport PDF brandé, portail client, brief Claude Code.",
            status: .draft,
            paidAt: nil,
            stripePaymentLinkURL:
                "https://buy.stripe.com/3cs5ll?prefilled_amount=540000",
            consultantBranding: branding
        )

        let pdf = InvoicePDFRenderer.render(invoice)

        let outPath = ProcessInfo.processInfo.environment["MIND_INVOICE_SAMPLE_PATH"]
            ?? "/Users/mehdinafaa/Developer/matter_hub/mind/screenshots/v0.31-invoice.pdf"
        let url = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pdf.write(to: url, options: .atomic)
        print("Invoice sample written to: \(outPath) (\(pdf.count) bytes)")

        XCTAssertFalse(pdf.isEmpty)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)),
                      "Sample PDF must begin with the %PDF magic.")
    }
}
