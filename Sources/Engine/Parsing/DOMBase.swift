import Foundation

// MARK: - DOMBase

struct DOMBase {
    var parent: NodeID?
    var children: [NodeID]
    var style: StyleFields
    var state: DOMState
}

extension DOMBase {
    @MainActor
    init() {
        self.parent = nil
        self.children = []
        self.style = StyleFields()
        self.state = DOMState()
    }
}

// MARK: - DOMState

struct DOMState {
    var flags: DOMFlags
    var animations: [AnimationKey: Animation]
}

extension DOMState {
    init() {
        self.flags = DOMFlags()
        self.animations = [:]
    }
}

// MARK: - DOMFlags

struct DOMFlags {
    var isFocused: Bool
    var isFocusVisible: Bool
    var isHovered: Bool
    var satisfiedHas: Set<Int>
}

extension DOMFlags {
    init() {
        self.isFocused = false
        self.isFocusVisible = false
        self.isHovered = false
        self.satisfiedHas = []
    }
}
