import CoreGraphics

public enum EffectKind {
    case blend(opacity: Double, mode: BrowserBlendMode?)
    case blur(radius: CGFloat)
    case clip(ClipShape)
    case transform(CGPoint?)
    case scroll(ClipShape, offset: CGFloat)
}
