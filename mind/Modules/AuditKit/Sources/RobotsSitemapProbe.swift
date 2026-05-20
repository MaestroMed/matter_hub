import Foundation

/// Checks the crawlability of the site through /robots.txt and
/// /sitemap.xml. Both files are the bedrock of how Google indexes the
/// prospect — missing or hostile values = invisible SEO.
public enum RobotsSitemapProbe {
    public static func fetch(for url: URL) async throws -> CrawlabilityFindings {
        guard let host = url.host(percentEncoded: false) else {
            return CrawlabilityFindings(
                hasRobotsTxt: false,
                allowsAllCrawlers: false,
                hasSitemap: false
            )
        }

        let scheme = url.scheme ?? "https"
        let base = "\(scheme)://\(host)"

        async let robotsResult = analyseRobots(at: URL(string: "\(base)/robots.txt"))
        async let sitemapResult = analyseSitemap(at: URL(string: "\(base)/sitemap.xml"))

        let (hasRobots, allowsAll) = await robotsResult
        let (hasSitemap, urlCount) = await sitemapResult

        return CrawlabilityFindings(
            hasRobotsTxt: hasRobots,
            allowsAllCrawlers: allowsAll,
            hasSitemap: hasSitemap,
            sitemapURLCount: urlCount
        )
    }

    // MARK: - robots.txt

    private static func analyseRobots(at url: URL?) async -> (Bool, Bool) {
        guard let url else { return (false, false) }
        do {
            let body = try await HTMLProbe.fetch(url).lowercased()
            // Look for an explicit Disallow under User-agent: *.
            let lines = body.split(separator: "\n").map { String($0) }
            var inStarBlock = false
            var sawAllow = false
            var sawBroadDisallow = false
            for raw in lines {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("user-agent:") {
                    inStarBlock = line.contains("*")
                    continue
                }
                if inStarBlock {
                    if line.hasPrefix("disallow:") {
                        let value = line.dropFirst("disallow:".count).trimmingCharacters(in: .whitespaces)
                        if value == "/" { sawBroadDisallow = true }
                    } else if line.hasPrefix("allow:") {
                        sawAllow = true
                    }
                }
            }
            let allowsAll = !sawBroadDisallow || sawAllow
            return (true, allowsAll)
        } catch {
            return (false, false)
        }
    }

    // MARK: - sitemap.xml

    private static func analyseSitemap(at url: URL?) async -> (Bool, Int?) {
        guard let url else { return (false, nil) }
        do {
            let body = try await HTMLProbe.fetch(url)
            // Count <url> tags as a proxy for "number of pages declared".
            // We don't fully parse XML for this — perf-wise wasteful for
            // big sitemaps. The count is informational only.
            let lower = body.lowercased()
            guard lower.contains("<urlset") || lower.contains("<sitemapindex") else {
                return (false, nil)
            }
            let count = lower.components(separatedBy: "<url>").count - 1
            let normalised = max(0, count)
            return (true, normalised)
        } catch {
            return (false, nil)
        }
    }
}
