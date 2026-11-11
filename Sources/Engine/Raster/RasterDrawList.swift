import CoreGraphics

enum RasterDrawList {
    static func compute(layers: [RasterLayer], inputs: RasterInput) -> [DisplayOp] {
        var layerByIndex: [Int: RasterLayer] = [:]
        for layer in layers where layer.identity.firstCommandIndex >= 0 {
            layerByIndex[layer.identity.firstCommandIndex] = layer
        }

        let scale: ContentScale = inputs.settings.viewport.scale
        let viewportHeight: CGFloat = (inputs.settings.viewport.windowSize.height - inputs.settings.viewport.topInset) / scale.page
        let visibleTop: CGFloat = inputs.scrollState.scroll - 2 * RasterLayer.tileSize
        let visibleBottom: CGFloat = inputs.scrollState.scroll + viewportHeight + 2 * RasterLayer.tileSize

        var commandIndex: Int = 0
        var drawList: [DisplayOp] = []
        drawList.reserveCapacity(inputs.scene.displayList.count)
        for op in inputs.scene.displayList {
            switch op {
            case .beginEffect(let scope):
                drawList.append(.beginEffect(updatedScope(scope, updates: inputs.scene.compositedUpdates)))
            case .endEffect:
                drawList.append(op)
            default:
                if let layer: RasterLayer = layerByIndex[commandIndex] {
                    drawList.append(
                        .compositedLayer(
                            layer: layer,
                            rect: layer.absoluteBounds(),
                            visibleTop: visibleTop,
                            visibleBottom: visibleBottom
                        )
                    )
                }
                commandIndex += 1
            }
        }

        if let bounds = inputs.settings.accessibility.hoveredBounds {
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: inputs.settings.preferences.usesForcedColors ? ForcedColor.highlight : "white"), width: 4))
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: "black"), width: 2))
        }

        if let bounds = inputs.settings.accessibility.readBounds {
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: "gold"), width: 4))
            drawList.append(.outline(rect: bounds, color: BrowserColor(cssName: "black"), width: 2))
        }

        return drawList
    }

    static func placements(
        _ layers: [RasterLayer],
        effectStrategies: [LayerEffectStrategy]
    ) -> [LayerPlacement] {
        let t: CGFloat = RasterLayer.tileSize
        var placements: [LayerPlacement] = []
        for (z, layer) in layers.enumerated() {
            switch effectStrategies[z].kind {
            case .flat:
                for index in layer.orderedTileIndices {
                    guard let image: CGImage = layer.tiles[index] else { continue }
                    placements.append(
                        LayerPlacement(
                            key: .tile(zIndex: z, col: index.col, row: index.row),
                            image: image,
                            frame: CGRect(
                                x: CGFloat(index.col) * t,
                                y: CGFloat(index.row) * t,
                                width: t,
                                height: t
                            ),
                        )
                    )
                }
            case .ca:
                guard let image = layer.effect.image else { break }
                let bounds: Rect = layer.compositedBounds()
                placements.append(
                    LayerPlacement(
                        key: .composited(zIndex: z),
                        image: image,
                        frame: CGRect(x: bounds.left, y: bounds.top, width: bounds.right - bounds.left, height: bounds.bottom - bounds.top),
                        effect: effectStrategies[z].effect
                    )
                )
            case .blendFallback, .scrollFallback:
                break
            }
        }
        return placements
    }

    private static func updatedScope(
        _ scope: EffectScope,
        updates: [NodeID: EffectUpdate]
    ) -> EffectScope {
        guard let node = scope.placement.node, let update = updates[node] else { return scope }
        let kind: EffectKind
        switch scope.kind {
        case .blend:
            kind = .blend(opacity: update.style.opacity, mode: update.style.blendMode)
        case .transform:
            kind = .transform(update.style.translation)
        case .blur:
            kind = .blur(radius: update.style.blurRadius)
        case .clip, .scroll:
            kind = scope.kind
        }
        return EffectScope(
            id: scope.id,
            kind: kind,
            placement: EffectPlacement(
                rect: scope.placement.rect,
                node: scope.placement.node,
                animatedTransform: update.isAnimatedTransform
            )
        )
    }
}
