import Foundation

struct ProfileMetric {
    var nanos: UInt64 = 0
    var count: Int = 0
}

final class Profiler {
    var enabled: Bool
    private var metrics: [String: ProfileMetric] = [:]

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    func reset() {
        guard enabled else { return }
        metrics.removeAll(keepingCapacity: true)
    }

    func record(_ name: String, nanos: UInt64, count: Int = 1) {
        guard enabled else { return }
        var metric: ProfileMetric = metrics[name] ?? ProfileMetric()
        metric.nanos += nanos
        metric.count += count
        metrics[name] = metric
    }

    @discardableResult
    func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let start: UInt64 = DispatchTime.now().uptimeNanoseconds
        let result: T = body()
        record(name, nanos: DispatchTime.now().uptimeNanoseconds - start)
        return result
    }

    func count(_ name: String, by amount: Int = 1) {
        guard enabled else { return }
        record(name, nanos: 0, count: amount)
    }

    func snapshot() -> [String: ProfileMetric] {
        metrics
    }

    func emitProfile(into measure: MeasureTime?, named event: String) {
        guard enabled else { return }
        var args: [String: Int] = [:]
        for (name, metric) in profiler.snapshot() {
            if metric.nanos > 0 { args["\(name).us"] = Int(metric.nanos / 1_000) }
            if metric.count > 0 { args["\(name).count"] = metric.count }
        }
        measure?.counter(event, args)
    }
}

nonisolated(unsafe) let profiler: Profiler = Profiler(
    enabled: !ProcessInfo.processInfo.arguments.contains("--no-profile")
)
