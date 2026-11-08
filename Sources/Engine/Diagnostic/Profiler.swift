import Foundation

struct ProfileMetric {
    var nanos: UInt64 = 0
    var count: Int = 0
}

/// Accumulates recursive work (per node, per rule, per word) into windows.
///
/// Each thread records into its own window, so recording takes no lock. The
/// main thread's window works as the single window always did: `reset()`
/// opens it and `emitProfile` writes it as one `profile.<phase>` counter. A
/// background layout job opens and emits its own window on its thread.
///
/// Names are string literals, keyed by their address, so recording does not
/// hash a string. A name built at runtime goes through `count(named:)`.
final class Profiler: @unchecked Sendable {
    let enabled: Bool
    private let windowKey: pthread_key_t

    init(enabled: Bool = true) {
        self.enabled = enabled
        var key: pthread_key_t = 0
        let status: Int32 = pthread_key_create(&key, { raw in
            let window: UnsafeMutablePointer<ProfileWindow> = raw.assumingMemoryBound(
                to: ProfileWindow.self
            )
            window.deinitialize(count: 1)
            window.deallocate()
        })
        precondition(status == 0, "pthread_key_create failed: \(status)")
        self.windowKey = key
    }

    deinit {
        pthread_key_delete(windowKey)
    }

    /// Clears this thread's window.
    func reset() {
        guard enabled else { return }
        window.pointee.reset()
    }

    func record(_ name: StaticString, nanos: UInt64, count: Int = 1) {
        guard enabled else { return }
        window.pointee.add(name, nanos: nanos, count: count)
    }

    @discardableResult
    func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let start: UInt64 = DispatchTime.now().uptimeNanoseconds
        let result: T = body()
        record(name, nanos: DispatchTime.now().uptimeNanoseconds - start)
        return result
    }

    func count(_ name: StaticString, by amount: Int = 1) {
        guard enabled else { return }
        window.pointee.add(name, nanos: 0, count: amount)
    }

    /// For a name built at runtime. Slower than a literal: the name is hashed.
    func count(named name: String, by amount: Int = 1) {
        guard enabled else { return }
        window.pointee.add(named: name, nanos: 0, count: amount)
    }

    /// This thread's window.
    func snapshot() -> [String: ProfileMetric] {
        return window.pointee.snapshot()
    }

    /// Writes this thread's window as one counter event. `frame` defaults to
    /// the frame current when the event is written.
    func emitProfile(into measure: MeasureTime?, named event: String, frame: Int? = nil) {
        guard enabled else { return }
        var args: [String: Int] = [:]
        for (name, metric) in snapshot() {
            if metric.nanos > 0 { args["\(name).us"] = Int(metric.nanos / 1_000) }
            if metric.count > 0 { args["\(name).count"] = metric.count }
        }
        measure?.counter(event, args, frame: frame)
    }

    /// This thread's window. Held through a raw pointer: only the owning
    /// thread touches it, so no retain, release, or exclusivity check per call.
    private var window: UnsafeMutablePointer<ProfileWindow> {
        if let raw: UnsafeMutableRawPointer = pthread_getspecific(windowKey) {
            return raw.assumingMemoryBound(to: ProfileWindow.self)
        }
        let created: UnsafeMutablePointer<ProfileWindow> = .allocate(capacity: 1)
        created.initialize(to: ProfileWindow())
        pthread_setspecific(windowKey, created)
        return created
    }
}

let profiler: Profiler = Profiler(
    enabled: !ProcessInfo.processInfo.arguments.contains("--no-profile")
)

// MARK: - ProfileWindow

/// One thread's metrics. Literal names map to a slot in `metrics`, so adding
/// to a known name is one pointer lookup and an in-place update.
private struct ProfileWindow {
    private var slots: [UnsafeRawPointer: Int] = [:]
    private var names: [StaticString] = []
    private var metrics: [ProfileMetric] = []
    private var byName: [String: ProfileMetric] = [:]

    mutating func reset() {
        slots.removeAll(keepingCapacity: true)
        names.removeAll(keepingCapacity: true)
        metrics.removeAll(keepingCapacity: true)
        byName.removeAll(keepingCapacity: true)
    }

    mutating func add(_ name: StaticString, nanos: UInt64, count: Int) {
        guard name.hasPointerRepresentation else {
            add(named: name.description, nanos: nanos, count: count)
            return
        }
        let address: UnsafeRawPointer = UnsafeRawPointer(name.utf8Start)
        if let slot: Int = slots[address] {
            metrics[slot].nanos += nanos
            metrics[slot].count += count
            return
        }
        slots[address] = metrics.count
        names.append(name)
        metrics.append(ProfileMetric(nanos: nanos, count: count))
    }

    mutating func add(named name: String, nanos: UInt64, count: Int) {
        var metric: ProfileMetric = byName[name] ?? ProfileMetric()
        metric.nanos += nanos
        metric.count += count
        byName[name] = metric
    }

    /// Merges by name: the same literal can sit at two addresses.
    func snapshot() -> [String: ProfileMetric] {
        var merged: [String: ProfileMetric] = byName
        for (slot, name) in names.enumerated() {
            var metric: ProfileMetric = merged[name.description] ?? ProfileMetric()
            metric.nanos += metrics[slot].nanos
            metric.count += metrics[slot].count
            merged[name.description] = metric
        }
        return merged
    }
}
