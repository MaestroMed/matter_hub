import Foundation

/// Identifies the prospect's hosting / CDN provider from response
/// headers. Inferring "where does this run" tells us a lot about the
/// engineering culture (Vercel/Netlify → modern Jamstack, OVH/native →
/// classic French web, AWS → enterprise).
public enum CDNProbe {
    private static let providers: [(needle: String, label: String)] = [
        ("cf-ray",                          "Cloudflare"),
        ("cloudflare",                      "Cloudflare"),
        ("x-vercel-cache",                  "Vercel"),
        ("x-vercel-id",                     "Vercel"),
        ("x-nf-request-id",                 "Netlify"),
        ("netlify",                         "Netlify"),
        ("x-served-by",                     "Fastly"),
        ("fastly",                          "Fastly"),
        ("x-amz-cf-id",                     "AWS CloudFront"),
        ("amazons3",                        "AWS S3"),
        ("via: 1.1 cloudfront",             "AWS CloudFront"),
        ("akamai",                          "Akamai"),
        ("x-bunny",                         "Bunny.net"),
        ("x-frontend",                      "Frontend cluster (custom)"),
        ("nginx",                           "Nginx (origin)"),
        ("apache",                          "Apache (origin)"),
        ("microsoft-iis",                   "Microsoft IIS"),
        ("ovh",                             "OVH"),
        ("o2switch",                        "o2switch"),
    ]

    public static func fetch(for url: URL) async throws -> CDNFindings {
        let headers = try await HTMLProbe.headers(for: url)
        var flat = ""
        for (key, value) in headers {
            if let k = key as? String { flat += k.lowercased() + ": " }
            flat += "\(value)".lowercased() + "\n"
        }

        let provider = providers.first { flat.contains($0.needle) }?.label
        let serverHeader: String? = {
            for (key, value) in headers where (key as? String)?.lowercased() == "server" {
                return "\(value)"
            }
            return nil
        }()

        return CDNFindings(
            provider: provider,
            serverHeader: serverHeader
        )
    }
}
