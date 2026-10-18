import Foundation

/// FR-ANN-005: announcement text is data. Views render it with `Text(verbatim:)` (no markdown, no
/// automatic links); this finds http(s) links so they can be listed and opened only on a tap.
public enum InertText {
    public static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<URL>()
        var result: [URL] = []
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()),
                  url.host() != nil, seen.insert(url).inserted else { continue }
            result.append(url)
        }
        return result
    }
}
