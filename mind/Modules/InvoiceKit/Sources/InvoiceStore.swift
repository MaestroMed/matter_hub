import Foundation
import GraphCore  // MINDTelemetry

/// v0.31 — On-disk store for `Invoice` values + the sequential
/// invoice-number counter.
///
/// Per-invoice persistence at `Documents/invoices/<uuid>.json` follows
/// the same single-file-per-record convention as
/// `OutreachKit.FollowUpStore` — keeps writes lock-free at the OS
/// level (the actor serialises concurrent writes anyway), and a
/// corrupt write of one invoice never takes the whole invoice state
/// down with it.
///
/// The sequential counter (`MIND-YYYY-0001`, `MIND-YYYY-0002`, …) is
/// stored separately at `Documents/invoices/_counter.json`. Two
/// invoices issued back-to-back can't collide because the actor
/// serialises `nextNumber()` reads + writes — even if the UI calls
/// it from two parallel `Task { }`s after the user double-taps the
/// "Won" drop, the counter ratchets monotonically.
public actor InvoiceStore {

    /// Shared singleton — the InvoiceSheet and the v0.31 follow-up
    /// "Relancer" card both reach this instance. Tests inject their
    /// own with a temp directory so the hermetic ratchet test never
    /// pollutes the dev sandbox.
    public static let shared = InvoiceStore()

    /// Root directory holding every invoice JSON file. Lazily
    /// created on the first write. `Documents/invoices/`.
    private let rootURL: URL

    /// Path to the sequential-number counter JSON. One file in the
    /// invoices folder keeps the ratchet atomic even if the user
    /// nukes individual invoices via Files.app — the next mint will
    /// still allocate a fresh number above the highest historical.
    private let counterURL: URL

    /// In-memory mirror of every invoice read so far. Populated on
    /// first access via `loadAllFromDisk()`; mutations write through
    /// to disk via `writeToDisk(_:)`. Lets the HomeView "Factures à
    /// relancer" card render without a filesystem round-trip per
    /// frame.
    private var cache: [UUID: Invoice] = [:]

    /// Tracks whether we've hydrated `cache` from disk yet. The first
    /// public read hydrates, every subsequent read goes straight to
    /// `cache` (cheap).
    private var hydrated: Bool = false

    public init(
        rootURL: URL = InvoiceStore.defaultRootURL()
    ) {
        self.rootURL = rootURL
        self.counterURL = rootURL.appendingPathComponent("_counter.json", isDirectory: false)
    }

    /// Default `Documents/invoices/` directory under the app sandbox.
    /// Static so the singleton + injected instances can share the
    /// same convention without duplicating the lookup.
    public nonisolated static func defaultRootURL() -> URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("invoices", isDirectory: true)
    }

    // MARK: - Sequential numbering

    /// Allocates the next sequential invoice number for the current
    /// year and persists the bumped counter to disk. Format is
    /// `MIND-YYYY-NNNN` (year-padded to 4 digits, ordinal padded to
    /// 4 digits, so the first invoice of 2026 reads "MIND-2026-0001").
    ///
    /// Resets the ordinal back to 1 when the year rolls over so 2027
    /// starts at "MIND-2027-0001" rather than continuing the 2026
    /// sequence — matches what every French accounting software does
    /// out of the box.
    public func nextNumber(now: Date = .now) async -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)

        let counter = loadCounter()
        let newOrdinal: Int
        if counter.year == year {
            newOrdinal = counter.ordinal + 1
        } else {
            newOrdinal = 1
        }

        let bumped = Counter(year: year, ordinal: newOrdinal)
        writeCounter(bumped)
        return Invoice.formatNumber(year: year, ordinal: newOrdinal)
    }

    /// Peeks at the next number that would be allocated without
    /// bumping the counter. Used by InvoiceSheet to preview the
    /// number before the user taps "Générer" — never call this to
    /// mint a real invoice, the counter would rewind.
    public func peekNumber(now: Date = .now) async -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        let counter = loadCounter()
        let preview = counter.year == year ? counter.ordinal + 1 : 1
        return Invoice.formatNumber(year: year, ordinal: preview)
    }

    // MARK: - CRUD

    /// Save (insert or replace) an invoice. Idempotent — the file is
    /// fully rewritten so a partial earlier write never sticks
    /// around. On disk failure, the mutation stays in-memory and a
    /// warning breadcrumb is emitted.
    public func save(_ invoice: Invoice) async {
        await hydrateIfNeeded()
        cache[invoice.id] = invoice
        writeToDisk(invoice)
    }

    /// Load a single invoice by id. Returns nil when the invoice has
    /// never been saved (or has been deleted). Soft-fails to nil
    /// when the on-disk file exists but is corrupt — the
    /// `MINDTelemetry` warning tells us about the regression without
    /// crashing the UI.
    public func load(_ id: UUID) async -> Invoice? {
        await hydrateIfNeeded()
        return cache[id]
    }

    /// Every invoice attached to a given client `Node`. Order is
    /// most-recent-first so the ClientDetailView shows the latest
    /// at the top of its list.
    public func allForClient(_ nodeID: UUID) async -> [Invoice] {
        await hydrateIfNeeded()
        return cache.values
            .filter { $0.clientNodeID == nodeID }
            .sorted { $0.issueDate > $1.issueDate }
    }

    /// Every invoice currently in the cache, regardless of client.
    /// Used by the HomeView "Factures à relancer" card to surface
    /// overdue invoices across all clients in one pass.
    public func allInvoices() async -> [Invoice] {
        await hydrateIfNeeded()
        return Array(cache.values)
    }

    /// Subset of `allInvoices()` that currently qualifies as overdue
    /// — status == .sent AND dueDate < now AND paidAt nil. Sorted
    /// oldest-due-first so the relance card surfaces the most
    /// urgent first.
    public func overdueInvoices(now: Date = .now) async -> [Invoice] {
        await hydrateIfNeeded()
        return cache.values
            .filter { $0.isOverdue(now: now) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    /// Flips an invoice's status to `.paid` and persists. Returns
    /// the updated invoice when found, nil when the id doesn't match
    /// any persisted invoice. Fires the `invoice.paid.marked`
    /// breadcrumb on success.
    @discardableResult
    public func markPaid(_ id: UUID, at when: Date = .now) async -> Invoice? {
        await hydrateIfNeeded()
        guard let existing = cache[id] else { return nil }
        let updated = existing.markedPaid(at: when)
        cache[id] = updated
        writeToDisk(updated)
        await telemetryInfo(
            "invoice.paid.marked",
            data: [
                "invoiceID": id.uuidString,
                "number": existing.number,
                "amountTTC": String(format: "%.2f", existing.amountTTC),
            ]
        )
        return updated
    }

    /// Flips an invoice's status to `.sent` and persists the Stripe
    /// link (if a fresh one was minted). Fires the `invoice.sent`
    /// breadcrumb.
    @discardableResult
    public func markSent(
        _ id: UUID,
        stripePaymentLinkURL: String? = nil
    ) async -> Invoice? {
        await hydrateIfNeeded()
        guard let existing = cache[id] else { return nil }
        let updated = existing.markedSent(stripePaymentLinkURL: stripePaymentLinkURL)
        cache[id] = updated
        writeToDisk(updated)
        await telemetryInfo(
            "invoice.sent",
            data: [
                "invoiceID": id.uuidString,
                "number": existing.number,
                "clientID": existing.clientNodeID.uuidString,
            ]
        )
        return updated
    }

    /// Deletes the invoice file + cache entry. Soft-fail.
    public func delete(_ id: UUID) async {
        cache.removeValue(forKey: id)
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes every persisted invoice + resets the counter. Used by
    /// tests + a future Settings "Clear all invoices" path.
    public func clearAll() async {
        cache.removeAll()
        try? FileManager.default.removeItem(at: rootURL)
        hydrated = true  // empty cache is a valid hydrated state
    }

    // MARK: - Disk I/O

    private func hydrateIfNeeded() async {
        guard !hydrated else { return }
        hydrated = true
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else { return }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            await telemetryWarning(
                "invoice.store.hydrate.failed",
                data: ["error": String(describing: error)]
            )
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json"
            && url.lastPathComponent != "_counter.json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let invoice = try decoder.decode(Invoice.self, from: data)
                cache[invoice.id] = invoice
            } catch {
                await telemetryWarning(
                    "invoice.store.decode.failed",
                    data: [
                        "file": url.lastPathComponent,
                        "error": String(describing: error),
                    ]
                )
            }
        }
    }

    private func writeToDisk(_ invoice: Invoice) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            Task { await telemetryWarning(
                "invoice.store.mkdir.failed",
                data: ["error": String(describing: error)]
            ) }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(invoice)
            try data.write(to: fileURL(for: invoice.id), options: [.atomic])
        } catch {
            Task { await telemetryWarning(
                "invoice.store.write.failed",
                data: [
                    "invoiceID": invoice.id.uuidString,
                    "error": String(describing: error),
                ]
            ) }
        }
    }

    private func fileURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    // MARK: - Counter file

    private struct Counter: Codable {
        let year: Int
        let ordinal: Int
    }

    /// Reads the counter from disk. Returns `(year: 0, ordinal: 0)`
    /// when the file doesn't exist yet — the first call to
    /// `nextNumber()` will then mint `MIND-<currentYear>-0001`.
    private func loadCounter() -> Counter {
        guard FileManager.default.fileExists(atPath: counterURL.path),
              let data = try? Data(contentsOf: counterURL) else {
            return Counter(year: 0, ordinal: 0)
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(Counter.self, from: data) {
            return decoded
        }
        // Counter file corrupt — log + start fresh. Better to skip a
        // few ordinals on next mint than to crash on an unreadable
        // JSON.
        Task { await telemetryWarning(
            "invoice.store.counter.decode.failed",
            data: [:]
        ) }
        return Counter(year: 0, ordinal: 0)
    }

    private func writeCounter(_ counter: Counter) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            Task { await telemetryWarning(
                "invoice.store.counter.mkdir.failed",
                data: ["error": String(describing: error)]
            ) }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(counter) {
            try? data.write(to: counterURL, options: [.atomic])
        }
    }

    // MARK: - Telemetry MainActor bridges

    /// `MINDTelemetry.info/warning` are MainActor-isolated; the actor
    /// hops through these wrappers so the breadcrumb fires on the
    /// MainActor without us polluting the call sites with explicit
    /// `await MainActor.run { }` blocks.
    private func telemetryInfo(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}
