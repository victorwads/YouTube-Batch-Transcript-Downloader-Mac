import SwiftUI

@main
struct LinksMaeApp: App {
    @StateObject private var model = TranscriptBatchViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.titleBar)
    }
}
