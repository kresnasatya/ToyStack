import CoreGraphics
import CoreText

// MARK: - DisplayCommand
public protocol DisplayCommand: DisplayItem {
    var parentEffect: BrowserVisualEffect? { get set }
    func execute(scroll: CGFloat, renderer: any Renderer)
    func shifted(dx: CGFloat, dy: CGFloat) -> any DisplayCommand
}

extension DisplayCommand {
    var contentHash: Int {
        var hasher: Hasher = Hasher()
        hasher.combine(ObjectIdentifier(type(of: self)))
        hasher.combine(rect.left)
        hasher.combine(rect.top)
        hasher.combine(rect.right)
        hasher.combine(rect.bottom)
        if let cmd = self as? DrawRect {
            hasher.combine(cmd.color)
        } else if let cmd = self as? DrawLine {
            hasher.combine(cmd.color)
            hasher.combine(cmd.thickness)
        } else if let cmd = self as? DrawText {
            hasher.combine(cmd.text)
            hasher.combine(cmd.color)
            hasher.combine(ObjectIdentifier(cmd.font.ctFont))
        } else if let cmd = self as? DrawOutline {
            hasher.combine(cmd.color)
            hasher.combine(cmd.thickness)
        } else if let cmd = self as? DrawRRect {
            hasher.combine(cmd.color)
            hasher.combine(cmd.radii)
        } else if let cmd = self as? DrawImage {
            hasher.combine(ObjectIdentifier(cmd.image))
            hasher.combine(cmd.rendering.rawValue)
            hasher.combine(cmd.contentVersion)
        } else if let cmd = self as? DrawClippedImage {
            hasher.combine(ObjectIdentifier(cmd.image))
            hasher.combine(cmd.rendering.rawValue)
            hasher.combine(cmd.clip.left)
            hasher.combine(cmd.clip.top)
            hasher.combine(cmd.clip.right)
            hasher.combine(cmd.clip.bottom)
        }
        return hasher.finalize()
    }
}
