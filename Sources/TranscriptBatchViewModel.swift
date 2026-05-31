import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
final class TranscriptBatchViewModel: NSObject, ObservableObject {
    @Published var linksText = ""
    @Published var extractedItems: [TranscriptInputItem] = []
    @Published var transcriptResults: [TranscriptResultItem] = []
    @Published var statusText = "Pronto."
    @Published var isProcessing = false
    @Published var progress: Double = 0

    let webViewSlots: [TranscriptWebViewSlot]

    private let transcriptCache = TranscriptCacheStore()
    private let slotPool: WebViewSlotPool
    private var processingTask: Task<Void, Never>?

    override init() {
        let slots = (1...6).map { TranscriptWebViewSlot(index: $0) }
        self.webViewSlots = slots
        self.slotPool = WebViewSlotPool(slots: slots)
        super.init()
    }

    func refreshExtractedLinksPreview() {
        extractedItems = LinkExtractor.extractEntries(from: linksText)
    }

    func startProcessing() {
        guard !isProcessing else { return }

        let items = LinkExtractor.extractEntries(from: linksText)
        extractedItems = items
        guard !items.isEmpty else {
            statusText = "Cole pelo menos um link válido."
            return
        }

        isProcessing = true
        progress = 0
        statusText = "Iniciando processamento de \(items.count) links..."

        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.process(items: items)
        }
    }

    func clearOutput() {
        transcriptResults = []
    }

    func exportText() -> String {
        transcriptResults
            .sorted(by: { $0.order < $1.order })
            .map { result in
                makeBlock(
                    title: result.title,
                    link: result.url.absoluteString,
                    transcript: result.transcript
                )
            }
            .joined(separator: "\n\n")
    }

    func exportTranscriptionToTXT() {
        let resultsToExport = transcriptResults
            .sorted(by: { $0.order < $1.order })

        guard !resultsToExport.isEmpty else {
            statusText = "Não há transcrição para exportar."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Exportar"
        panel.message = "Escolha a pasta onde os arquivos de transcrição serão salvos."

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return
        }

        do {
            var usedNames = Set<String>()

            for result in resultsToExport {
                let fileName = makeUniqueFileName(for: result, usedNames: &usedNames)
                let fileURL = directoryURL.appendingPathComponent(fileName)
                let text = makeBlock(
                    title: result.title,
                    link: result.url.absoluteString,
                    transcript: result.transcript
                )

                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            statusText = "\(resultsToExport.count) transcrições exportadas para \(directoryURL.lastPathComponent)."
        } catch {
            statusText = "Falha ao exportar: \(error.localizedDescription)"
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        for slot in webViewSlots {
            slot.stop()
        }
        isProcessing = false
        statusText = "Processamento interrompido."
    }

    private func process(items: [TranscriptInputItem]) async {
        let baseOrder = transcriptResults.count

        defer {
            let wasCancelled = Task.isCancelled
            Task { @MainActor in
                self.finalizeAllWebViews()
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

        await withTaskGroup(of: Void.self) { group in
            var launched = 0

            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }

                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.processItem(item: item, order: baseOrder + index, total: items.count)
                }

                launched += 1
                if launched >= self.webViewSlots.count {
                    _ = await group.next()
                    launched -= 1
                }
            }

            while launched > 0 {
                _ = await group.next()
                launched -= 1
            }
        }
    }

    private func processItem(item: TranscriptInputItem, order: Int, total: Int) async {
        if Task.isCancelled { return }

        await MainActor.run {
            self.statusText = "Aguardando slot para \(item.title)"
        }

        let slot = await slotPool.acquire()
        defer {
            Task {
                await MainActor.run {
                    slot.finishProcessingCycle()
                }
                await self.slotPool.release(slot)
            }
        }

        await MainActor.run {
            slot.prepare(for: item)
            self.statusText = "Processando no \(slot.slotName): \(item.title)"
        }

        if !isSupportedYouTubeURL(item.url) {
            let transcript = "ERRO: Não é o YouTube."
            await MainActor.run {
                slot.markError(transcript)
                self.appendResult(
                    TranscriptResultItem(order: order, title: item.title, url: item.url, transcript: transcript)
                )
                self.progress = Double(order + 1) / Double(baseProgressDenominator(total: total))
                self.statusText = "Ignorado: \(item.title)"
            }
            return
        }

        if let cachedTranscript = transcriptCache.transcript(for: item.url) {
            await MainActor.run {
                slot.prepare(for: item, cached: true)
                slot.markFinished()
                self.appendResult(
                    TranscriptResultItem(order: order, title: item.title, url: item.url, transcript: cachedTranscript)
                )
                self.progress = Double(order + 1) / Double(baseProgressDenominator(total: total))
                self.statusText = "Cache: \(item.title)"
            }
            return
        }

        do {
            await MainActor.run {
                slot.statusText = "Carregando página..."
            }

            try await slot.load(url: item.url)

            await MainActor.run {
                slot.statusText = "Extraindo transcrição..."
            }

            let transcript = try await slot.extractTranscript()
            transcriptCache.save(transcript: transcript, for: item.url)

            await MainActor.run {
                slot.markFinished()
                self.appendResult(
                    TranscriptResultItem(order: order, title: item.title, url: item.url, transcript: transcript)
                )
                self.progress = Double(order + 1) / Double(baseProgressDenominator(total: total))
                self.statusText = "Concluído: \(item.title)"
            }
        } catch {
            let transcript = "ERRO: \(error.localizedDescription)"
            await MainActor.run {
                slot.markError(transcript)
                self.appendResult(
                    TranscriptResultItem(order: order, title: item.title, url: item.url, transcript: transcript)
                )
                self.progress = Double(order + 1) / Double(baseProgressDenominator(total: total))
                self.statusText = "Erro em \(item.title)"
            }
        }
    }

    private func baseProgressDenominator(total: Int) -> Int {
        max(total, 1)
    }

    private func appendResult(_ result: TranscriptResultItem) {
        transcriptResults.append(result)
        transcriptResults.sort(by: { $0.order < $1.order })
    }

    private func finalizeAllWebViews() {
        for slot in webViewSlots {
            slot.finishProcessingCycle()
        }
    }

    private func makeBlock(title: String, link: String, transcript: String) -> String {
        """
        TÍTULO:
        \(title)

        LINK:
        \(link)

        TRANSCRIÇÃO:
        \(transcript)
        """
    }

    private func makeUniqueFileName(for result: TranscriptResultItem, usedNames: inout Set<String>) -> String {
        let orderPrefix = String(format: "%03d", result.order + 1)
        let baseName = sanitizeFileName(result.title).isEmpty ? "transcricao" : sanitizeFileName(result.title)
        var candidate = "\(orderPrefix) - \(baseName).txt"
        var duplicateIndex = 2

        while usedNames.contains(candidate) {
            candidate = "\(orderPrefix) - \(baseName) (\(duplicateIndex)).txt"
            duplicateIndex += 1
        }

        usedNames.insert(candidate)
        return candidate
    }

    private func sanitizeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)

        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(cleaned.prefix(80))
    }

    private func isSupportedYouTubeURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("youtube.com") || host.contains("youtu.be")
    }
}

private actor WebViewSlotPool {
    private var available: [TranscriptWebViewSlot]
    private var waiters: [CheckedContinuation<TranscriptWebViewSlot, Never>] = []

    init(slots: [TranscriptWebViewSlot]) {
        self.available = slots.reversed()
    }

    func acquire() async -> TranscriptWebViewSlot {
        if let slot = available.popLast() {
            return slot
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release(_ slot: TranscriptWebViewSlot) {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: slot)
            return
        }

        available.append(slot)
    }
}
