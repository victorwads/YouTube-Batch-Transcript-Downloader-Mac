import Foundation

enum TranscriptError: LocalizedError {
    case siteBlocked
    case transcriptButtonNotFound
    case transcriptNotFound

    var errorDescription: String? {
        switch self {
        case .siteBlocked:
            return "Site bloqueado."
        case .transcriptButtonNotFound:
            return "Botão de transcrição não encontrado."
        case .transcriptNotFound:
            return "Não foi possível localizar a transcrição nesta página."
        }
    }
}
