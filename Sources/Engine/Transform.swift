import CoreGraphics
import Foundation

public class Transform: VisualEffect {
    let translation: CGPoint?
    var isAnimated: Bool {
        guard let node = node else { return false }
        return node.animations["transform-x"] != nil || node.animations["transform-y"] != nil
    }

    init(translation: CGPoint?, rect: Rect, node: DOMNode?, children: [Any]) {
        self.translation = translation
        super.init(rect: rect, children: children, node: node)
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        if let t = translation {
            renderer.translateBy(x: t.x, y: t.y)
        }

        for child in children {
            if let ve = child as? VisualEffect {
                ve.execute(renderer: renderer)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, renderer: renderer)
            }
        }
        renderer.restoreState()
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
    let dx: CGFloat = reversed ? -t.x : t.x
    let dy: CGFloat = reversed ? -t.y : t.y
    return Rect(
        left: rect.left + dx, top: rect.top + dy, right: rect.right + dx, bottom: rect.bottom + dy)
}

func parseTransform(_ value: String) -> CGPoint? {
    let pattern: String = #"translate\((-?[0-9.]+)px,\s*(-?[0-9.]+)px\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
        let xRange = Range(match.range(at: 1), in: value),
        let yRange = Range(match.range(at: 2), in: value),
        let x = Double(value[xRange]),
        let y = Double(value[yRange])
    else { return nil }
    return CGPoint(x: x, y: y)
}
