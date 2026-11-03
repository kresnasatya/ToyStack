import Foundation

/// Builds raster layers from a frozen display list.
enum RasterCompositor {
    static func compute(
        _ inputs: RasterInput,
        measure: MeasureTime,
        frame: Int
    ) -> [RasterLayer] {
        measure.start("raster.composite.scan", category: .raster, frame: frame)
        var compositedLayers: [RasterLayer] = []
        var scopes: [EffectScope] = []
        var ordinals: [EffectScopeID?: Int] = [:]
        var animatedTransforms: Int = 0
        var assumeOverlap: Bool = false
        var commandIndex: Int = 0

        for op in inputs.scene.displayList {
            switch op {
            case .beginEffect(let scope):
                scopes.append(scope)
                if case .transform = scope.kind, scope.placement.animatedTransform {
                    animatedTransforms += 1
                }
            case .endEffect:
                let scope: EffectScope = scopes.removeLast()
                if case .transform = scope.kind, scope.placement.animatedTransform {
                    animatedTransforms -= 1
                }
            default:
                let scopeID: EffectScopeID? = scopes.last?.id
                if animatedTransforms > 0 { assumeOverlap = true }
                var merged: Bool = false
                for index in compositedLayers.indices.reversed() {
                    let layer: RasterLayer = compositedLayers[index]
                    if layer.identity.id.effect == scopeID {
                        compositedLayers[index].add(op)
                        merged = true
                        break
                    } else if assumeOverlap {
                        break
                    }
                }
                if !merged {
                    let ordinal: Int = ordinals[scopeID, default: 0]
                    ordinals[scopeID] = ordinal + 1
                    var layer: RasterLayer = RasterLayer(
                        displayItem: op,
                        firstCommandIndex: commandIndex,
                        id: LayerID(effect: scopeID, ordinal: ordinal)
                    )
                    layer.identity.ancestorChain = Array(scopes.reversed())
                    compositedLayers.append(layer)
                }
                commandIndex += 1
            }
        }

        reuseEffectImages(from: inputs.scene.previousLayers, into: &compositedLayers)
        measure.stop("raster.composite.scan")
        return compositedLayers
    }

    private static func reuseEffectImages(from previous: [RasterLayer], into layers: inout [RasterLayer]) {
        guard !previous.isEmpty else { return }
        var pool: [LayerID: [RasterLayer]] = [:]
        for layer in previous {
            pool[layer.identity.id, default: []].append(layer)
        }
        for index in layers.indices {
            let id: LayerID = layers[index].identity.id
            guard var candidates = pool[id], let source = candidates.popLast() else { continue }
            pool[id] = candidates
            layers[index].effect = source.effect
        }
    }
}
