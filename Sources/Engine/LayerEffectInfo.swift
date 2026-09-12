import CoreGraphics

struct LayerEffectInfo {
    enum Kind: Comparable {
        case flat
        case ca
        case blendFallback
        case scrollFallback
    }

    let kind: Kind
    let effect: LayerEffect?
    let blur: CGFloat

    init(kind: Kind, effect: LayerEffect?, blur: CGFloat) {
        self.kind = kind
        self.effect = effect
        self.blur = blur
    }
}
