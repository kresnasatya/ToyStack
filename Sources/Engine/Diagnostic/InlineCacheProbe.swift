import Foundation

private let inlineProbeEnabled: Bool =
    ProcessInfo.processInfo.environment["TOYSTACK_INLINE_PROBE"] == "1"

@MainActor
func inlineCacheProbe(_ frame: Frame, _ label: String) {
    guard inlineProbeEnabled else { return }
    frame.withLayoutTree { tree in
        var blocks: Int = 0
        var totalBlocks: Int = 0
        var items: Int = 0
        var objects: Int = 0
        var mismatched: Int = 0
        var samples: [String] = []

        for id in tree.liveIDs where tree.isBlock(id) {
            totalBlocks += 1
            let data: BlockData = tree[block: id]
            let itemCount: Int = data.content.inlineItems.count
            let objectCount: Int = data.content.inlineObjects.count
            guard itemCount > 0 || objectCount > 0 else { continue }
            blocks += 1
            items += itemCount
            objects += objectCount
            if itemCount != objectCount { mismatched += 1 }
            if samples.count < 4 {
                samples.append("\(id.raw):\(itemCount)/\(objectCount)")
            }
        }

        print(
            "INLINE_PROBE \(label) blocks=\(blocks) totalBlocks=\(totalBlocks) items=\(items) objects=\(objects) mismatched=\(mismatched) sample=[\(samples.joined(separator: ","))]"
        )
    }
}
