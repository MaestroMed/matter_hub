#if canImport(UIKit)
import UIKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
#endif
import Foundation

/// v0.31 — Renders an `Invoice` as a single-page A4 PDF using
/// `UIGraphicsPDFRenderer`. The layout is deliberately understated
/// — Helvetica, monochrome strokes, two-column header — so the
/// resulting document reads as a *legal artefact* rather than a
/// marketing brochure. Clients pay invoices that look like invoices.
///
/// Lives in InvoiceKit so the test target can call it without
/// pulling in UIKit at the app layer. The renderer is pure-ish: same
/// `Invoice` → same `Data`, modulo the `issueDate` formatter locale
/// which we pin to `.current` deliberately so a French Mehdi sees
/// "19 mai 2026" while an EN-locale tester sees "May 19, 2026".
public enum InvoicePDFRenderer {

    /// A4 portrait at 72dpi (PDF native unit). Width × height = 595 × 842.
    /// We match the international stationery convention so the
    /// resulting PDF prints cleanly on any French / EU consultant's
    /// home printer without scaling artefacts.
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 48

    /// Renders the invoice and returns the PDF bytes. Returns an
    /// empty `Data` on platforms without UIKit so the test target on
    /// macOS (XCTest hosted on iOS Simulator) gets a non-nil but
    /// well-defined fallback. In practice this always runs in an iOS
    /// process so the empty branch never fires.
    public static func render(_ invoice: Invoice) -> Data {
        #if canImport(UIKit)
        let format = UIGraphicsPDFRendererFormat()
        let metadata: [String: Any] = [
            kCGPDFContextCreator as String: "MIND v0.31",
            kCGPDFContextAuthor as String:  invoice.consultantBranding.name,
            kCGPDFContextTitle as String:   "Facture \(invoice.number)",
            kCGPDFContextSubject as String: invoice.description,
        ]
        format.documentInfo = metadata

        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        return renderer.pdfData { context in
            context.beginPage()
            drawPage(invoice: invoice)
        }
        #else
        return Data()
        #endif
    }

    // MARK: - Drawing

    #if canImport(UIKit)
    private static func drawPage(invoice: Invoice) {
        let contentWidth = pageWidth - 2 * margin
        var cursorY: CGFloat = margin

        // -- 1. Header: consultant identity (left) + invoice label (right).
        cursorY = drawHeader(at: cursorY, contentWidth: contentWidth, invoice: invoice)
        cursorY += 18

        // -- 2. Two columns: consultant address (left) / client (right).
        cursorY = drawParties(at: cursorY, contentWidth: contentWidth, invoice: invoice)
        cursorY += 24

        // -- 3. Invoice metadata table.
        cursorY = drawMetadataRow(at: cursorY, contentWidth: contentWidth, invoice: invoice)
        cursorY += 24

        // -- 4. Line items table (single line for now).
        cursorY = drawLineItems(at: cursorY, contentWidth: contentWidth, invoice: invoice)
        cursorY += 12

        // -- 5. Totals (HT / TVA / TTC).
        cursorY = drawTotals(at: cursorY, contentWidth: contentWidth, invoice: invoice)
        cursorY += 18

        // -- 6. Payment block: Stripe Payment Link + QR + IBAN.
        cursorY = drawPaymentBlock(at: cursorY, contentWidth: contentWidth, invoice: invoice)

        // -- 7. Legal mentions pinned at page bottom.
        drawLegalFooter(invoice: invoice)
    }

