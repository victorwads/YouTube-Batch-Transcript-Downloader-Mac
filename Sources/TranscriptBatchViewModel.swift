import Foundation
import WebKit

@MainActor
final class TranscriptBatchViewModel: NSObject, ObservableObject {
    @Published var linksText = ""
    @Published var extractedLinksText = ""
    @Published var outputText = ""
    @Published var statusText = "Pronto."
    @Published var isProcessing = false
    @Published var progress: Double = 0

    let webView: WKWebView

    private var processingTask: Task<Void, Never>?
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    func refreshExtractedLinksPreview() {
        let links = LinkExtractor.extractLinks(from: linksText)
        extractedLinksText = links.map(\.absoluteString).joined(separator: "\n")
    }

    func startProcessing() {
        guard !isProcessing else { return }
        let links = LinkExtractor.extractLinks(from: linksText)
        extractedLinksText = links.map(\.absoluteString).joined(separator: "\n")
        guard !links.isEmpty else {
            statusText = "Cole pelo menos um link válido."
            return
        }

        outputText = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !outputText.isEmpty {
            outputText += "\n\n"
        }

        isProcessing = true
        progress = 0
        statusText = "Iniciando processamento de \(links.count) links..."

        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.process(links: links)
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        webView.stopLoading()
        isProcessing = false
        statusText = "Processamento interrompido."
    }

    private func process(links: [URL]) async {
        let wasCancelled = Task.isCancelled
        defer {
            Task { @MainActor in
                self.isProcessing = false
                self.processingTask = nil
                if wasCancelled {
                    self.statusText = "Processamento interrompido."
                } else {
                    self.statusText = "Concluído."
                    self.progress = 1
                }
            }
        }

        for (index, url) in links.enumerated() {
            if Task.isCancelled { return }

            await MainActor.run {
                self.statusText = "Abrindo \(index + 1)/\(links.count): \(url.absoluteString)"
            }

            do {
                try await load(url: url)
                let transcript = try await extractTranscript()
                let block = makeBlock(for: url.absoluteString, transcript: transcript)

                await MainActor.run {
                    if !self.outputText.isEmpty, !self.outputText.hasSuffix("\n\n") {
                        self.outputText += "\n\n"
                    }
                    self.outputText += block
                    self.outputText += "\n\n"
                    self.progress = Double(index + 1) / Double(links.count)
                }
            } catch {
                let block = makeBlock(for: url.absoluteString, transcript: "ERRO: \(error.localizedDescription)")
                await MainActor.run {
                    self.outputText += block
                    self.outputText += "\n\n"
                    self.progress = Double(index + 1) / Double(links.count)
                }
            }
        }
    }

    private func load(url: URL) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private func extractTranscript() async throws -> String {
        try Task.checkCancellation()

        let script = """
        (async () => {
          const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
          document.getElementById('info-container')?.click();
          document.querySelector('[aria-label="Mostrar transcrição"]')?.click();

          for (let i = 0; i < 24; i += 1) {
            const transcriptNode = document.getElementsByTagName('ytd-transcript-segment-list-renderer')[0];
            const transcript = transcriptNode?.outerText?.trim();
            if (transcript) {
              return transcript;
            }

            await sleep(250);
          }

          return '__TRANSCRIPT_NOT_FOUND__';
        })();
        """

        let result = try await evaluateJavaScript(script)
        let transcript = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty || transcript == "__TRANSCRIPT_NOT_FOUND__" {
            throw TranscriptError.notFound
        }

        return transcript
    }

    private func evaluateJavaScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard self != nil else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result as? String ?? String(describing: result ?? "")
                continuation.resume(returning: value)
            }
        }
    }

    private func makeBlock(for link: String, transcript: String) -> String {
        """
        LINK:
        \(link)

        TRANSCRIÇÃO:
        \(transcript)
        """
    }
}

extension TranscriptBatchViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

private enum TranscriptError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Não foi possível localizar a transcrição nesta página."
        }
    }
}
