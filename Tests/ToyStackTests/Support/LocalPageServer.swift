import Foundation
import Network

/// A one-page HTTP server on 127.0.0.1. It sends no `Cache-Control`
/// header, so the engine keeps its first answer in the response cache.
/// It speaks no TLS: an https attempt is counted and hung up on.
final class LocalPageServer: @unchecked Sendable {
    enum Reply {
        case page(String)
        case redirect(String)
        /// Like a site that lives at one address only: a request naming any
        /// other host is redirected to this one.
        case canonicalHost(String, page: String)
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
    private var tlsAttempts: Int = 0

    var requests: [Request] { lock.withLock({ log }) }
    var secureAttempts: Int { lock.withLock({ tlsAttempts }) }

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
            if received.first == Self.tlsHandshakeRecord {
                lock.withLock({ tlsAttempts += 1 })
                connection.cancel()
            } else if let (request, host): (Request, String) = Self.parse(received) {
                respond(to: request, host: host, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(connection, buffer: received)
            }
        }
    }

    private func respond(to request: Request, host: String, on connection: NWConnection) {
        let current: Reply = lock.withLock({
            log.append(request)
            return reply
        })
        switch current {
        case .hangUp:
            connection.cancel()
        case .page(let html):
            sendPage(html, on: connection)
        case .redirect(let location):
            sendRedirect(to: location, on: connection)
        case .canonicalHost(let canonical, let html):
            if host == canonical {
                sendPage(html, on: connection)
            } else {
                sendRedirect(to: "http://\(canonical)/page", on: connection)
            }
        }
    }

    private func sendPage(_ html: String, on connection: NWConnection) {
        let body: Data = Data(html.utf8)
        let head: String =
            "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        send(Data(head.utf8) + body, on: connection)
    }

    private func sendRedirect(to location: String, on connection: NWConnection) {
        send(Data("HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(
            content: data,
            completion: .contentProcessed({ (_: NWError?) in connection.cancel() })
        )
    }

    // RFC 8446 §5.1: every TLS connection opens with a handshake record, type 22.
    private static let tlsHandshakeRecord: UInt8 = 22

    private static func parse(_ data: Data) -> (Request, host: String)? {
        let separator: Data = Data("\r\n\r\n".utf8)
        guard let end: Range<Data.Index> = data.range(of: separator) else { return nil }
        let head: String = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines: [Substring] = head.split(separator: "\r\n")
        let method: String = lines.first.map({ String($0.prefix(while: { $0 != " " })) }) ?? ""
        let length: Int = headerValue("content-length", in: lines).flatMap({ Int($0) }) ?? 0
        let body: Data = data[end.upperBound...]
        guard body.count >= length else { return nil }
        let request: Request = Request(method: method, body: String(decoding: body.prefix(length), as: UTF8.self))
        return (request, headerValue("host", in: lines) ?? "")
    }

    private static func headerValue(_ name: String, in lines: [Substring]) -> String? {
        let prefix: String = name + ":"
        guard let line: Substring = lines.first(where: { $0.lowercased().hasPrefix(prefix) }) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
