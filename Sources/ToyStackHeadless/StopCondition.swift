// MARK: - StopCondition
struct StopCondition {
    static let settledFrameCount: Int = 30
    static let defaultSeconds: Double = 10

    let frameLimit: Int
    let stopsWhenSettled: Bool
    private var lastSignature: String
    private var settledFrames: Int

    init(session: SessionOptions, signature: String) {
        if let frameLimit: Int = session.frameLimit {
            self.frameLimit = frameLimit
            stopsWhenSettled = false
        } else if let runFor: Double = session.runFor {
            frameLimit = animationFrameCount(for: runFor)
            stopsWhenSettled = false
        } else {
            let defaultLimit: Int = animationFrameCount(for: StopCondition.defaultSeconds)
            let lastEventFrame: Int? = session.events.map { (event: ScheduledEvent) -> Int in animationFrameCount(for: event.time) }.max()
            // An event fires at the start of its frame, so the run needs one frame past it.
            frameLimit = max(defaultLimit, (lastEventFrame ?? -1) + 1)
            stopsWhenSettled = true
        }
        lastSignature = signature
        settledFrames = 0
    }

    mutating func eventApplied() {
        settledFrames = 0
    }

    mutating func frameRendered(signature: String, isRenderIdle: Bool) {
        if signature == lastSignature, isRenderIdle {
            settledFrames += 1
        } else {
            settledFrames = 0
            lastSignature = signature
        }
    }

    func canStopEarly(pendingEvents: Int) -> Bool {
        return stopsWhenSettled && pendingEvents == 0 && settledFrames >= StopCondition.settledFrameCount
    }
}
