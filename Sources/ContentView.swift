import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject var model: TranscriptBatchViewModel

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
                        TextEditor(text: $model.extractedLinksText)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .disabled(true)
                    }

                    panel(title: "Transcrição concatenada") {
                        TextEditor(text: $model.outputText)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
                }
                .frame(minHeight: 330)

                panel(title: "WebView ao vivo") {
                    LiveWebView(webView: model.webView)
                        .frame(minHeight: 320)
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
        .onAppear {
            model.refreshExtractedLinksPreview()
        }
        .onChange(of: model.linksText) { _, _ in
            model.refreshExtractedLinksPreview()
        }
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

            Button("Limpar saída") {
                model.outputText = ""
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

private struct LiveWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
