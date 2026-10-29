import Engine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
func capture(_ browser: Browser, scale: CGFloat, to path: String) -> Bool {
    guard let image: CGImage = renderImage(browser, scale: scale) else {
        return false
    }
    return savePNG(image, to: path)
}

@MainActor
private func renderImage(_ browser: Browser, scale: CGFloat) -> CGImage? {
    let size: CGSize = browser.windowSize
    return CGRenderer.renderBitmap(
        size: size,
        scale: scale,
        backgroundColor: BrowserColor(cssName: "white")
    ) { renderer in
        guard let tab: BrowserTab = browser.activeTab else { return }
        renderer.saveState()
        ContentTransform(
            pageZoom: browser.pageZoom,
            scroll: browser.activeTabScroll,
            topInset: 0
        ).apply(to: renderer)
        for item in browser.drawList {
            if let command = item as? any DisplayCommand {
                command.execute(scroll: 0, renderer: renderer)
            } else if let effect = item as? BrowserVisualEffect {
                effect.execute(renderer: renderer)
            }
        }
        renderer.restoreState()

        renderer.saveState()
        renderer.scaleBy(x: browser.pageZoom, y: browser.pageZoom)
        for command in tab.scrollbarCommands() {
            command.execute(scroll: 0, renderer: renderer)
        }
        renderer.restoreState()
    }
}

private func savePNG(_ image: CGImage, to path: String) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}
