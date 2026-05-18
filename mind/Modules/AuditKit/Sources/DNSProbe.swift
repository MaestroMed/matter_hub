import Foundation

public enum DNSProbeError: Error, LocalizedError, Sendable {
    case invalidHost
    case requestFailed(Int)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHost: return "DNS: hôte invalide."
        case .requestFailed(let code): return "DNS: échec (\(code))."
        case .decodingFailed(let msg): return "DNS: décodage \(msg.prefix(120))."
        }
    }
}

/// DNS lookup over HTTPS via Cloudflare 1.1.1.1 (DoH JSON API, RFC 8484
/// JSON variant). No API key. We pull MX + TXT to figure out the email
/// provider, SPF presence, and DMARC presence — enough signal for an
/// audit headline without dragging a full DNS library into the app.
public enum DNSProbe {
    public static func fetch(for host: String) async throws -> EmailFindings {
        let cleaned = host.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { throw DNSProbeError.invalidHost }

        async let mx = query(name: cleaned, type: "MX")
        async let txt = query(name: cleaned, type: "TXT")
        async let dmarc = query(name: "_dmarc.\(cleaned)", type: "TXT")

        let mxRecords = try await mx
        let txtRecords = try await txt
        let dmarcRecords = try await dmarc

        let mxHosts = mxRecords
            .map { extractMXHost($0) }
            .filter { !$0.isEmpty }

        return EmailFindings(
            provider: inferProvider(from: mxHosts),
            mxHosts: mxHosts,
            hasSPF: txtRecords.contains(where: { $0.lowercased().contains("v=spf1") }),
            hasDMARC: dmarcRecords.contains(where: { $0.lowercased().contains("v=dmarc1") })
        )
    }

    // MARK: - Networking

    private static func query(name: String, type: String) async throws -> [String] {
        var components = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode(DOHResponse.self, from: data)
            return (decoded.Answer ?? []).map { $0.data.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        } catch {
            return []
        }
    }

    // MARK: - Inference

    private static func extractMXHost(_ raw: String) -> String {
        // MX records are "<priority> <hostname.>" — pull the hostname.
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let host = parts.last else { return "" }
        return String(host).trimmingCharacters(in: CharacterSet(charactersIn: " .\""))
    }

    private static func inferProvider(from mxHosts: [String]) -> String? {
        guard !mxHosts.isEmpty else { return nil }
        let joined = mxHosts.joined(separator: " ").lowercased()

        // Order matters: most-specific first.
        let table: [(needle: String, label: String)] = [
            ("google.com", "Google Workspace"),
            ("googlemail.com", "Google Workspace"),
            ("aspmx.l.google", "Google Workspace"),
            ("outlook.com", "Microsoft 365"),
            ("protection.outlook", "Microsoft 365"),
            ("messagingengine", "Fastmail"),
            ("zoho", "Zoho Mail"),
            ("infomaniak", "Infomaniak"),
            ("ovh", "OVH Mail"),
            ("gandi", "Gandi Mail"),
            ("mxhichina", "Alibaba Mail"),
            ("yandex", "Yandex Mail"),
            ("brevo", "Brevo"),
            ("sendinblue", "Brevo"),
            ("mailgun", "Mailgun"),
            ("sendgrid", "SendGrid"),
            ("postmarkapp", "Postmark"),
            ("mailchannels", "MailChannels"),
            ("amazonses", "Amazon SES"),
        ]
        for entry in table where joined.contains(entry.needle) {
            return entry.label
        }
        return "Self-hosted / unknown"
    }
}

// MARK: - DoH JSON shape

private struct DOHResponse: Decodable {
    let Answer: [Answer]?
    struct Answer: Decodable {
        let data: String
    }
}
