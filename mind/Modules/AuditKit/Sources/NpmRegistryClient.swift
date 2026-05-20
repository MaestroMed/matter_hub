import Foundation

/// v1.0-alpha.10 — Thin client around the public npm registry. No
/// auth required (the registry is public). Used by
/// `RepositoryAuditProbe` to decide whether a dependency is behind
/// `latest` and how heavy it is.
///
/// Aggressive on-disk caching (24h TTL under
/// `Documents/npm-cache/<name>.json`) so a repo audit doesn't fire a
/// thousand HTTP calls every run — the registry's `latest` rarely
/// changes minute-to-minute, and the audit signal cares about
/// "behind by 1+ majors" not "behind by the patch released 4 hours
/// ago". Soft-fails on every error: the probe treats nil as "no
/// info", which keeps the audit landing on degraded networks.
public actor NpmRegistryClient {

    public static let shared = NpmRegistryClient()

    /// Wire-format value type. `approximateSizeKB` is best-effort —
    /// the registry's `dist.unpackedSize` field is in bytes; we round
    /// to KB for the heavy-deps heuristic, leaving nil when the
    /// field is absent.
    public struct NpmPackageInfo: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let version: String
        public let approximateSizeKB: Int?

        public init(name: String, version: String, approximateSizeKB: Int? = nil) {
            self.name = name
            self.version = version
            self.approximateSizeKB = approximateSizeKB
        }
    }

    private let session: URLSession
    private let cacheTTL: TimeInterval

    public init(session: URLSession = .shared, cacheTTL: TimeInterval = 24 * 60 * 60) {
        self.session = session
        self.cacheTTL = cacheTTL
    }

    /// `GET https://registry.npmjs.org/<name>/latest`. Returns the
    /// cached entry when one is still fresh; otherwise fires the
    /// network call, caches the result, returns it. Throws on
    /// network failure / non-2xx — the probe catches and treats
    /// that as "no info" without surfacing it to the user.
    public func latest(packageName: String) async throws -> NpmPackageInfo {
        let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NpmRegistryError.invalidPackageName
        }
        // Cache hit?
        if let cached = await readCache(packageName: trimmed), isFresh(cached) {
            return cached.info
        }
        // Fetch fresh.
        guard let url = Self.latestURL(packageName: trimmed) else {
            throw NpmRegistryError.invalidPackageName
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MIND/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NpmRegistryError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NpmRegistryError.decode
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NpmRegistryError.http(http.statusCode)
        }
        let info: NpmPackageInfo
        do {
            let dto = try JSONDecoder().decode(LatestDTO.self, from: data)
            info = dto.packageInfo
        } catch {
            throw NpmRegistryError.decode
        }
        await writeCache(entry: CacheEntry(info: info, savedAt: Date()))
        return info
    }

    /// Pure URL builder exposed for tests. Returns nil for an empty
    /// or whitespace-only package name. Scoped names (`@scope/pkg`)
    /// are URL-encoded so the slash inside is preserved.
    public static func latestURL(packageName: String) -> URL? {
        let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Scoped packages keep their slash; we percent-encode the
        // `@` and let the slash through so the URL reads
        // `/@scope%2Fpkg/latest`. The registry accepts both shapes.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        return URL(string: "https://registry.npmjs.org/\(encoded)/latest")
    }

    /// Pure cache-key derivation exposed for tests. Scoped names
    /// `@scope/pkg` collapse their slash to `_` so the file system
    /// is happy: `@scope_pkg.json`.
    public static func cacheKey(packageName: String) -> String {
        let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "_empty" }
        return trimmed.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Cache I/O

    private struct CacheEntry: Codable {
        let info: NpmPackageInfo
        let savedAt: Date
    }

    private func isFresh(_ entry: CacheEntry) -> Bool {
        Date().timeIntervalSince(entry.savedAt) < cacheTTL
    }

    private func cacheDirectory() -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let dir = docs.appendingPathComponent("npm-cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
        }
        return dir
    }

    private func cacheURL(packageName: String) -> URL? {
        guard let dir = cacheDirectory() else { return nil }
        return dir.appendingPathComponent("\(Self.cacheKey(packageName: packageName)).json")
    }

    private func readCache(packageName: String) async -> CacheEntry? {
        guard let url = cacheURL(packageName: packageName) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CacheEntry.self, from: data)
        } catch {
            return nil
        }
    }

    private func writeCache(entry: CacheEntry) async {
        guard let info = Optional(entry.info),
              let url = cacheURL(packageName: info.name) else { return }
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: url, options: .atomic)
        } catch {
            // Soft-fail: caching is an optimisation, never a hard
            // failure path.
        }
    }
}

/// v1.0-alpha.10 — npm registry failure modes. Mirrors the
/// `GitHubClientError` shape so call sites can switch / log identically.
public enum NpmRegistryError: Error, Sendable, Equatable {
    case invalidPackageName
    case http(Int)
    case decode
    case network(String)

    public static func == (lhs: NpmRegistryError, rhs: NpmRegistryError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidPackageName, .invalidPackageName),
             (.decode, .decode):
            return true
        case let (.http(a), .http(b)):
            return a == b
        case let (.network(a), .network(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Wire format

/// `/registry/<pkg>/latest` wire shape. The full payload is large; we
/// project only what the audit signal needs: name, version, and the
/// optional `dist.unpackedSize` (bytes) which we round to KB.
private struct LatestDTO: Decodable {
    let name: String
    let version: String
    let dist: Dist?

    struct Dist: Decodable {
        let unpackedSize: Int?
    }

    var packageInfo: NpmRegistryClient.NpmPackageInfo {
        let sizeKB: Int?
        if let bytes = dist?.unpackedSize {
            sizeKB = max(0, bytes / 1024)
        } else {
            sizeKB = nil
        }
        return NpmRegistryClient.NpmPackageInfo(
            name: name,
            version: version,
            approximateSizeKB: sizeKB
        )
    }
}
