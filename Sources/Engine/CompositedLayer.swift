import SwiftUI

class CompositedLayer {
    var displayItems: [PaintCommand] = []

    init(displayItem: PaintCommand) {
        self.displayItems = [displayItem]
    }

    func canMerge(_ displayItem: PaintCommand) -> Bool {
        return displayItem.parentEffect === displayItems[0].parentEffect
    }

    func add(_ displayItem: PaintCommand) {
        displayItems.append(displayItem)
    }

    func compositedBounds() -> Rect {
        return displayItems.reduce(
            Rect(left: 0, top: 0, right: 0, bottom: 0),
            {
                $0.union($1.rect)
            })
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
}
