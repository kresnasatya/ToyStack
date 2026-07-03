import SwiftUI

class CompositedLayer {
    var displayItems: [PaintCommand] = []
    static let maxArea: CGFloat = 2 * WIDTH * HEIGHT
    static let shortDisplayListLimit = 3
    var cachedImage: CGImage? = nil
    var needsTexture: Bool {
        displayItems.count >= Self.shortDisplayListLimit
    }

    init(displayItem: PaintCommand) {
        self.displayItems = [displayItem]
    }

    func canMerge(_ displayItem: PaintCommand) -> Bool {
        guard displayItem.parentEffect === displayItems[0].parentEffect else {
            return false
        }
        let merged = compositedBounds().union(displayItem.rect)
        let area = (merged.right - merged.left) * (merged.bottom - merged.top)
        return area <= Self.maxArea
    }

    func add(_ displayItem: PaintCommand) {
        displayItems.append(displayItem)
        cachedImage = nil
    }

    func compositedBounds() -> Rect {
        guard let first = displayItems.first else {
            return Rect(left: 0, top: 0, right: 0, bottom: 0)
        }
        return displayItems.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }

    func absoluteBounds() -> Rect {
        var rect = compositedBounds()
        var effect: VisualEffect? = displayItems.first?.parentEffect
        while let e = effect {
            rect = e.map(rect: rect)
            effect = e.parent
        }
        return rect
    }

    func raster(context: inout GraphicsContext) {
        let bounds = compositedBounds()
        guard bounds.right > bounds.left && bounds.bottom > bounds.top else { return }
        context.translateBy(x: -bounds.left, y: -bounds.top)
        for item in displayItems {
            item.execute(scroll: 0, context: &context)
        }
        context.translateBy(x: bounds.left, y: bounds.top)
    }

    @MainActor
    func rasterIfNeeded(scale: CGFloat) {
        // Exercise 13-8: short display lists get no texture; draw executes their commands directly instead.
        guard needsTexture, cachedImage == nil else { return }
        let bounds = compositedBounds()
        let width = bounds.right - bounds.left
        let height = bounds.bottom - bounds.top
        guard width > 0, height > 0 else { return }

        let items = displayItems
        let canvas = Canvas { context, _ in
            var ctx = context
            ctx.translateBy(x: -bounds.left, y: -bounds.top)
            for item in items {
                item.execute(scroll: 0, context: &ctx)
            }
        }
        .frame(width: width, height: height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        cachedImage = renderer.cgImage
    }
}
