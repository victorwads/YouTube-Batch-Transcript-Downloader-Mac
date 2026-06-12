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
    private var customUserAgent: String?
    private var videoMuteGuardTask: Task<Void, Never>?

    init(index: Int, slotName: String? = nil) {
        self.slotName = slotName ?? "WebView \(index)"
        self.title = self.slotName
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
        videoMuteGuardTask?.cancel()
        videoMuteGuardTask = nil
        navigationContinuation?.resume(throwing: CancellationError())
        navigationContinuation = nil
        webView?.stopLoading()
        statusText = "Interrompido"
    }

    func resetWebView() {
        videoMuteGuardTask?.cancel()
        videoMuteGuardTask = nil
        navigationContinuation?.resume(throwing: CancellationError())
        navigationContinuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = makeWebView()
        reset()
    }

    func openManualPage(url: URL, title: String) {
        videoMuteGuardTask?.cancel()
        videoMuteGuardTask = nil
        navigationContinuation?.resume(throwing: CancellationError())
        navigationContinuation = nil

        let webView = ensureWebView()
        webView.stopLoading()

        self.title = title
        currentURLString = url.absoluteString
        statusText = "Abrindo login..."
        webView.load(URLRequest(url: url))
    }

    func silencePlayback() async {
        guard webView != nil else { return }

        let script = """
        (() => {
          const applyToMedia = () => {
            const videos = Array.from(document.querySelectorAll('video'));
            for (const video of videos) {
              try {
                video.muted = true;
                video.volume = 0;
                video.pause();
              } catch (_) {}
            }

            const iframes = Array.from(document.querySelectorAll('iframe'));
            for (const frame of iframes) {
              try {
                frame.contentWindow?.postMessage({ event: 'command', func: 'mute', args: [] }, '*');
                frame.contentWindow?.postMessage({ event: 'command', func: 'pauseVideo', args: [] }, '*');
              } catch (_) {}
            }

            return {
              mutedVideos: videos.filter((video) => video.muted).length,
              totalVideos: videos.length,
            };
          };

          const result = applyToMedia();

          if (!window.__codexMediaSilenceObserverInstalled) {
            window.__codexMediaSilenceObserverInstalled = true;
            const observer = new MutationObserver(() => applyToMedia());
            observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true });
            window.setTimeout(() => observer.disconnect(), 15000);
          }

          return JSON.stringify(result);
        })();
        """

        _ = try? await evaluateJavaScript(script)
    }

    func startVideoMuteGuard() {
        guard videoMuteGuardTask == nil else { return }

        videoMuteGuardTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }

                if Task.isCancelled { break }

                await self.silencePlayback()
            }
        }
    }

    func updateUserAgent(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        customUserAgent = trimmed.isEmpty ? nil : trimmed
        webView?.customUserAgent = customUserAgent
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
            const segments = Array.from(document.querySelectorAll([
              'transcript-segment-view-model',
              'ytd-transcript-segment-renderer'
            ].join(',')));
            if (!segments.length) return '';

            const lines = segments.map((segment) => {
              const timestampNode = segment.querySelector([
                'div[class*="Timestamp"]:not([class*="A11yLabel"])',
                '.segment-timestamp'
              ].join(','));
              const textNode = segment.querySelector([
                'span',
                '.segment-text',
                'yt-formatted-string.segment-text'
              ].join(','));
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

          const waitForTranscriptContent = async (timeoutMs, intervalMs = 250) => {
            const startedAt = Date.now();
            let lastStructuredTranscript = '';
            let stableHits = 0;
            let lastOpenAttemptAt = 0;

            const tryOpenTranscriptPanel = () => {
              document.getElementById('info-container')?.click();

              const transcriptButton = findTranscriptButton();
              if (transcriptButton) {
                transcriptButton.click();
                return true;
              }

              return false;
            };

            while (Date.now() - startedAt < timeoutMs) {
              const structuredTranscript = extractStructuredTranscript();
              if (structuredTranscript) {
                if (structuredTranscript === lastStructuredTranscript) {
                  stableHits += 1;
                  if (stableHits >= 2) {
                    return structuredTranscript;
                  }
                } else {
                  lastStructuredTranscript = structuredTranscript;
                  stableHits = 0;
                }
              } else if (Date.now() - lastOpenAttemptAt >= 5000) {
                tryOpenTranscriptPanel();
                lastOpenAttemptAt = Date.now();
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

          const pageReady = await waitFor(() => document.readyState === 'complete' ? 'ready' : '', 120000);
          if (!pageReady) {
            window.__codexTranscriptResult = '__DOCUMENT_READY_TIMEOUT__';
            return;
          }

          const infoContainer = await waitFor(() => document.getElementById('info-container'), 120000);
          if (!infoContainer) {
            window.__codexTranscriptResult = '__INFO_CONTAINER_NOT_FOUND__';
            return;
          }

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

          infoContainer.click();

          const transcriptButton = await waitFor(findTranscriptButton, 120000);
          if (!transcriptButton) {
            window.__codexTranscriptResult = '__TRANSCRIPT_BUTTON_NOT_FOUND__';
            return;
          }

          transcriptButton.click();

          const structuredTranscript = await waitForTranscriptContent(120000);

          if (structuredTranscript) {
            window.__codexTranscriptResult = structuredTranscript;
            return;
          }

          const transcriptText = await waitFor(() => {
            const node = document.getElementsByTagName('yt-item-section-renderer')[0];
            const text = textOf(node);
            return text ? text : '';
          }, 120000);

          if (!transcriptText) {
            window.__codexTranscriptResult = '__TRANSCRIPT_CONTENT_NOT_FOUND__';
            return;
          }

          window.__codexTranscriptResult = transcriptText;
        })();
        """

        try await injectJavaScript(script)
        let result = try await waitForTranscriptResult(timeoutMs: 120_000)
        let transcript = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty {
            throw TranscriptError.transcriptNotFound
        }

        if transcript == "__SITE_BLOCKED__" {
            throw TranscriptError.siteBlocked
        }

        if transcript == "__DOCUMENT_READY_TIMEOUT__" {
            throw TranscriptError.documentReadyTimeout
        }

        if transcript == "__INFO_CONTAINER_NOT_FOUND__" {
            throw TranscriptError.infoContainerNotFound
        }

        if transcript == "__TRANSCRIPT_BUTTON_NOT_FOUND__" {
            throw TranscriptError.transcriptButtonNotFound
        }

        if transcript == "__TRANSCRIPT_CONTENT_NOT_FOUND__" {
            throw TranscriptError.transcriptContentNotFound
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
        videoMuteGuardTask?.cancel()
        videoMuteGuardTask = nil
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
        webView.customUserAgent = customUserAgent
        webView.navigationDelegate = self
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        return webView
    }
}

extension TranscriptWebViewSlot: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
        statusText = "Página carregada"

        Task { @MainActor in
            await self.silencePlayback()
            self.startVideoMuteGuard()
        }
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
