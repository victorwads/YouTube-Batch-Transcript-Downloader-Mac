import Foundation

struct TranscriptInputItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
}

struct TranscriptResultItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
    let transcript: String
}
