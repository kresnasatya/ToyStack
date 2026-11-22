import Testing

@testable import ToyStackHeadless

@Suite
struct StopConditionTests {
    private func session(events: [ScheduledEvent], frameLimit: Int? = nil, runFor: Double? = nil) -> SessionOptions {
        return SessionOptions(runFor: runFor, frameLimit: frameLimit, forceFullLayout: false, events: events)
    }

    private func screenshot(at time: Double) -> ScheduledEvent {
        return ScheduledEvent(time: time, action: .screenshot(path: "/tmp/unused.png"))
    }

    private func renderUnchangedFrames(_ count: Int, into stop: inout StopCondition) {
        for _ in 0..<count {
            stop.frameRendered(signature: "page", isRenderIdle: true)
        }
    }

    @Test func settledPageWithoutEventsStopsAfterThirtyFrames() {
        var stop: StopCondition = StopCondition(session: session(events: []), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount - 1, into: &stop)
        #expect(!stop.canStopEarly(pendingEvents: 0))
        renderUnchangedFrames(1, into: &stop)
        #expect(stop.canStopEarly(pendingEvents: 0))
    }

    @Test func settledPageKeepsRunningWhileAnEventIsPending() {
        var stop: StopCondition = StopCondition(session: session(events: [screenshot(at: 1.0)]), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount * 2, into: &stop)
        #expect(!stop.canStopEarly(pendingEvents: 1))
    }

    @Test func eventRestartsTheSettleWindow() {
        var stop: StopCondition = StopCondition(session: session(events: [screenshot(at: 1.0)]), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount, into: &stop)
        stop.eventApplied()
        renderUnchangedFrames(StopCondition.settledFrameCount - 1, into: &stop)
        #expect(!stop.canStopEarly(pendingEvents: 0))
        renderUnchangedFrames(1, into: &stop)
        #expect(stop.canStopEarly(pendingEvents: 0))
    }

    @Test func busyRendererDoesNotCountAsSettled() {
        var stop: StopCondition = StopCondition(session: session(events: []), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount - 1, into: &stop)
        stop.frameRendered(signature: "page", isRenderIdle: false)
        renderUnchangedFrames(StopCondition.settledFrameCount - 1, into: &stop)
        #expect(!stop.canStopEarly(pendingEvents: 0))
    }

    @Test func changedPageRestartsTheSettleWindow() {
        var stop: StopCondition = StopCondition(session: session(events: []), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount - 1, into: &stop)
        stop.frameRendered(signature: "scrolled", isRenderIdle: true)
        #expect(!stop.canStopEarly(pendingEvents: 0))
    }

    @Test func eventPastTheDefaultLengthExtendsTheRun() {
        let stop: StopCondition = StopCondition(session: session(events: [screenshot(at: 12.0)]), signature: "page")
        #expect(stop.frameLimit == 721)
    }

    @Test func eventInsideTheDefaultLengthKeepsTheDefault() {
        let stop: StopCondition = StopCondition(session: session(events: [screenshot(at: 2.0)]), signature: "page")
        #expect(stop.frameLimit == 600)
    }

    @Test func explicitFrameLimitNeverStopsEarly() {
        var stop: StopCondition = StopCondition(session: session(events: [], frameLimit: 60), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount, into: &stop)
        #expect(stop.frameLimit == 60)
        #expect(!stop.canStopEarly(pendingEvents: 0))
    }

    @Test func explicitRunForNeverStopsEarly() {
        var stop: StopCondition = StopCondition(session: session(events: [], runFor: 2.5), signature: "page")
        renderUnchangedFrames(StopCondition.settledFrameCount, into: &stop)
        #expect(stop.frameLimit == 150)
        #expect(!stop.canStopEarly(pendingEvents: 0))
    }
}
