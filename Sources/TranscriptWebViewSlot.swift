import Foundation
import WebKit

@MainActor
final class TranscriptWebViewSlot: NSObject, ObservableObject {
    let slotName: String
    @Published var title: String
    @Published var currentURLString = ""
    @Published var statusText = "Livre"

    @Published private(set) var webView: WKWebView?

    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(index: Int) {
        self.slotName = "WebView \(index)"
        self.title = slotName
        super.init()
        self.webView = makeWebView()
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
        navigationContinuation?.resume(throwing: CancellationError())
        navigationContinuation = nil
        webView?.stopLoading()
        statusText = "Interrompido"
    }

    func load(url: URL) async throws {
        try Task.checkCancellation()
        let webView = ensureWebView()
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
          const normalizeTimestamp = (raw) => {
            const cleaned = (raw || '').trim();
            if (!cleaned) return '';

            const parts = cleaned
              .split(':')
              .map((part) => part.replace(/\\D/g, ''))
              .filter((part) => part.length > 0);

            if (parts.length < 2 || parts.length > 3) return '';

            const numbers = parts.map((part) => Number.parseInt(part, 10));
            if (numbers.some((value) => Number.isNaN(value))) return '';

            const [hours, minutes, seconds] = parts.length === 3
              ? numbers
              : [0, numbers[0], numbers[1]];

            return [
              String(hours).padStart(3, '0'),
              String(minutes).padStart(2, '0'),
              String(seconds).padStart(2, '0')
            ].join(':');
          };
          const extractStructuredTranscript = () => {
            const segments = Array.from(document.querySelectorAll('transcript-segment-view-model'));
            if (!segments.length) return '';

            const lines = segments.map((segment) => {
              const timestampNode = segment.querySelector('div[class*="Timestamp"]:not([class*="A11yLabel"])');
              const textNode = segment.querySelector('span');
              const timestamp = normalizeTimestamp(textOf(timestampNode));
              const text = textOf(textNode);

              if (!timestamp || !text) return '';
              return `${timestamp} ${text}`;
            }).filter(Boolean);

            return lines.join('\\n').trim();
          };
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

          const structuredTranscript = await waitFor(() => {
            const structured = extractStructuredTranscript();
            if (structured) {
              return structured;
            }
            return '';
          }, 20000);

          if (structuredTranscript) {
            window.__codexTranscriptResult = structuredTranscript;
            return;
          }

          const transcriptText = await waitFor(() => {
            const node = document.getElementsByTagName('yt-item-section-renderer')[0];
            const text = textOf(node);
            return text ? text : '';
          }, 5000);

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
        let webView = ensureWebView()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
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

    func finishProcessingCycle() {
        navigationContinuation?.resume(throwing: CancellationError())
        navigationContinuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.loadHTMLString("", baseURL: nil)
        webView?.removeFromSuperview()
        webView = nil
        reset()
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let newWebView = makeWebView()
        webView = newWebView
        return newWebView
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
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
