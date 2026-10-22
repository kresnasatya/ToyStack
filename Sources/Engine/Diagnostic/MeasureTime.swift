import Foundation

public final class MeasureTime: @unchecked Sendable {
    public enum Category: String {
        case load, style, layout, paint, raster, present, frame, input, engine
    }

    private struct OpenSpan {
        let name: String
        let category: Category
        let frame: Int
        let start: UInt64
    }

    struct SpanInterval {
        let start: UInt64
        let end: UInt64
        let category: Category
        let frame: Int
    }

    private static let streamKey: String = "browser.trace.stream"

    private let lock: NSLock = NSLock()
    private var file: FileHandle?
    private var stacks: [UInt: [OpenSpan]] = [:]
    private var namedThreads: [UInt: String] = [:]
    private var streamIDs: [String: UInt] = [:]
    private var nextStreamID: UInt = 1
    private var currentFrame: Int = 0
    private let epochOffset: UInt64

    public init() {
        let path: String = FileManager.default.currentDirectoryPath + "/browser.trace"
        FileManager.default.createFile(atPath: path, contents: nil)
        file = FileHandle(forUpdatingAtPath: path)
        try? file?.truncate(atOffset: 0)
        file?.seek(toFileOffset: 0)
        epochOffset = UInt64(Date().timeIntervalSince1970 * 1_000_000) - DispatchTime.now().uptimeNanoseconds / 1_000
        let ts: Int = Int(Date().timeIntervalSince1970 * 1_000_000)
        writeTrace(
            #"{"traceEvents": [{ "name": "process_name", "ph": "M", "ts": \#(ts), "pid": 1, "cat": "__metadata", "args": {"name": "Browser"}}]}"#
        )
    }

    public func start(_ name: String, category: Category? = nil, frame: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let tid: UInt = threadID()
        noteThreadLocked(tid: tid, name: nil)
        let resolved: Category = category ?? self.category(for: name)
        let frameID: Int = frame ?? currentFrame
        let ts: UInt64 = now()
        stacks[tid, default: []].append(
            OpenSpan(name: name, category: resolved, frame: frameID, start: ts)
        )
        seekBeforeClose()
        writeTrace(
            ", { \"ph\": \"B\", \"cat\": \"\(resolved.rawValue)\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid), \"args\": {\"frame\": \(frameID)} }]}"
        )
    }

    public func stop(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        let tid: UInt = threadID()
        guard var stack = stacks[tid], let top = stack.popLast() else {
            writeWarningLocked(kind: "unmatchedStop", frame: currentFrame)
            return
        }
        if top.name != name {
            writeWarningLocked(kind: "nameMismatch", frame: top.frame)
        }
        stacks[tid] = stack
        seekBeforeClose()
        let ts: UInt64 = now()
        writeTrace(
            ", { \"ph\": \"E\", \"cat\": \"\(top.category.rawValue)\", \"name\": \"\(top.name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid), \"args\": {\"frame\": \(top.frame)} }]}"
        )
    }

    @discardableResult
    public func span<T>(
        _ name: String,
        category: Category? = nil,
        _ body: () throws -> T
    ) rethrows -> T {
        start(name, category: category)
        defer { stop(name) }
        return try body()
    }

