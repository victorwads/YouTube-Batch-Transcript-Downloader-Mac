import Foundation

final class TranscriptCacheStore {
    private let userDefaults: UserDefaults
    private let key = "cachedTranscriptByLink"
    private let structuredLinePattern = #"^\d{3}:\d{2}:\d{2}\s+\S.*$"#

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func transcript(for url: URL) -> String? {
        let key = cacheKey(for: url)
        guard let transcript = allTranscripts[key] else {
            return nil
        }

        if transcript.hasPrefix("ERRO:") || isStructuredTranscript(transcript) {
            return transcript
        }

        removeTranscript(forKey: key)
        return nil
    }

    func save(transcript: String, for url: URL) {
        let key = cacheKey(for: url)
        var transcripts = allTranscripts
        transcripts[key] = transcript
        userDefaults.set(transcripts, forKey: self.key)
    }

    func clearAll() -> Int {
        let count = allTranscripts.count
        userDefaults.removeObject(forKey: key)
        return count
    }

    private var allTranscripts: [String: String] {
        userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func removeTranscript(forKey cacheKey: String) {
        var transcripts = allTranscripts
        transcripts.removeValue(forKey: cacheKey)
        userDefaults.set(transcripts, forKey: key)
    }

    private func isStructuredTranscript(_ transcript: String) -> Bool {
        let lines = transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return false
        }

        return lines.allSatisfy { line in
            line.range(of: structuredLinePattern, options: .regularExpression) != nil
        }
    }

    private func cacheKey(for url: URL) -> String {
        guard let host = url.host?.lowercased() else {
            return url.absoluteString
        }

        if host.contains("youtu.be") {
            let videoID = url.pathComponents.dropFirst().first ?? ""
            return videoID.isEmpty ? url.absoluteString : "youtube:\(videoID)"
        }

        if host.contains("youtube.com") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let videoID = components?.queryItems?.first(where: { $0.name == "v" })?.value, !videoID.isEmpty {
                return "youtube:\(videoID)"
            }
        }

        return url.absoluteString
    }
}
