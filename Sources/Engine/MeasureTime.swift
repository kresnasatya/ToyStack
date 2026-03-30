import Foundation

public class MeasureTime {
    private let lock = NSLock()
    private var file: FileHandle?

    public init() {
        let path = FileManager.default.currentDirectoryPath + "/browser.trace"
        FileManager.default.createFile(atPath: path, contents: nil)
        file = FileHandle(forUpdatingAtPath: path)
        let ts = Int(Date().timeIntervalSince1970 * 1_000_000)
        writeTrace(
            #"{"traceEvents": [{ "name": "process_name", "ph": "M", "ts": \#(ts), "pid": 1, "cat": "__metadata", "args": {"name": "Browser"}}]}"#
        )
    }

    public func start(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        seekBeforeClose()
        let ts = Int(Date().timeIntervalSince1970 * 1_000_000)
        let tid = UInt(bitPattern: ObjectIdentifier(Thread.current))
        writeTrace(
            ", { \"ph\": \"B\", \"cat\": \"_\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid)}]}"
        )
    }

    public func stop(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        seekBeforeClose()
        let ts = Int(Date().timeIntervalSince1970 * 1_000_000)
        let tid = UInt(bitPattern: ObjectIdentifier(Thread.current))
        writeTrace(
            ", { \"ph\": \"E\", \"cat\": \"_\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid)}]}"
        )
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        try? file?.close()
        file = nil
    }

    private func seekBeforeClose() {
        let end = file?.seekToEndOfFile() ?? 2
        file?.seek(toFileOffset: end - 2)  // overwrite the trailing ]}
    }

    private func writeTrace(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        file?.write(data)
    }
}
