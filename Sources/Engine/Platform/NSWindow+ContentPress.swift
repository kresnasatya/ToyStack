import AppKit

extension NSWindow {
    public func contentReceivesPress(at locationInWindow: NSPoint) -> Bool {
        guard let content: NSView = contentView, let frameView: NSView = content.superview else { return false }
        let point: NSPoint = frameView.convert(locationInWindow, from: nil)
        guard let hit: NSView = frameView.hitTest(point) else { return false }
        return hit.isDescendant(of: content)
    }
}
