import Engine
import Foundation

@MainActor
func runScene(_ options: HeadlessOptions) -> Never {
    let browser: Browser = Browser(tracePath: options.output.tracePath)
    browser.forceFullLayout = options.session.forceFullLayout
    browser.resize(to: CGSize(width: options.viewport.width, height: options.viewport.height))
    browser.displayScale = options.viewport.scale
    browser.newTab(options.url)
    browser.setZoom(options.viewport.zoom)
    browser.pauseAnimationTimer()

    guard let tab: BrowserTab = browser.activeTab else {
        print("No active tab after load")
        browser.stopAnimationTimer()
        exit(1)
    }

    guard pump({ tab.isLoaded }, timeout: 30) else {
        print("Load timed out")
        browser.stopAnimationTimer()
        exit(1)
    }
    pumpRenderIdle(browser)

    let scheduled: [ScheduledEvent] = options.session.events.sorted(by: { (lhs: ScheduledEvent, rhs: ScheduledEvent) -> Bool in lhs.time < rhs.time })
    let limit: Int = options.session.frameLimit ?? animationFrameCount(for: options.session.runFor ?? 10)
    let watchStability: Bool = options.session.frameLimit == nil && options.session.runFor == nil
    var eventIndex: Int = 0
    var tick: Int = 0
    var stableTicks: Int = 0
    var lastSignature: String = displaySignature(browser.drawList)

    while tick < limit {
        while eventIndex < scheduled.count,
            animationFrameCount(for: scheduled[eventIndex].time) <= tick
        {
            apply(
                scheduled[eventIndex].action,
                browser: browser,
                tab: tab,
                viewport: options.viewport
            )
            eventIndex += 1
        }

        browser.advanceFrame()
        pumpRenderIdle(browser)
        tick += 1

        if watchStability {
            let current: String = displaySignature(browser.drawList)
            if current == lastSignature, browser.isRenderIdle {
                stableTicks += 1
            } else {
                stableTicks = 0
                lastSignature = current
            }
            if stableTicks >= 30 { break }
        }
    }

    if let path: String = options.output.screenshotPath {
        guard capture(browser, viewport: options.viewport, to: path) else {
            print("Failed to write PNG to \(path)")
            browser.stopAnimationTimer()
            exit(1)
        }
        print("Saved: \(path)")
    }

    browser.stopAnimationTimer()
    exit(0)
}

@MainActor
private func apply(
    _ action: ScheduledEvent.Action,
    browser: Browser,
    tab: BrowserTab,
    viewport: ViewportOptions
) {
    switch action {
    case let .scroll(x, y, deltaY):
        tab.scrollAt(x: x, y: y, deltaY: deltaY)
        pumpRenderIdle(browser)
    case let .screenshot(path):
        if capture(browser, viewport: viewport, to: path) {
            print("Saved: \(path)")
        } else {
            print("Failed to write PNG to \(path)")
        }
    }
}

@MainActor
private func pumpRenderIdle(_ browser: Browser) {
    _ = pump({ browser.isRenderIdle }, timeout: 10)
}

@MainActor
private func pump(_ condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline: Date = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
    }
    return true
}

