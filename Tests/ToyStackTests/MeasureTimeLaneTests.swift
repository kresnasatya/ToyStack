import Foundation
import Testing

@testable import Engine

/// Queues share pooled OS threads. A lane label must describe only the work
/// that set it, or later work on the same thread lands on the wrong lane.
@Suite
struct MeasureTimeLaneTests {
    @Test func streamLabelEndsWithItsWork() throws {
        let (measure, path): (MeasureTime, String) = Self.makeMeasure()
        defer { try? FileManager.default.removeItem(atPath: path) }

        Self.onOneThread {
            let lane: TraceLane = measure.beginStream("test.stream")
            measure.start("inside")
            measure.stop("inside")
            lane.end()
            measure.start("after")
            measure.stop("after")
        }
        measure.close()

        let trace: TraceLanes = try TraceLanes(path: path)
        #expect(trace.lane(of: "inside") == "test.stream")
        #expect(trace.lane(of: "after") != "test.stream", "work after the stream block stayed on its lane")
    }

    @Test func threadLaneLabelEndsWithItsWork() throws {
        let (measure, path): (MeasureTime, String) = Self.makeMeasure()
        defer { try? FileManager.default.removeItem(atPath: path) }

        Self.onOneThread {
            let lane: TraceLane = measure.beginThreadLane("test.pool")
            measure.start("inside")
            measure.stop("inside")
            lane.end()
            measure.start("after")
            measure.stop("after")
        }
        measure.close()

        let trace: TraceLanes = try TraceLanes(path: path)
        #expect(trace.lane(of: "inside") == "test.pool")
        #expect(trace.lane(of: "after") != "test.pool", "work after the pool block kept the pool's name")
    }

    /// Spans that overlap on two pool threads must stay on two lanes, or their
    /// begin and end events pair up wrongly.
    @Test func eachPoolThreadGetsItsOwnLane() throws {
        let (measure, path): (MeasureTime, String) = Self.makeMeasure()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entered: DispatchGroup = DispatchGroup()
        let release: DispatchSemaphore = DispatchSemaphore(value: 0)
        let done: DispatchGroup = DispatchGroup()
        for name in ["first", "second"] {
            entered.enter()
            done.enter()
            Thread {
                let lane: TraceLane = measure.beginThreadLane("test.pool")
                measure.start(name)
                entered.leave()
                release.wait()
                measure.stop(name)
                lane.end()
                done.leave()
            }.start()
        }
        entered.wait()
        release.signal()
        release.signal()
        done.wait()
        measure.close()

        let trace: TraceLanes = try TraceLanes(path: path)
        #expect(trace.lane(of: "first") == "test.pool")
        #expect(trace.lane(of: "second") == "test.pool")
        #expect(trace.tid(of: "first") != trace.tid(of: "second"))
    }

    // MARK: - Helpers

    private static func makeMeasure() -> (MeasureTime, String) {
        let path: String = NSTemporaryDirectory() + "lanes-\(UUID().uuidString).trace"
        return (MeasureTime(path: path), path)
    }

    /// Runs `body` on one dedicated thread, the way consecutive queue blocks
    /// can run on one pooled thread.
    private static func onOneThread(_ body: @escaping @Sendable () -> Void) {
        let done: DispatchSemaphore = DispatchSemaphore(value: 0)
        Thread {
            body()
            done.signal()
        }.start()
        done.wait()
    }
}

// MARK: - TraceLanes

/// Reads which lane each span was recorded on. The last `thread_name` for a
/// tid wins, as in trace viewers.
private struct TraceLanes {
    private let tidBySpan: [String: Int]
    private let nameByTid: [Int: String]

    init(path: String) throws {
        let data: Data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root: [String: Any] = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let events: [[String: Any]] = try #require(root["traceEvents"] as? [[String: Any]])
        var spans: [String: Int] = [:]
        var names: [Int: String] = [:]
        for event in events {
            guard let tid: Int = event["tid"] as? Int, let name: String = event["name"] as? String else {
                continue
            }
            if name == "thread_name", let args: [String: Any] = event["args"] as? [String: Any] {
                names[tid] = args["name"] as? String
            } else if event["ph"] as? String == "B" {
                spans[name] = tid
            }
        }
        tidBySpan = spans
        nameByTid = names
    }

    func tid(of span: String) -> Int? {
        return tidBySpan[span]
    }

    func lane(of span: String) -> String? {
        return tidBySpan[span].flatMap({ nameByTid[$0] })
    }
}
