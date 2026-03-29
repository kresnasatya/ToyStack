import SwiftUI

public class Transform: VisualEffect {
    let translation: CGPoint?

    init(translation: CGPoint?, rect: Rect, node: DOMNode?, children: [Any]) {
        self.translation = translation
        super.init(rect: rect, children: children, node: node)
    }

    public override func execute(context: inout GraphicsContext) {
        if let t = translation {
            context.translateBy(x: t.x, y: t.y)
        }

        for child in children {
            if let ve = child as? VisualEffect {
                ve.execute(context: &context)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, context: &context)
            }
        }
        if let t = translation {
            context.translateBy(x: -t.x, y: -t.y)
        }
    }

    func clone(child: Any) -> Transform {
        return Transform(translation: translation, rect: rect, node: node, children: [child])
    }

    override func map(rect: Rect) -> Rect {
        guard let t = translation else { return rect }
        return Rect(
            left: rect.left + t.x, top: rect.top + t.y, right: rect.right + t.x,
            bottom: rect.bottom + t.y)
    }

    override func unmap(rect: Rect) -> Rect {
        guard let t = translation else { return rect }
        return Rect(
            left: rect.left - t.x, top: rect.top - t.y, right: rect.right - t.x,
            bottom: rect.bottom - t.y)
    }
}

func mapTranslation(rect: Rect, translation: CGPoint?, reversed: Bool = false) -> Rect {
    guard let t = translation else { return rect }
    let dx = reversed ? -t.x : t.x
    let dy = reversed ? -t.y : t.y
    return Rect(
        left: rect.left + dx, top: rect.top + dy, right: rect.right + dx, bottom: rect.bottom + dy)
}
