import CoreGraphics
import Foundation

// MARK: - DOMSideTables

/// Cold per-node state. Only nodes that use a feature get an entry.
struct DOMSideTables {
    var images: ImageTable
    var embeds: EmbedTable
    var canvases: CanvasTable
    var scrollOffsets: [NodeID: CGFloat]
}

extension DOMSideTables {
    init() {
        self.images = ImageTable()
        self.embeds = EmbedTable()
        self.canvases = CanvasTable()
        self.scrollOffsets = [:]
    }
}

// MARK: - ImageTable

struct ImageTable {
    var images: [NodeID: CGImage]
    var backgrounds: [NodeID: CGImage]
    var backgroundSources: [NodeID: String]
    var revision: UInt64
}

extension ImageTable {
    init() {
        self.images = [:]
        self.backgrounds = [:]
        self.backgroundSources = [:]
        self.revision = 0
    }
}

// MARK: - EmbedTable

struct EmbedTable {
    var frames: [NodeID: FrameID]
    var frameSources: [NodeID: String]
}

extension EmbedTable {
    init() {
        self.frames = [:]
        self.frameSources = [:]
    }
}

// MARK: - CanvasTable

struct CanvasTable {
    var contexts: [NodeID: CanvasRenderingContext2D]
}

extension CanvasTable {
    init() {
        self.contexts = [:]
    }
}
