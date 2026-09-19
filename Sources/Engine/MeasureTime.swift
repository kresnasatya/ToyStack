import Foundation

public class MeasureTime: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var file: FileHandle?

    public init() {
        let path: String = FileManager.default.currentDirectoryPath + "/browser.trace"
        FileManager.default.createFile(atPath: path, contents: nil)
        file = FileHandle(forUpdatingAtPath: path)
        let ts: Int = Int(Date().timeIntervalSince1970 * 1_000_000)
        writeTrace(
            #"{"traceEvents": [{ "name": "process_name", "ph": "M", "ts": \#(ts), "pid": 1, "cat": "__metadata", "args": {"name": "Browser"}}]}"#
        )
    }

    public func start(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        seekBeforeClose()
        let ts: Int = Int(Date().timeIntervalSince1970 * 1_000_000)
        let tid: UInt = UInt(bitPattern: ObjectIdentifier(Thread.current))
        writeTrace(
            ", { \"ph\": \"B\", \"cat\": \"_\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid)}]}"
        )
    }

    public func stop(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        seekBeforeClose()
        let ts: Int = Int(Date().timeIntervalSince1970 * 1_000_000)
        let tid: UInt = UInt(bitPattern: ObjectIdentifier(Thread.current))
        writeTrace(
            ", { \"ph\": \"E\", \"cat\": \"_\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid)}]}"
        )
    }

    public func counter(_ name: String, _ args: [String: Int]) {
        lock.lock()
        defer { lock.unlock() }
        seekBeforeClose()
        let ts: Int = Int(Date().timeIntervalSince1970 * 1_000_000)
        let tid: UInt = UInt(bitPattern: ObjectIdentifier(Thread.current))
        let body: String = args.map { "\"\($0.key)\": \($0.value)"}.joined(separator: ", ")
        writeTrace(
            ", { \"ph\": \"C\", \"cat\": \"_\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid), \"args\": {\(body)}}]}"
        )
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        try? file?.close()
        file = nil
    }

    private func seekBeforeClose() {
        let end: UInt64 = file?.seekToEndOfFile() ?? 2
        file?.seek(toFileOffset: end - 2)
    }

    private func writeTrace(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        file?.write(data)
    }
}
