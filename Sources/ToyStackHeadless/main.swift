import Engine
import Foundation
import ImageIO
import UniformTypeIdentifiers

var urlString: String? = nil
var screenshotPath: String? = nil
var width: CGFloat = 800
var height: CGFloat = 600
var scale: CGFloat = 2.0

var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    switch arg {
        case "--screenshot":
            screenshotPath = args.first.map { $0 as String }; args.removeFirst()
        case "--width":
            width = CGFloat(Double(args.removeFirst()) ?? 800)
        case "--height":
            height = CGFloat(Double(args.removeFirst()) ?? 600)
        case "--scale":
            scale = CGFloat(Double(args.removeFirst()) ?? 2.0)
        default:
            urlString = arg
    }
}

func usage() -> Never {
    print("""
        Usage: swift run ToyStackHeadless <url> --screenshot output.png \
        [--width 800] [--height 600] [--scale 2]
        Example:
            swift run ToyStackHeadless https://browser.engineering --screenshot output.png
            swift run ToyStackHeadless file://$PWD/www/ui-free/effects.html --screenshot effects.png
        """)
    exit(2)
}

guard let urlString, let screenshotPath else { usage() }

func savePNG(_ image: CGImage, to path: String) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

MainActor.assumeIsolated {
    let browser = Browser()
    browser.resize(to: CGSize(width: width, height: height))
    browser.displayScale = scale
    browser.newTab(WebURL(urlString))

    func signature(_ list: [Any]) -> String {
        list.map { item -> String in
            if let cmd = item as? any PaintCommand { return "\(type(of: cmd)) \(cmd.rect)" }
            return "\(type(of: item))"
        }.joined(separator: "|")
    }

    let deadline = Date().addingTimeInterval(10)
    var last = signature(browser.drawList)
    var lastChange = Date()
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let now = signature(browser.drawList)
        if now != last {
            last = now
            lastChange = Date()
        } else if !browser.drawList.isEmpty, Date().timeIntervalSince(lastChange) >= 0.5 {
            break
        }
    }

    let image = CGRenderer.renderBitmap(
        width: browser.windowSize.width,
        height: browser.windowSize.height,
        scale: browser.displayScale,
        backgroundColor: EngineColor(cssName: "white")
    ) { r in
        if let tab = browser.activeTab {
            r.saveState()
            r.translateBy(x: 0, y: -browser.activeTabScroll)
            for item in browser.drawList {
                if let cmd = item as? any PaintCommand {
                    cmd.execute(scroll: 0, renderer: r)
                } else if let ve = item as? Engine.VisualEffect {
                    ve.execute(renderer: r)
                }
            }
            r.restoreState()

            r.saveState()
            r.translateBy(x: 0, y: 0)
            for item in tab.scrollbarCommands() {
                if let cmd = item as? any PaintCommand {
                    cmd.execute(scroll: 0, renderer: r)
                } else if let ve = item as? Engine.VisualEffect {
                    ve.execute(renderer: r)
                }
            }
            r.restoreState()
        }
    }

    guard let image else {
        print("Failed to create bitmap \(Int(width * scale))x\(Int(height * scale)) pixel")
        exit(1)
    }

    browser.stopAnimationTimer()
    if savePNG(image, to: screenshotPath) {
        print("Saved: \(screenshotPath) (\(image.width)x\(image.height) pixel)")
    } else {
        print("Failed to write PNG to \(screenshotPath)")
        exit(1)
    }
    exit(0)
}
