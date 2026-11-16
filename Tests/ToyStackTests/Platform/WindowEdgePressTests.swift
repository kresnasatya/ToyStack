import AppKit
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct WindowEdgePressTests {
    private func window(styleMask: NSWindow.StyleMask) -> NSWindow {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        return window
    }

    @Test(arguments: [NSPoint(x: 599, y: 200), NSPoint(x: 599, y: 1)])
    func pressOnTheResizeEdgeBelongsToTheWindow(point: NSPoint) {
        let resizable: NSWindow = window(styleMask: [.titled, .resizable])

        #expect(!resizable.contentReceivesPress(at: point))
    }

    @Test func pressOnTheScrollbarAwayFromTheEdgeBelongsToThePage() {
        let resizable: NSWindow = window(styleMask: [.titled, .resizable])

        #expect(resizable.contentReceivesPress(at: NSPoint(x: 594, y: 200)))
    }

    @Test func windowThatCannotResizeLeavesItsEdgeToThePage() {
        let fixed: NSWindow = window(styleMask: [.titled])

        #expect(fixed.contentReceivesPress(at: NSPoint(x: 599, y: 200)))
    }

    @Test func pressOutsideTheWindowNeverBelongsToThePage() {
        let resizable: NSWindow = window(styleMask: [.titled, .resizable])

        #expect(!resizable.contentReceivesPress(at: NSPoint(x: 640, y: 200)))
    }
}
