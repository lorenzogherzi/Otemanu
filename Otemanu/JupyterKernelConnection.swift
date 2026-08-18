import Foundation

@MainActor
final class JupyterKernelConnection {
    let kernelID: String

    private let server: JupyterServerInfo
    private let onMessage: @MainActor (JupyterKernelMessage) -> Void
    private let onDisconnect: @MainActor (String) -> Void
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(
        server: JupyterServerInfo,
        kernelID: String,
        onMessage: @escaping @MainActor (JupyterKernelMessage) -> Void,
        onDisconnect: @escaping @MainActor (String) -> Void
    ) {
        self.server = server
        self.kernelID = kernelID
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        session = URLSession(configuration: .ephemeral)
    }

    func start() {
        guard socket == nil, let request = makeRequest() else { return }

        let socket = session.webSocketTask(with: request)
        // Jupyter messages may include binary notebook output. Foundation's
        // default one-mebibyte limit is too small for common images and widget
        // payloads, while this explicit cap keeps transient buffering bounded.
        socket.maximumMessageSize = 64 * 1_024 * 1_024
        self.socket = socket
        socket.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }

            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    if let decoded = self.decode(message) {
                        self.onMessage(decoded)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.onDisconnect(self.kernelID)
            }
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session.invalidateAndCancel()
    }

    private func makeRequest() -> URLRequest? {
        guard
            let baseURL = URL(string: server.url),
            var components = URLComponents(
                url: baseURL.appendingPathComponent("api/kernels/\(kernelID)/channels"),
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"

        var queryItems = [URLQueryItem(name: "session_id", value: UUID().uuidString)]
        if let token = server.token, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        if let token = server.token, !token.isEmpty {
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decode(_ message: URLSessionWebSocketTask.Message) -> JupyterKernelMessage? {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return nil }
            return JupyterKernelMessage(data: data)
        case .data(let data):
            guard let jsonData = legacyJSONPayload(from: data) else { return nil }
            return JupyterKernelMessage(data: jsonData)
        @unknown default:
            return nil
        }
    }

    private func legacyJSONPayload(from data: Data) -> Data? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data)

        func uint32(at offset: Int) -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            let value =
                UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            return Int(value)
        }

        guard let offsetCount = uint32(at: 0), offsetCount > 0 else { return nil }
        let tableEnd = 4 + offsetCount * 4
        guard tableEnd <= bytes.count, let firstOffset = uint32(at: 4) else { return nil }

        let endOffset: Int
        if offsetCount > 1, let secondOffset = uint32(at: 8) {
            endOffset = secondOffset
        } else {
            endOffset = data.count
        }

        guard
            firstOffset >= tableEnd,
            endOffset > firstOffset,
            endOffset <= data.count
        else {
            return nil
        }

        return data.subdata(in: firstOffset..<endOffset)
    }
}
