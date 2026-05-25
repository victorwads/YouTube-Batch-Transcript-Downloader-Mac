import Foundation

enum LinkExtractor {
    private static let urlPattern = #"https?://[^\s<>"']+"#

    static func extractLinks(from text: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var seen = Set<String>()
        var urls: [URL] = []
        urls.reserveCapacity(matches.count)

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            var candidate = String(text[range])
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            while let last = candidate.last, ".,;:)]}".contains(last) {
                candidate.removeLast()
            }

            guard !candidate.isEmpty, seen.insert(candidate).inserted, let url = URL(string: candidate) else {
                continue
            }

            urls.append(url)
        }

        return urls
    }
}
