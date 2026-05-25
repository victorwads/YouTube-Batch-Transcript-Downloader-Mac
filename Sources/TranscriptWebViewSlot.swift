import Foundation
import WebKit

@MainActor
final class TranscriptWebViewSlot: NSObject, ObservableObject {
    let slotName: String
    @Published var title: String
    @Published var currentURLString = ""
    @Published var statusText = "Livre"

    let webView: WKWebView

    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(index: Int) {
        self.slotName = "WebView \(index)"
        self.title = slotName

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    func prepare(for item: TranscriptInputItem, cached: Bool = false) {
        title = item.title
        currentURLString = item.url.absoluteString
        statusText = cached ? "Cache" : "Carregando..."
    }

    func reset() {
        title = slotName
        currentURLString = ""
        statusText = "Livre"
    }

    func markFinished() {
        statusText = "Concluído"
    }

    func markError(_ message: String) {
        statusText = message
    }

    func stop() {
        webView.stopLoading()
        statusText = "Interrompido"
    }

    func load(url: URL) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    func extractTranscript() async throws -> String {
        try Task.checkCancellation()

        let script = """
        void (async () => {
          window.__codexTranscriptResult = '__PENDING__';
          const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
          const normalize = (value) => (value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
          const textOf = (node) => (node && typeof node.innerText === 'string') ? node.innerText.trim() : '';
          const transcriptLabels = [
            'show transcript',
            'open transcript',
            'transcript',
            'mostrar transcrição',
            'mostrar transcricao',
            'exibir transcrição',
            'exibir transcricao',
            'abrir transcrição',
            'abrir transcricao'
          ];

          const waitFor = async (predicate, timeoutMs, intervalMs = 250) => {
            const startedAt = Date.now();
            while (Date.now() - startedAt < timeoutMs) {
              const value = predicate();
              if (value) {
                return value;
              }
              await sleep(intervalMs);
            }
            return null;
          };

          const findTranscriptButton = () => {
            const buttons = Array.from(document.querySelectorAll([
              'button',
              'tp-yt-paper-button',
              'ytd-button-renderer button',
              'ytd-menu-service-item-renderer button',
              'ytd-menu-navigation-item-renderer button'
            ].join(',')));

            return buttons.find((button) => {
              const signature = [
                button.textContent,
                button.getAttribute('aria-label'),
                button.title
              ].map(normalize).join(' ');

              return transcriptLabels.some((label) => signature.includes(label));
            }) || null;
          };

          await waitFor(() => document.readyState === 'complete' ? 'ready' : '', 15000);
          await waitFor(() => document.getElementById('info-container') ? 'info' : '', 15000);

          const blockedKeywords = [
            'video unavailable',
            'this video is unavailable',
            'restricted',
            'blocked',
            'conteúdo indisponível',
            'conteudo indisponivel',
            'vídeo indisponível',
            'video indisponivel'
          ];

          const pageText = normalize(document.body?.innerText || '');
          if (blockedKeywords.some((keyword) => pageText.includes(keyword))) {
            window.__codexTranscriptResult = '__SITE_BLOCKED__';
            return;
          }

          document.getElementById('info-container')?.click();
          await sleep(1200);

          const transcriptButton = await waitFor(findTranscriptButton, 15000);
          if (!transcriptButton) {
            window.__codexTranscriptResult = '__TRANSCRIPT_BUTTON_NOT_FOUND__';
            return;
          }

          transcriptButton.click();
          await sleep(1500);

          const transcriptText = await waitFor(() => {
            const node = document.getElementsByTagName('yt-item-section-renderer')[0];
            const text = textOf(node);
            return text ? text : '';
          }, 20000);

          if (!transcriptText) {
            window.__codexTranscriptResult = '__TRANSCRIPT_NOT_FOUND__';
            return;
          }

          window.__codexTranscriptResult = transcriptText;
        })();
        """

        try await injectJavaScript(script)
        let result = try await waitForTranscriptResult(timeoutMs: 25_000)
        let transcript = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty {
            throw TranscriptError.transcriptNotFound
        }

        if transcript == "__SITE_BLOCKED__" {
            throw TranscriptError.siteBlocked
        }

        if transcript == "__TRANSCRIPT_BUTTON_NOT_FOUND__" {
            throw TranscriptError.transcriptButtonNotFound
        }

        if transcript == "__TRANSCRIPT_NOT_FOUND__" {
            throw TranscriptError.transcriptNotFound
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

    private func injectJavaScript(_ script: String) async throws {
        _ = try await evaluateJavaScript(script)
    }

    private func waitForTranscriptResult(timeoutMs: Int) async throws -> String {
        let startedAt = Date()

        while Date().timeIntervalSince(startedAt) * 1000 < Double(timeoutMs) {
            try Task.checkCancellation()

            let result = try await evaluateJavaScript("window.__codexTranscriptResult || ''")
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != "__PENDING__" {
                return trimmed
            }

            try await Task.sleep(nanoseconds: 300_000_000)
        }

        throw TranscriptError.transcriptNotFound
    }
}

extension TranscriptWebViewSlot: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
        statusText = "Página carregada"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
        statusText = "Erro: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
        statusText = "Erro: \(error.localizedDescription)"
    }
}
