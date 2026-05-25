import Foundation

final class TranscriptCacheStore {
    private let userDefaults: UserDefaults
    private let key = "cachedTranscriptByLink"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func transcript(for url: URL) -> String? {
        allTranscripts[cacheKey(for: url)]
    }

    func save(transcript: String, for url: URL) {
        let key = cacheKey(for: url)
        var transcripts = allTranscripts
        transcripts[key] = transcript
        userDefaults.set(transcripts, forKey: self.key)
    }

    private var allTranscripts: [String: String] {
        userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
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
