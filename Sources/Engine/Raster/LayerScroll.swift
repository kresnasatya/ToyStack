import CoreGraphics

struct LayerScroll: Sendable {
    let clips: [ClipShape]
    let offset: CGFloat

    init(clips: [ClipShape], offset: CGFloat) {
        self.clips = clips
        self.offset = offset
    }
}

extension LayerScroll {
    static func resolve(_ ancestorChain: [EffectScope]) -> LayerScroll? {
        var clips: [ClipShape] = []
        var offset: CGFloat = 0
        for scope in ancestorChain.reversed() {
            guard case .scroll(let shape, let scrollOffset) = scope.kind else { continue }
            clips.append(ClipShape(rect: shape.rect.translated(dx: 0, dy: offset), radii: shape.radii))
            offset -= scrollOffset
        }
        return clips.isEmpty ? nil : LayerScroll(clips: clips, offset: offset)
    }

    func placed(_ items: [DisplayOp]) -> [DisplayOp] {
        return items.map { $0.shifted(dx: 0, dy: offset) }
    }

    func visibleBounds(of bounds: Rect) -> Rect {
        var visible: Rect = bounds.translated(dx: 0, dy: offset)
        for clip in clips {
            visible = visible.intersect(clip.rect)
        }
        return visible
    }

    func combineClips(into hasher: inout Hasher) {
        for clip in clips {
            hasher.combine(clip.rect.left)
            hasher.combine(clip.rect.top)
            hasher.combine(clip.rect.right)
            hasher.combine(clip.rect.bottom)
            hasher.combine(clip.radii)
        }
    }
}
