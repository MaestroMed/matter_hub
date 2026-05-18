import Foundation

public enum WhoisProbeError: Error, LocalizedError, Sendable {
    case invalidHost
    case requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidHost: return "Whois: hôte invalide."
        case .requestFailed(let code): return "Whois: échec (\(code))."
        }
    }
}

/// RDAP (RFC 9082+9083) lookup via the rdap.org redirect service — the
/// modern, JSON-native replacement for legacy whois. Returns the domain's
/// registrar and creation date, which gives us its age in years.
public enum WhoisProbe {
    public static func fetch(for host: String) async throws -> DomainFindings {
        let cleaned = host
            .lowercased()
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { throw WhoisProbeError.invalidHost }

        guard let url = URL(string: "https://rdap.org/domain/\(cleaned)") else {
            throw WhoisProbeError.invalidHost
        }

        var request = URLRequest(url: url)
        request.setValue("application/rdap+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WhoisProbeError.requestFailed(0)
        }
        // rdap.org redirects to the authoritative server; both 200 and 404
        // (unregistered) are useful outcomes, anything else we treat as a
        // soft fail and return a nil-shaped finding.
        guard (200..<300).contains(http.statusCode) else {
            return DomainFindings(registrar: nil, createdAt: nil, ageYears: nil)
        }

        let payload = (try? JSONDecoder().decode(RDAPResponse.self, from: data)) ?? RDAPResponse()
        let createdAt = payload.events?
            .first { $0.eventAction == "registration" }
            .flatMap { parseDate($0.eventDate) }

        let registrarName = payload.entities?
            .first { ($0.roles ?? []).contains("registrar") }
            .flatMap { extractName(from: $0) }

        let years = createdAt.map { Date.now.timeIntervalSince($0) / (365.25 * 24 * 3600) }

        return DomainFindings(
            registrar: registrarName,
            createdAt: createdAt,
            ageYears: years
        )
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        // RDAP dates are RFC 3339 with timezone.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func extractName(from entity: RDAPEntity) -> String? {
        // vCardArray is [ "vcard", [["fn", {}, "text", "<name>"], …] ]
        guard let vcard = entity.vcardArray else { return nil }
        // The wire-level shape is a generic array of mixed types — we use
        // JSONSerialization on the raw data to dig through it.
        guard let data = try? JSONEncoder().encode(vcard),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any],
              parsed.count >= 2,
              let entries = parsed[1] as? [[Any]] else { return nil }
        for entry in entries {
            if entry.count >= 4,
               let key = entry[0] as? String,
               key.lowercased() == "fn",
               let value = entry[3] as? String {
                return value
            }
        }
        return nil
    }
}

// MARK: - RDAP shapes (minimal subset we need)

private struct RDAPResponse: Decodable {
    var events: [RDAPEvent]?
    var entities: [RDAPEntity]?
}

private struct RDAPEvent: Decodable {
    let eventAction: String
    let eventDate: String?
}

private struct RDAPEntity: Decodable {
    let roles: [String]?
    let vcardArray: AnyCodable?
}

/// Lightweight `Any`-bridging Codable so we can decode RDAP's heterogeneous
/// vCardArray and round-trip it back through JSONSerialization for parsing.
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)         { self.value = v; return }
        if let v = try? container.decode(Int.self)          { self.value = v; return }
        if let v = try? container.decode(Double.self)       { self.value = v; return }
        if let v = try? container.decode(String.self)       { self.value = v; return }
        if let v = try? container.decode([AnyCodable].self) { self.value = v.map(\.value); return }
        if let v = try? container.decode([String: AnyCodable].self) {
            self.value = v.mapValues(\.value); return
        }
        self.value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:     try container.encode(v)
        case let v as Int:      try container.encode(v)
        case let v as Double:   try container.encode(v)
        case let v as String:   try container.encode(v)
        case let v as [Any]:    try container.encode(v.map(AnyCodable.init))
        case let v as [String: Any]: try container.encode(v.mapValues(AnyCodable.init))
        default: try container.encodeNil()
        }
    }
}
