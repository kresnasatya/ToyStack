import Foundation
import Network

/// A one-page HTTP server on 127.0.0.1. It sends no `Cache-Control`
/// header, so the engine keeps its first answer in the response cache.
final class LocalPageServer: @unchecked Sendable {
    enum Reply {
        case page(String)
        case hangUp
    }

    struct Request: Equatable {
        let method: String
        let body: String
    }

    private let listener: NWListener
    private let lock: NSLock = NSLock()
    private var reply: Reply
    private var log: [Request] = []

    var requests: [Request] { lock.withLock({ log }) }

    init(reply: Reply) throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        self.reply = reply
    }

    func setReply(_ newReply: Reply) {
        lock.withLock({ reply = newReply })
    }

    /// Returns the address of the page once the server listens.
    func start() async throws -> String {
        let queue: DispatchQueue = DispatchQueue(label: "local-page-server")
        listener.newConnectionHandler = { [self] (connection: NWConnection) in
            connection.start(queue: queue)
            receive(connection, buffer: Data())
        }
        let port: UInt16 = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<UInt16, any Error>) in
            listener.stateUpdateHandler = { [listener] (state: NWListener.State) in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        })
        return "http://127.0.0.1:\(port)/page"
    }

    func stop() {
        listener.cancel()
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [self] (data: Data?, _, isComplete: Bool, error: NWError?) in
            var received: Data = buffer
            if let data { received.append(data) }
            if let request: Request = Self.parse(received) {
                respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(connection, buffer: received)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let current: Reply = lock.withLock({
            log.append(request)
            return reply
        })
        switch current {
        case .hangUp:
            connection.cancel()
        case .page(let html):
            let body: Data = Data(html.utf8)
            let head: String =
                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8) + body,
                completion: .contentProcessed({ (_: NWError?) in connection.cancel() })
            )
        }
    }

    private static func parse(_ data: Data) -> Request? {
        let separator: Data = Data("\r\n\r\n".utf8)
        guard let end: Range<Data.Index> = data.range(of: separator) else { return nil }
        let head: String = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines: [Substring] = head.split(separator: "\r\n")
        let method: String = lines.first.map({ String($0.prefix(while: { $0 != " " })) }) ?? ""
        let lengthLine: Substring? = lines.first(where: { $0.lowercased().hasPrefix("content-length:") })
        let length: Int = lengthLine.flatMap({ Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }) ?? 0
        let body: Data = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: method, body: String(decoding: body.prefix(length), as: UTF8.self))
    }
}
