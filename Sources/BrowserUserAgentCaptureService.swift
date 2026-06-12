import AppKit
import Foundation
import Network

@MainActor
final class BrowserUserAgentCaptureService {
    nonisolated private static let responseHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <title>User-Agent Capture</title>
        <script>
          document.addEventListener("DOMContentLoaded", function () {
            setTimeout(function () {
              window.close();
            }, 250);
          });
        </script>
      </head>
      <body>
        User-Agent captured. You can close this tab.
      </body>
    </html>
    """

    func captureUserAgent() async throws -> String {
        let token = UUID().uuidString.lowercased()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: 0)

        let listener = try NWListener(using: parameters)
        let captureState = CaptureState(listener: listener)
        let userAgent = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            captureState.setContinuation(continuation)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        captureState.finish(.failure(BrowserUserAgentCaptureError.listenerPortUnavailable))
                        return
                    }
                    let url = URL(string: "http://127.0.0.1:\(port.rawValue)/capture/\(token)")!
                    NSWorkspace.shared.open(url)
                case .failed(let error):
                    captureState.finish(.failure(error))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                captureState.addConnection(connection)
                Self.handleConnection(
                    connection,
                    expectedToken: token,
                    onSuccess: { ua in
                        captureState.finish(.success(ua))
                    },
                    onIgnore: {
                        captureState.removeConnection(connection)
                    }
                )
            }

            listener.start(queue: .global(qos: .userInitiated))
            captureState.scheduleTimeout(seconds: 30)
        }

        let trimmed = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw BrowserUserAgentCaptureError.missingUserAgent
        }
        return trimmed
    }

    nonisolated private static func handleConnection(
        _ connection: NWConnection,
        expectedToken: String,
        onSuccess: @escaping (String) -> Void,
        onIgnore: @escaping () -> Void
    ) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(
            connection: connection,
            data: Data(),
            expectedToken: expectedToken,
            onSuccess: onSuccess,
            onIgnore: onIgnore
        )
    }

    nonisolated private static func receiveRequest(
        connection: NWConnection,
        data: Data,
        expectedToken: String,
        onSuccess: @escaping (String) -> Void,
        onIgnore: @escaping () -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, isComplete, error in
            if let error {
                connection.cancel()
                _ = error
                onIgnore()
                return
            }

            var buffer = data
            if let chunk {
                buffer.append(chunk)
            }

            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[..<range.lowerBound]
                guard let headerText = String(data: headerData, encoding: .utf8) else {
                    respond(connection: connection, status: "400 Bad Request", body: "Bad request")
                    onIgnore()
                    return
                }

                let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
                guard let requestLine = lines.first else {
                    respond(connection: connection, status: "400 Bad Request", body: "Bad request")
                    onIgnore()
                    return
                }

                let requestParts = requestLine.split(separator: " ")
                guard requestParts.count >= 2 else {
                    respond(connection: connection, status: "400 Bad Request", body: "Bad request")
                    onIgnore()
                    return
                }

                let path = String(requestParts[1])
                let expectedPath = "/capture/\(expectedToken)"
                guard path == expectedPath else {
                    respond(connection: connection, status: "404 Not Found", body: "Not found")
                    onIgnore()
                    return
                }

                let userAgent = lines
                    .dropFirst()
                    .compactMap { line -> String? in
                        let raw = String(line)
                        guard raw.lowercased().hasPrefix("user-agent:") else { return nil }
                        return raw.dropFirst("user-agent:".count).trimmingCharacters(in: .whitespaces)
                    }
                    .first

                guard let userAgent, !userAgent.isEmpty else {
                    respond(connection: connection, status: "400 Bad Request", body: "Missing User-Agent")
                    onIgnore()
                    return
                }

                // Resume caller immediately after parsing a valid User-Agent.
                onSuccess(userAgent)
                // Best-effort response/close, must not delay caller.
                respond(connection: connection, status: "200 OK", body: Self.responseHTML)
                return
            }

            if isComplete || buffer.count > 32_768 {
                connection.cancel()
                onIgnore()
                return
            }

            receiveRequest(
                connection: connection,
                data: buffer,
                expectedToken: expectedToken,
                onSuccess: onSuccess,
                onIgnore: onIgnore
            )
        }
    }

    nonisolated private static func respond(connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(bodyData.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var output = Data(response.utf8)
        output.append(bodyData)

        connection.send(content: output, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class CaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?
    private var connections: [NWConnection] = []

    init(listener: NWListener) {
        self.listener = listener
    }

    func setContinuation(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func addConnection(_ connection: NWConnection) {
        lock.lock()
        if !finished {
            connections.append(connection)
        } else {
            connection.cancel()
        }
        lock.unlock()
    }

    func removeConnection(_ connection: NWConnection) {
        lock.lock()
        connections.removeAll { $0 === connection }
        lock.unlock()
    }

    func scheduleTimeout(seconds: TimeInterval) {
        timeoutTask = Task { [weak self] in
            let nanos = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            self?.finish(.failure(BrowserUserAgentCaptureError.timeout))
        }
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        let connections = self.connections
        self.connections = []
        lock.unlock()

        switch result {
        case .success(let userAgent):
            continuation?.resume(returning: userAgent)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }

        // Cleanup is best-effort and must not delay continuation result.
        Task.detached {
            timeoutTask?.cancel()
            connections.forEach { $0.cancel() }
            self.listener.cancel()
        }
    }
}

enum BrowserUserAgentCaptureError: LocalizedError {
    case listenerPortUnavailable
    case timeout
    case invalidRequest
    case invalidTokenPath
    case missingUserAgent
    case cancelled

    var errorDescription: String? {
        switch self {
        case .listenerPortUnavailable:
            return "Could not determine local capture server port."
        case .timeout:
            return "Timed out while waiting for browser User-Agent capture."
        case .invalidRequest:
            return "Received an invalid capture request."
        case .invalidTokenPath:
            return "Received a capture request with an invalid token path."
        case .missingUserAgent:
            return "The browser request did not include a User-Agent."
        case .cancelled:
            return "User-Agent capture was cancelled."
        }
    }
}
