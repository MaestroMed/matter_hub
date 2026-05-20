import Foundation

/// On-disk cache for synthesized pitch audio MP3s, keyed by
/// `auditID`. Writing through this actor keeps the AuditSheet
/// "Générer le pitch audio" button idempotent — tapping it twice
/// against the same report doesn't re-bill ElevenLabs per character.
///
/// File layout:
///   Documents/audit-audio/<auditID>.mp3
///
/// The folder is created on demand. Files persist indefinitely; the
/// host clears them via Settings → "Wipe all data" same as every
/// other on-disk MIND cache.
public actor AuditPitchAudioStore {
    public static let shared = AuditPitchAudioStore()

    public init() {}

    /// Writes `mp3Data` to `Documents/audit-audio/<auditID>.mp3` and
    /// returns the file URL so the caller can wire up AVAudioPlayer
    /// directly, or fold the file into the Client Portal HTML.
    @discardableResult
    public func save(mp3Data: Data, for auditID: UUID) throws -> URL {
        let folder = try Self.folderURL()
        let url = folder.appendingPathComponent("\(auditID.uuidString).mp3")
        try mp3Data.write(to: url, options: .atomic)
        return url
    }

    /// Returns the cached MP3 URL if it's on disk, or nil. Lets the
    /// AuditSheet show "Lire le pitch" without firing a network
    /// request, and the portal builder inline the bytes from disk.
    public func cachedURL(for auditID: UUID) -> URL? {
        guard let folder = try? Self.folderURL() else { return nil }
        let url = folder.appendingPathComponent("\(auditID.uuidString).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Reads the cached MP3 bytes if present, or nil. Used by the
    /// portal HTML builder to inline an `<audio>` element with a
    /// data URL.
    public func cachedBytes(for auditID: UUID) -> Data? {
        guard let url = cachedURL(for: auditID) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Removes the cached MP3 for `auditID`. Lets the "Régénérer"
    /// CTA force a fresh ElevenLabs round-trip when Mehdi tweaks the
    /// pitch text without rebuilding the cache key.
    public func clear(for auditID: UUID) {
        guard let url = cachedURL(for: auditID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Returns `Documents/audit-audio/`, creating it on demand. Made
    /// public-static so the tests can compute the expected path
    /// without reaching into actor isolation.
    public static func folderURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = docs.appendingPathComponent("audit-audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
        return folder
    }
}
