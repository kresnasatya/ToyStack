import CoreGraphics
import Foundation

// MARK: - ArenaFieldStore

/// Value storage for one layout node's fields.
///
/// Named `ArenaFieldStore` only while the old class `LayoutFieldStore` is still
/// in use. B2 deletes that class and renames this type to `LayoutFieldStore`.
struct ArenaFieldStore {
    var geometry: GeometryFields
    var inlineText: InlineTextFields
    var state: FieldState

    init() {
        self.geometry = GeometryFields()
        self.inlineText = InlineTextFields()
        self.state = FieldState()
    }
}

extension ArenaFieldStore {
    func isUsed(_ field: LayoutField) -> Bool {
        return state.usedBits & field.mask != 0
    }

    func isDirty(_ field: LayoutField) -> Bool {
        return state.dirtyBits & field.mask != 0
    }

    func isFrozen(_ field: LayoutField) -> Bool {
        return state.frozenBits & field.mask != 0
    }

    mutating func markUsed(_ field: LayoutField) {
        state.usedBits |= field.mask
    }

    mutating func markDirty(_ field: LayoutField) {
        state.dirtyBits |= field.mask
    }

    mutating func markClean(_ field: LayoutField) {
        state.dirtyBits &= ~field.mask
    }

    mutating func markFrozen(_ field: LayoutField) {
        state.frozenBits |= field.mask
    }
}

// MARK: - GeometryFields

struct GeometryFields {
    var origin: Point
    var size: CGSize
    var zoom: CGFloat

    init() {
        self.origin = Point(x: 0, y: 0)
        self.size = CGSize(width: 0, height: 0)
        self.zoom = 1
    }
}

// MARK: - InlineTextFields

struct InlineTextFields {
    var font: BrowserFont
    var ascent: CGFloat
    var descent: CGFloat
    var inlineContent: UInt64

    init() {
        self.font = inlineDefaultFont
        self.ascent = 0
        self.descent = 0
        self.inlineContent = 0
    }
}

// MARK: - FieldState

struct FieldState {
    var usedBits: UInt16
    var dirtyBits: UInt16
    var frozenBits: UInt16

    init() {
        self.usedBits = 0
        self.dirtyBits = LayoutField.allMask
        self.frozenBits = 0
    }
}
