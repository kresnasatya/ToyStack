import CoreGraphics
import CoreText

// MARK: - DisplayCommand
public protocol DisplayCommand: DisplayItem {
    var parentEffect: VisualEffect? { get set }
    func execute(scroll: CGFloat, renderer: any Renderer)
}

extension DisplayCommand {
    var contentHash: Int {
        var hasher: Hasher = Hasher()
        hasher.combine(String(describing: type(of: self)))
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
            hasher.combine(CTFontCopyPostScriptName(cmd.font.ctFont) as String)
            hasher.combine(CTFontGetSize(cmd.font.ctFont))
        } else if let cmd = self as? DrawOutline {
            hasher.combine(cmd.color)
            hasher.combine(cmd.thickness)
        } else if let cmd = self as? DrawRRect {
            hasher.combine(cmd.color)
            hasher.combine(cmd.radius)
        }
        return hasher.finalize()
    }
}
