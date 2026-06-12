import AppKit
import SwiftUI
import WebKit

@MainActor
final class LoginWebViewWindowController: NSWindowController {
    private let onWindowClosed: () -> Void

    init(slot: TranscriptWebViewSlot, onWindowClosed: @escaping () -> Void, closeAction: @escaping () -> Void) {
        self.onWindowClosed = onWindowClosed
        let rootView = LoginWebViewWindowView(slot: slot, closeAction: closeAction)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 854, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Login da WebView"
        window.setContentSize(NSSize(width: 854, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = nil

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension LoginWebViewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }
}

private struct LoginWebViewWindowView: View {
    @ObservedObject var slot: TranscriptWebViewSlot
    let closeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Janela de login")
                        .font(.headline)
                    Text(slot.currentURLString.isEmpty ? "Pronta para abrir uma página de login." : slot.currentURLString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Cancelar login") {
                    closeAction()
                }
                .buttonStyle(.borderedProminent)
            }

            WindowWebView(webView: slot.webView)
                .frame(minHeight: 360)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(minWidth: 854, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WindowWebView: NSViewRepresentable {
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
