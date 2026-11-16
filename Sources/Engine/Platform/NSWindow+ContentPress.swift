import AppKit

extension NSWindow {
    // AppKit sizes a window from a strip that reaches a few points inside its
    // frame, so the page's right and bottom edges overlap the resize border.
    // A local event monitor sees the press before the window does; asking the
    // frame view's hit test leaves those presses to the window, the same way
    // it would decide without the monitor.
    public func contentReceivesPress(at locationInWindow: NSPoint) -> Bool {
        guard let content: NSView = contentView, let frameView: NSView = content.superview else { return false }
        let point: NSPoint = frameView.convert(locationInWindow, from: nil)
        guard let hit: NSView = frameView.hitTest(point) else { return false }
        return hit.isDescendant(of: content)
    }
}
