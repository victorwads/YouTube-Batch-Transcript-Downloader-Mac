import AppKit
import SwiftUI
import WebKit

@MainActor
final class TranscriptWebViewWindowController: NSWindowController {
    init(slot: TranscriptWebViewSlot) {
        let rootView = TranscriptWebViewWindowView(slot: slot)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 854, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = slot.slotName
        window.setContentSize(NSSize(width: 854, height: 480))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct TranscriptWebViewWindowView: View {
    @ObservedObject var slot: TranscriptWebViewSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.slotName)
                        .font(.headline)
                    Text(slot.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(slot.currentURLString.isEmpty ? "Nenhuma URL carregada." : slot.currentURLString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()
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
