import Foundation

enum TranscriptError: LocalizedError {
    case documentReadyTimeout
    case infoContainerNotFound
    case siteBlocked
    case transcriptButtonNotFound
    case transcriptNotFound
    case transcriptContentNotFound

    var errorDescription: String? {
        switch self {
        case .documentReadyTimeout:
            return "A pagina nao ficou pronta dentro do tempo esperado. Falhou ao aguardar document.readyState === 'complete'."
        case .infoContainerNotFound:
            return "Nao foi possivel localizar o elemento #info-container na pagina do YouTube."
        case .siteBlocked:
            return "O YouTube indicou que o video esta bloqueado, restrito ou indisponivel."
        case .transcriptButtonNotFound:
            return "Nao foi possivel localizar o botao de transcricao. Foram verificados botoes e itens de menu com texto/aria-label contendo 'transcript', 'show transcript' ou equivalentes."
        case .transcriptNotFound:
            return "Nao foi possivel localizar a transcricao nesta pagina."
        case .transcriptContentNotFound:
            return "O painel de transcricao abriu, mas nao foi possivel encontrar o conteudo nos seletores esperados: transcript-segment-view-model ou yt-item-section-renderer."
        }
    }
}
