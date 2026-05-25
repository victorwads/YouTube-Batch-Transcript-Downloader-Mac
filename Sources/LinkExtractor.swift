import Foundation

enum LinkExtractor {
    private static let urlPattern = #"https?://[^\s<>"']+"#

    static func extractEntries(from text: String) -> [TranscriptInputItem] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else {
            return []
        }

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var items: [TranscriptInputItem] = []
        items.reserveCapacity(lines.count)

        for line in lines {
            let lineText = String(line)
            let lineRange = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
            let matches = regex.matches(in: lineText, options: [], range: lineRange)

            guard !matches.isEmpty else { continue }

            for match in matches {
                guard let range = Range(match.range, in: lineText) else { continue }
                var candidate = String(lineText[range])
                candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                while let last = candidate.last, ".,;:)]}".contains(last) {
                    candidate.removeLast()
                }

                guard let url = URL(string: candidate) else {
                    continue
                }

                let prefix = String(lineText[..<range.lowerBound])
                let title = cleanTitle(from: prefix, fallbackIndex: items.count + 1)
                items.append(TranscriptInputItem(title: title, url: url))
            }
        }

        return items
    }

    static func extractLinks(from text: String) -> [URL] {
        extractEntries(from: text).map(\.url)
    }

    private static func cleanTitle(from prefix: String, fallbackIndex: Int) -> String {
        var title = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        if let regex = try? NSRegularExpression(pattern: #"^\s*\d+\s*[\.\)]\s*"#, options: []) {
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            title = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
        }

        while let last = title.last, "-–—:|".contains(last) {
            title.removeLast()
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Link \(fallbackIndex)" : title
    }
}