    func interval(
        _ name: String,
        _ span: SpanInterval,
        args: [String: Int] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }
        let tid: UInt = threadID()
        noteThreadLocked(tid: tid, name: nil)
        seekBeforeClose()
        var all: [String: Int] = args
        all["frame"] = span.frame
        let body: String = all
            .map({ "\"\($0.key)\": \($0.value)" })
            .joined(separator: ", ")
        writeTrace(
             ", { \"ph\": \"X\", \"cat\": \"\(span.category.rawValue)\", \"name\": \"\(name)\", \"ts\": \(span.start), \"dur\": \(span.end >= span.start ? span.end - span.start : 0), \"pid\": 1, \"tid\": \(tid), \"args\": {\(body)} }]}"
        )
    }

    private func noteThreadLocked(tid: UInt, name: String?) {
        if let name {
            guard namedThreads[tid] != name else { return }
            namedThreads[tid] = name
            seekBeforeClose()
            writeTrace(
                ", { \"name\": \"thread_name\", \"ph\": \"M\", \"pid\": 1, \"tid\": \(tid), \"cat\": \"__metadata\", \"args\": {\"name\": \"\(name)\"} }]}"
            )
            return
        }
        guard namedThreads[tid] == nil else { return }
        let label: String = Thread.isMainThread ? "main" : "worker"
        namedThreads[tid] = label
        seekBeforeClose()
        writeTrace(
            ", { \"name\": \"thread_name\", \"ph\": \"M\", \"pid\": 1, \"tid\": \(tid), \"cat\": \"__metadata\", \"args\": {\"name\": \"\(label)\"} }]}"
        )
    }

    private func writeWarningLocked(kind: String, frame: Int) {
        seekBeforeClose()
        let ts: UInt64 = now()
        writeTrace(
            ", { \"ph\": \"i\", \"cat\": \"trace\", \"name\": \"trace.warning\", \"s\": \"t\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(threadID()), \"args\": {\"kind\": \"\(kind)\", \"frame\": \(frame)} }]}"
        )
    }

    public func counter(_ name: String, _ args: [String: Int], frame: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        seekBeforeClose()
        let ts: UInt64 = now()
        let tid: UInt = threadID()
        var all: [String: Int] = args
        all["frame"] = frame ?? currentFrame
        let body: String = all.map { "\"\($0.key)\": \($0.value)"}.joined(separator: ", ")
        writeTrace(
            ", { \"ph\": \"C\", \"cat\": \"\(category(for: name).rawValue)\", \"name\": \"\(name)\", \"ts\": \(ts), \"pid\": 1, \"tid\": \(tid), \"args\": {\(body)}}]}"
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

    public func timestamp() -> UInt64 {
        now()
    }

    public func setFrame(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        currentFrame = id
    }

    public func noteThread(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        Thread.current.threadDictionary[Self.streamKey] = nil
        noteThreadLocked(tid: threadID(), name: name)
    }

    public func noteStream(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        let id: UInt
        if let existing: UInt = streamIDs[name] {
            id = existing
        } else {
            id = nextStreamID
            nextStreamID += 1
            streamIDs[name] = id
        }
        Thread.current.threadDictionary[Self.streamKey] = NSNumber(value: id)
        noteThreadLocked(tid: id, name: name)
    }

    private func threadID() -> UInt {
        if let stream: NSNumber = Thread.current.threadDictionary[Self.streamKey] as? NSNumber {
            return stream.uintValue
        }
        return UInt(bitPattern: pthread_self())
    }

    private func now() -> UInt64 {
        epochOffset + DispatchTime.now().uptimeNanoseconds / 1_000
    }

    private func category(for name: String) -> Category {
        if name.hasPrefix("profile.style") || name.hasPrefix("BrowserTab.style") || name.hasPrefix("style.") { return .style }
        if name.hasPrefix("profile.layout") || name.hasPrefix("BrowserTab.layout") || name.hasPrefix("layout.") { return .layout }
        if name.hasPrefix("profile.paint") || name.hasPrefix("BrowserTab.paint") || name.hasPrefix("paint.") { return .paint }
        if name.hasPrefix("raster.") || name == "tiles" || name == "pool" { return .raster }
        if name.hasPrefix("view.") || name == "view" || name == "present.main" || name == "present" { return .present }
        if name.hasPrefix("profile.load") || name.hasPrefix("BrowserTab.load") || name.hasPrefix("load.") { return .load }
        if name == "composite_raster_and_draw" || name.hasPrefix("BrowserTab.anim") || name.hasPrefix("BrowserTab.raf") { return .frame }
        if name.hasPrefix("BrowserTab.scroll") { return .input }
        return .engine
    }
}