    private static func drawHeader(
        at y: CGFloat,
        contentWidth: CGFloat,
        invoice: Invoice
    ) -> CGFloat {
        let brand = invoice.consultantBranding

        // Left: consultant name (large, semibold).
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 22)
                ?? UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.black,
        ]
        let nameRect = CGRect(x: margin, y: y, width: contentWidth * 0.55, height: 28)
        (brand.name as NSString).draw(in: nameRect, withAttributes: nameAttrs)

        // Right: "FACTURE" tag + invoice number, right-aligned.
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 11)
                ?? UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray,
            .kern: 2,
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        var tagAttrsWithAlign = tagAttrs
        tagAttrsWithAlign[.paragraphStyle] = paragraph

        let tagY = y
        let tagRect = CGRect(x: margin, y: tagY, width: contentWidth, height: 14)
        ("FACTURE" as NSString).draw(in: tagRect, withAttributes: tagAttrsWithAlign)

        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 16)
                ?? UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ]
        let numberRect = CGRect(x: margin, y: tagY + 16, width: contentWidth, height: 22)
        (invoice.number as NSString).draw(in: numberRect, withAttributes: numberAttrs)

        // Iris-tinted accent rule under the header.
        let ruleY = y + 44
        let ruleRect = CGRect(x: margin, y: ruleY, width: contentWidth, height: 1)
        UIColor(red: 0.42, green: 0.36, blue: 0.83, alpha: 1).setFill()
        UIRectFill(ruleRect)

        return ruleY + 2
    }

    private static func drawParties(
        at y: CGFloat,
        contentWidth: CGFloat,
        invoice: Invoice
    ) -> CGFloat {
        let columnWidth = contentWidth / 2 - 8

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 9)
                ?? UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
            .kern: 1.4,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 11)
                ?? UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black,
        ]

        // Left column: consultant block.
        ("ÉMETTEUR" as NSString).draw(
            in: CGRect(x: margin, y: y, width: columnWidth, height: 12),
            withAttributes: labelAttrs
        )
        var leftY = y + 14

        let brand = invoice.consultantBranding
        var leftLines: [String] = [brand.name]
        if let address = brand.address, !address.isEmpty {
            // Split multi-line addresses so each line wraps neatly.
            leftLines.append(contentsOf: address
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
        leftLines.append(brand.email)
        if let phone = brand.phone, !phone.isEmpty {
            leftLines.append(phone)
        }
        for line in leftLines {
            let r = CGRect(x: margin, y: leftY, width: columnWidth, height: 14)
            (line as NSString).draw(in: r, withAttributes: valueAttrs)
            leftY += 14
        }

        // Right column: client block.
        let rightX = margin + columnWidth + 16
        ("CLIENT" as NSString).draw(
            in: CGRect(x: rightX, y: y, width: columnWidth, height: 12),
            withAttributes: labelAttrs
        )
        var rightY = y + 14
        var rightLines: [String] = [invoice.clientName]
        if let email = invoice.clientEmail, !email.isEmpty {
            rightLines.append(email)
        }
        for line in rightLines {
            let r = CGRect(x: rightX, y: rightY, width: columnWidth, height: 14)
            (line as NSString).draw(in: r, withAttributes: valueAttrs)
            rightY += 14
        }

        return max(leftY, rightY)
    }

    private static func drawMetadataRow(
        at y: CGFloat,
        contentWidth: CGFloat,
        invoice: Invoice
    ) -> CGFloat {
        let cellW = contentWidth / 3
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 9)
                ?? UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
            .kern: 1.4,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 12)
                ?? UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black,
        ]

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = .current

        let pairs: [(String, String)] = [
            ("DATE D'ÉMISSION", formatter.string(from: invoice.issueDate)),
            ("ÉCHÉANCE",        formatter.string(from: invoice.dueDate)),
            ("RÉFÉRENCE",       invoice.number),
        ]

        var x = margin
        for pair in pairs {
            (pair.0 as NSString).draw(
                in: CGRect(x: x, y: y, width: cellW, height: 12),
                withAttributes: labelAttrs
            )
            (pair.1 as NSString).draw(
                in: CGRect(x: x, y: y + 14, width: cellW, height: 16),
                withAttributes: valueAttrs
            )
            x += cellW
        }

        return y + 34
    }

    private static func drawLineItems(
        at y: CGFloat,
        contentWidth: CGFloat,
        invoice: Invoice
    ) -> CGFloat {
        // Table header band.
        let headerHeight: CGFloat = 22
        let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: headerHeight)
        UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1).setFill()
        UIRectFill(headerRect)

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 10)
                ?? UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray,
            .kern: 1.2,
        ]
        let rightAlign = NSMutableParagraphStyle()
        rightAlign.alignment = .right
        var headerRightAttrs = headerAttrs
        headerRightAttrs[.paragraphStyle] = rightAlign

        let descColumnWidth = contentWidth * 0.62
        let priceColumnWidth = contentWidth * 0.38

        ("DESCRIPTION" as NSString).draw(
            in: CGRect(x: margin + 8, y: y + 6, width: descColumnWidth, height: 14),
            withAttributes: headerAttrs
        )
        ("MONTANT HT" as NSString).draw(
            in: CGRect(x: margin + descColumnWidth, y: y + 6, width: priceColumnWidth - 8, height: 14),
            withAttributes: headerRightAttrs
        )

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 12)
                ?? UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black,
        ]
        var bodyRightAttrs = bodyAttrs
        bodyRightAttrs[.paragraphStyle] = rightAlign

        let bodyY = y + headerHeight + 10
        let descRect = CGRect(
            x: margin + 8,
            y: bodyY,
            width: descColumnWidth,
            height: 100
        )
        // Wrap the description across multiple lines if needed.
        let descPara = NSMutableParagraphStyle()
        descPara.lineBreakMode = .byWordWrapping
        var wrappedAttrs = bodyAttrs
        wrappedAttrs[.paragraphStyle] = descPara
        (invoice.description as NSString).draw(in: descRect, withAttributes: wrappedAttrs)

        let priceRect = CGRect(
            x: margin + descColumnWidth,
            y: bodyY,
            width: priceColumnWidth - 8,
            height: 18
        )
        let priceText = formatEUR(invoice.amountHT)
        (priceText as NSString).draw(in: priceRect, withAttributes: bodyRightAttrs)

        // Bottom rule under the line.
        let ruleY = bodyY + 30
        let ruleRect = CGRect(x: margin, y: ruleY, width: contentWidth, height: 0.5)
        UIColor.lightGray.setFill()
        UIRectFill(ruleRect)

        return ruleY + 4
    }

    private static func drawTotals(
        at y: CGFloat,
        contentWidth: CGFloat,
        invoice: Invoice
    ) -> CGFloat {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 11)
                ?? UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 11)
                ?? UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black,
        ]
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 14)
                ?? UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.black,
        ]

        let rightCol: CGFloat = contentWidth * 0.4
        let leftCol: CGFloat = contentWidth - rightCol
        let labelX = margin + leftCol - 20
        let valueX = margin + leftCol + 20
        let rightAlign = NSMutableParagraphStyle()
        rightAlign.alignment = .right
        var labelRight = labelAttrs
        labelRight[.paragraphStyle] = rightAlign
        var valueRight = valueAttrs
        valueRight[.paragraphStyle] = rightAlign
        var totalRight = totalAttrs
        totalRight[.paragraphStyle] = rightAlign

        var rowY = y
        let lineHeight: CGFloat = 18

        ("Total HT" as NSString).draw(
            in: CGRect(x: margin, y: rowY, width: labelX - margin, height: lineHeight),
            withAttributes: labelRight
        )
        (formatEUR(invoice.amountHT) as NSString).draw(
            in: CGRect(x: valueX, y: rowY, width: contentWidth - (valueX - margin), height: lineHeight),
            withAttributes: valueRight
        )
        rowY += lineHeight

        let vatLine = String(format: "TVA %g %%", invoice.vatPercent)
        (vatLine as NSString).draw(
            in: CGRect(x: margin, y: rowY, width: labelX - margin, height: lineHeight),
            withAttributes: labelRight
        )
        (formatEUR(invoice.amountVAT) as NSString).draw(
            in: CGRect(x: valueX, y: rowY, width: contentWidth - (valueX - margin), height: lineHeight),
            withAttributes: valueRight
        )
        rowY += lineHeight + 4

        // Separator above the TTC total.
        let sepRect = CGRect(x: margin + leftCol - 40, y: rowY, width: rightCol + 40, height: 0.5)
        UIColor.darkGray.setFill()
        UIRectFill(sepRect)
        rowY += 6

        ("Total TTC" as NSString).draw(
            in: CGRect(x: margin, y: rowY, width: labelX - margin, height: 22),
            withAttributes: totalRight
        )
        (formatEUR(invoice.amountTTC) as NSString).draw(
            in: CGRect(x: valueX, y: rowY, width: contentWidth - (valueX - margin), height: 22),
            withAttributes: totalRight
        )
        rowY += 22

        return rowY
    }

    private static func drawPaymentBlock(
        at y: CGFloat,
        contentWidth: CGFloat,
        invoice: Invoice
    ) -> CGFloat {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 9)
                ?? UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
            .kern: 1.4,
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 10)
                ?? UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.black,
        ]

        var cursorY = y
        ("PAIEMENT" as NSString).draw(
            in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 12),
            withAttributes: labelAttrs
        )
        cursorY += 14

        let brand = invoice.consultantBranding

        // Stripe Payment Link as text + QR code.
        if let link = invoice.stripePaymentLinkURL, !link.isEmpty {
            ("Lien Stripe Payment Link :" as NSString).draw(
                in: CGRect(x: margin, y: cursorY, width: contentWidth - 110, height: 14),
                withAttributes: valueAttrs
            )
            cursorY += 14
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Courier", size: 9)
                    ?? UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor(red: 0.42, green: 0.36, blue: 0.83, alpha: 1),
            ]
            let linkRect = CGRect(x: margin, y: cursorY, width: contentWidth - 110, height: 36)
            let linkPara = NSMutableParagraphStyle()
            linkPara.lineBreakMode = .byCharWrapping
            var linkAttrsWithPara = linkAttrs
            linkAttrsWithPara[.paragraphStyle] = linkPara
            (link as NSString).draw(in: linkRect, withAttributes: linkAttrsWithPara)

            // QR code top-right, anchored to the same baseline.
            if let qr = makeQRCode(payload: link, side: 96) {
                let qrRect = CGRect(
                    x: margin + contentWidth - 96,
                    y: cursorY - 14,
                    width: 96,
                    height: 96
                )
                qr.draw(in: qrRect)
            }
            cursorY += 46
        }

        if let iban = brand.iban, !iban.isEmpty {
            ("Virement bancaire — IBAN" as NSString).draw(
                in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 14),
                withAttributes: valueAttrs
            )
            cursorY += 14
            let ibanAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Courier-Bold", size: 11)
                    ?? UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.black,
            ]
            (iban as NSString).draw(
                in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 14),
                withAttributes: ibanAttrs
            )
            cursorY += 18
        }

        return cursorY
    }

    private static func drawLegalFooter(invoice: Invoice) {
        let footerY = pageHeight - 90
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 8)
                ?? UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.darkGray,
        ]

        // Top rule.
        let ruleRect = CGRect(x: margin, y: footerY, width: pageWidth - 2 * margin, height: 0.5)
        UIColor.lightGray.setFill()
        UIRectFill(ruleRect)

        var lines: [String] = []
        let brand = invoice.consultantBranding

        // Mentions légales obligatoires (FR).
        if let siret = brand.siret, !siret.isEmpty {
            lines.append("SIRET : \(siret)")
        } else {
            lines.append("SIRET : en cours d'immatriculation")
        }

        if let vatNumber = brand.vatNumber, !vatNumber.isEmpty {
            lines.append("TVA intracommunautaire : \(vatNumber)")
        } else if invoice.vatPercent == 0 {
            lines.append("TVA non applicable, art. 293 B du CGI")
        }

        lines.append(
            "Conditions de paiement : règlement à 30 jours. " +
            "Pénalités de retard : 3 fois le taux d'intérêt légal. " +
            "Indemnité forfaitaire pour frais de recouvrement : 40 €."
        )
        lines.append(
            "Aucun escompte accordé pour règlement anticipé."
        )

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.alignment = .center
        var attrs = footerAttrs
        attrs[.paragraphStyle] = para

        var y = footerY + 6
        for line in lines {
            let rect = CGRect(x: margin, y: y, width: pageWidth - 2 * margin, height: 22)
            (line as NSString).draw(in: rect, withAttributes: attrs)
            y += 14
        }
    }

    // MARK: - QR code

    private static func makeQRCode(payload: String, side: CGFloat) -> UIImage? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaleX = side / output.extent.size.width
        let scaleY = side / output.extent.size.height
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Currency formatter

    private static func formatEUR(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) €"
    }
    #endif
}
