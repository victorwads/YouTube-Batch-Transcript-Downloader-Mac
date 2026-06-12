import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject var model: TranscriptBatchViewModel
    @State private var expandedResultIDs = Set<TranscriptResultItem.ID>()

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

                panel(title: "WebViews") {
                    webViewControlGrid
                        .frame(minHeight: 150, maxHeight: 190)
                }
            }
        }
        .frame(minWidth: 1400, minHeight: 900)
        .onAppear {
            model.refreshExtractedLinksPreview()
            model.showAllWebViewWindows()
        }
        .onChange(of: model.linksText) { _, _ in
            model.refreshExtractedLinksPreview()
        }
    }

    private var webViewControlGrid: some View {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10)
                ], alignment: .leading, spacing: 10) {
                    ForEach(Array(model.webViewSlots.enumerated()), id: \.offset) { index, slot in
                        WebViewSlotCard(slot: slot) {
                            model.webViewWindowControllers[index].showWindow(nil)
                            model.webViewWindowControllers[index].window?.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                .padding(10)
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
                    transcriptSummaryCard

                    ForEach(Array(sortedTranscriptResults.enumerated()), id: \.element.id) { index, item in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedResultIDs.contains(item.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedResultIDs.insert(item.id)
                                    } else {
                                        expandedResultIDs.remove(item.id)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.url.absoluteString)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Text(transcriptPreview(for: item.transcript))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(isErrorResult(item) ? Color.red : Color.green)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(index + 1). \(item.title)")
                                        .font(.headline)
                                        .textSelection(.enabled)

                                    Text(isErrorResult(item) ? "Erro" : "Sucesso")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isErrorResult(item) ? .red : .green)
                                }

                                Spacer()
                            }
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("User-Agent da WebView")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        TextField(
                            "Padrão do sistema",
                            text: Binding(
                                get: { model.webViewUserAgent },
                                set: { model.updateWebViewUserAgent($0) }
                            )
                        )
                        .font(.system(.footnote, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)

                        Button("Capturar User-Agent") {
                            Task { @MainActor in
                                await model.captureWebViewUserAgentFromDefaultBrowser()
                            }
                        }
                        .disabled(model.isProcessing || model.isCapturingWebViewUserAgent)
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tela de login")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            TextField("URL para abrir o login", text: $model.loginURLText)
                                .textFieldStyle(.roundedBorder)

                            Button("Abrir login") {
                                model.openLoginPage()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Cancelar login") {
                                model.cancelLogin()
                            }
                            .buttonStyle(.bordered)

                            Button("Mostrar janelas ativas") {
                                model.showAllWebViewWindows()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Concorrência")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Stepper(
                                "WebViews simultâneas: \(model.activeWebViewCount)",
                                value: Binding(
                                    get: { model.activeWebViewCount },
                                    set: { model.setActiveWebViewCount($0) }
                                ),
                                in: 1...model.webViewSlots.count
                            )
                            .disabled(model.isProcessing)

                            Text("Isso define quantas janelas ficam ativas ao mesmo tempo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 8)
                .frame(maxWidth: 760, alignment: .leading)
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

            Button("Limpar WebView") {
                Task { @MainActor in
                    await model.clearWebViewStorageAndResetSlots()
                }
            }
            .disabled(model.isProcessing || model.isClearingWebViewStorage)

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

    private var sortedTranscriptResults: [TranscriptResultItem] {
        model.transcriptResults.sorted { lhs, rhs in
            if isErrorResult(lhs) != isErrorResult(rhs) {
                return isErrorResult(lhs) && !isErrorResult(rhs)
            }
            return lhs.order < rhs.order
        }
    }

    private var transcriptSummaryCard: some View {
        let successCount = model.transcriptResults.filter { !isErrorResult($0) }.count
        let errorCount = model.transcriptResults.filter(isErrorResult).count

        return HStack(spacing: 12) {
            summaryBadge(title: "Total", value: "\(model.transcriptResults.count)", color: .secondary)
            summaryBadge(title: "Sucessos", value: "\(successCount)", color: .green)
            summaryBadge(title: "Erros", value: "\(errorCount)", color: .red)

            Spacer()

            if errorCount > 0 {
                Text("Erros aparecem primeiro na lista.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func summaryBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func isErrorResult(_ item: TranscriptResultItem) -> Bool {
        item.transcript.hasPrefix("ERRO:")
    }
}

private struct WebViewSlotCard: View {
    @ObservedObject var slot: TranscriptWebViewSlot
    let focusWindowAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.slotName)
                        .font(.subheadline.weight(.semibold))
                    Text(slot.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Focar janela") {
                    focusWindowAction()
                }
                .buttonStyle(.bordered)
            }

            Text(slot.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .textSelection(.enabled)

            Text(slot.currentURLString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)

            Text("A WebView fica aberta em uma janela separada.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func transcriptPreview(for transcript: String, limit: Int = 2_500) -> String {
    guard transcript.count > limit else { return transcript }
    let endIndex = transcript.index(transcript.startIndex, offsetBy: limit)
    return String(transcript[..<endIndex]) + "\n\n[prévia truncada para manter a interface leve]"
}
