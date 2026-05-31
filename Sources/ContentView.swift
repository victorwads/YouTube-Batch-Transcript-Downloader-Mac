import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject var model: TranscriptBatchViewModel

    private let webViewColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                HSplitView {
                    panel(title: "Texto de entrada") {
                        TextEditor(text: $model.linksText)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                    }

                    panel(title: "Links extraídos") {
                        extractedItemsList
                    }

                    panel(title: "Transcrições") {
                        transcriptResultsList
                    }
                }
                .frame(minHeight: 330)

                panel(title: "6 WebViews ao vivo") {
                    webViewGrid
                        .frame(minHeight: 520)
                }
            }
        }
        .frame(minWidth: 1400, minHeight: 900)
        .onAppear {
            model.refreshExtractedLinksPreview()
        }
        .onChange(of: model.linksText) { _, _ in
            model.refreshExtractedLinksPreview()
        }
    }

    private var webViewGrid: some View {
        ScrollView {
            LazyVGrid(columns: webViewColumns, alignment: .leading, spacing: 12) {
                ForEach(Array(model.webViewSlots.enumerated()), id: \.offset) { _, slot in
                    WebViewSlotCard(slot: slot)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var extractedItemsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if model.extractedItems.isEmpty {
                    Text("Nenhum link detectado ainda.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(model.extractedItems.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(item.title)")
                                .font(.headline)
                                .textSelection(.enabled)

                            Text(item.url.absoluteString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var transcriptResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.transcriptResults.isEmpty {
                    Text("Nenhuma transcrição gerada ainda.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(model.transcriptResults.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index + 1). \(item.title)")
                                .font(.headline)
                                .textSelection(.enabled)

                            Text(item.url.absoluteString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Text(transcriptPreview(for: item.transcript))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LinksMae")
                    .font(.title2.weight(.semibold))
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isProcessing {
                ProgressView(value: model.progress)
                    .frame(width: 220)
            }

            Button("Exportar TXT") {
                model.exportTranscriptionToTXT()
            }
            .disabled(model.transcriptResults.isEmpty)

            Button("Limpar resultados") {
                model.clearOutput()
            }
            .disabled(model.isProcessing)

            Button("Limpar cache") {
                model.clearCache()
            }
            .disabled(model.isProcessing)

            Button(model.isProcessing ? "Parar" : "Processar") {
                if model.isProcessing {
                    model.cancelProcessing()
                } else {
                    model.startProcessing()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func panel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 8)

            content()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WebViewSlotCard: View {
    @ObservedObject var slot: TranscriptWebViewSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.slotName)
                        .font(.headline)
                    Text(slot.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(slot.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .textSelection(.enabled)

            Text(slot.currentURLString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            LiveWebView(webView: slot.webView)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LiveWebView: NSViewRepresentable {
    let webView: WKWebView?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.subviews.forEach { subview in
            if subview !== webView {
                subview.removeFromSuperview()
            }
        }

        guard let webView else { return }
        guard webView.superview !== nsView else {
            webView.frame = nsView.bounds
            return
        }

        webView.removeFromSuperview()
        webView.frame = nsView.bounds
        webView.autoresizingMask = [.width, .height]
        nsView.addSubview(webView)
    }
}

private func transcriptPreview(for transcript: String, limit: Int = 2_500) -> String {
    guard transcript.count > limit else { return transcript }
    let endIndex = transcript.index(transcript.startIndex, offsetBy: limit)
    return String(transcript[..<endIndex]) + "\n\n[prévia truncada para manter a interface leve]"
}
