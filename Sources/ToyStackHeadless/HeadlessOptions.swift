import CoreGraphics
import Engine
import Foundation

// MARK: - HeadlessOptions
struct HeadlessOptions {
    let url: WebURL
    let viewport: ViewportOptions
    let output: OutputOptions
    let session: SessionOptions
}

// MARK: ViewportOptions
struct ViewportOptions {
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let zoom: CGFloat
}

// MARK: - OutputOptions
struct OutputOptions {
    let tracePath: String?
    let screenshotPath: String?
}

// MARK: - SessionOptions
struct SessionOptions {
    let runFor: Double?
    let frameLimit: Int?
    let forceFullLayout: Bool
    let events: [ScheduledEvent]
}

// MARK: - ScheduledEvent
struct ScheduledEvent {
    enum Action {
        case scroll(x: CGFloat, y: CGFloat, deltaY: CGFloat)
        case resize(width: CGFloat, height: CGFloat)
        case screenshot(path: String)
    }

    let time: Double
    let action: Action
}

// MARK: Argument parsing
func usage() -> Never {
    print("""
        Usage: swift run ToyStackHeadless <url> [options]

        --trace <path>                 write the trace here (default ./browser.trace)
                  --run-for <seconds>            run this much animation time (60 frames per second)
                  --frame-limit <n>              stop after n frames on the 60 Hz clock
                  --screenshot <path>            capture when the run ends
                  --screenshot-at <t> <path>     capture after t seconds of animation time
                  --scroll-at <t>:<x>:<y>:<dy>   scroll at t seconds (repeatable)
                  --resize-at <t>:<w>:<h>        resize at t seconds (repeatable)
                  --force-full-layout            rebuild every box on every layout pass
                  --no-incremental-layout        pre-0b name for --force-full-layout
                  --width <px>                   viewport width (default 800)
                  --height <px>                  viewport height (default 600)
                  --scale <n>                    display scale (default 2)
                  --zoom <n>                     page zoom (default 1)
                  --no-profile                   keep the trace but drop profiler counters

        Without --screenshot or --screenshot-at the runner only writes a trace.
        Example:
            swift run ToyStackHeadless file://$PWD/www/bench/large.html \\
              --trace /tmp/large.trace --frame-limit 600 --screenshot /tmp/large.png
        """)
    exit(2)
}

func parseArguments() -> HeadlessOptions? {
    var urlString: String? = nil
    var tracePath: String? = nil
    var screenshotPath: String? = nil
    var width: CGFloat = 800
    var height: CGFloat = 600
    var scale: CGFloat = 2.0
    var zoom: CGFloat = 1.0
    var runFor: Double? = nil
    var frameLimit: Int? = nil
    var forceFullLayout: Bool = false
    var events: [ScheduledEvent] = []
    var args: [String] = Array(CommandLine.arguments.dropFirst())

    func next(_ name: String) -> String {
        guard let value: String = args.first else {
            print("Missing value for \(name)")
            usage()
        }
        args.removeFirst()
        return value
    }

    while let arg: String = args.first {
        args.removeFirst()
        switch arg {
        case "--screenshot":
            screenshotPath = next(arg)
        case "--screenshot-at":
            guard let time: Double = Double(next(arg)), time >= 0 else { return nil }
            events.append(ScheduledEvent(time: time, action: .screenshot(path: next(arg))))
        case "--scroll-at":
            guard let event: ScheduledEvent = parseScrollEvent(next(arg)) else { return nil }
            events.append(event)
        case "--resize-at":
            guard let event: ScheduledEvent = parseResizeEvent(next(arg)) else { return nil }
            events.append(event)
        case "--trace":
            tracePath = next(arg)
        case "--run-for":
            guard let value: Double = Double(next(arg)), value >= 0 else { return nil }
            runFor = value
        case "--frame-limit":
            guard let value: Int = Int(next(arg)), value >= 0 else { return nil }
            frameLimit = value
        case "--force-full-layout", "--no-incremental-layout":
            forceFullLayout = true
        case "--no-profile":
            break
        case "--width":
            guard let value: Double = Double(next(arg)) else { return nil }
            width = CGFloat(value)
        case "--height":
            guard let value: Double = Double(next(arg)) else { return nil }
            height = CGFloat(value)
        case "--scale":
            guard let value: Double = Double(next(arg)) else { return nil }
            scale = CGFloat(value)
        case "--zoom":
            guard let value: Double = Double(next(arg)) else { return nil }
            zoom = CGFloat(value)
        default:
            guard !arg.hasPrefix("--") else { return nil }
            urlString = arg
        }
    }

    guard let urlString else { return nil }
    return HeadlessOptions(
        url: WebURL(urlString),
        viewport: ViewportOptions(width: width, height: height, scale: scale, zoom: zoom),
        output: OutputOptions(tracePath: tracePath, screenshotPath: screenshotPath),
        session: SessionOptions(
            runFor: runFor,
            frameLimit: frameLimit,
            forceFullLayout: forceFullLayout,
            events: events
        )
    )
}

private func parseScrollEvent(_ value: String) -> ScheduledEvent? {
    let parts: [String] = value.split(separator: ":", omittingEmptySubsequences: false)
        .map(String.init)
    guard parts.count == 4,
        let time: Double = Double(parts[0]),
        let x: Double = Double(parts[1]),
        let y: Double = Double(parts[2]),
        let deltaY: Double = Double(parts[3])
    else { return nil }
    return ScheduledEvent(
        time: time,
        action: .scroll(x: CGFloat(x), y: CGFloat(y), deltaY: CGFloat(deltaY))
    )
}

private func parseResizeEvent(_ value: String) -> ScheduledEvent? {
    let parts: [String] = value.split(separator: ":", omittingEmptySubsequences: false)
        .map(String.init)
    guard parts.count == 3,
        let time: Double = Double(parts[0]), time >= 0,
        let width: Double = Double(parts[1]), width > 0,
        let height: Double = Double(parts[2]), height > 0
    else { return nil }
    return ScheduledEvent(
        time: time,
        action: .resize(width: CGFloat(width), height: CGFloat(height))
    )
}

func animationFrameCount(for seconds: Double) -> Int {
    return max(0, Int((seconds * animationFramesPerSecond).rounded()))
}
