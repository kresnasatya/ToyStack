import CoreGraphics
import Foundation

// MARK: - LayoutFieldStore

struct LayoutFieldStore {
    var geometry: GeometryFields
    var inlineText: InlineTextFields
    var state: FieldState

    init() {
        self.geometry = GeometryFields()
        self.inlineText = InlineTextFields()
        self.state = FieldState()
    }
}

extension LayoutFieldStore {
    func isUsed(_ field: LayoutField) -> Bool {
        return state.isUsed(field)
    }

    func isDirty(_ field: LayoutField) -> Bool {
        return state.isDirty(field)
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

    init() {
        self.usedBits = 0
        self.dirtyBits = LayoutField.allMask
    }
}

extension FieldState {
    func isUsed(_ field: LayoutField) -> Bool {
        return usedBits & field.mask != 0
    }

    func isDirty(_ field: LayoutField) -> Bool {
        return dirtyBits & field.mask != 0
    }
}
