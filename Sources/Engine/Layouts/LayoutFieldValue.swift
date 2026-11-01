import CoreGraphics
import Foundation

// MARK: - LayoutFieldValue

@MainActor
protocol LayoutFieldValue {
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> Self
    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: Self)
    static func equals(_ lhs: Self, _ rhs: Self) -> Bool
}

// MARK: CGFloat

extension CGFloat: LayoutFieldValue {
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> CGFloat {
        switch field {
        case .x: return store.x
        case .y: return store.y
        case .width: return store.width
        case .height: return store.height
        case .zoom: return store.zoom
        case .ascent: return store.ascent
        case .descent: return store.descent
        default: preconditionFailure("\(field.rawValue) is not a CGFloat field")
        }
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: CGFloat) {
        switch field {
        case .x: store.x = value
        case .y: store.y = value
        case .width: store.width = value
        case .height: store.height = value
        case .zoom: store.zoom = value
        case .ascent: store.ascent = value
        case .descent: store.descent = value
        default: preconditionFailure("\(field.rawValue) is not a CGFloat field")
        }
    }

    static func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        return lhs == rhs
    }
}

// MARK: UInt64

extension UInt64: LayoutFieldValue {
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> UInt64 {
        precondition(field == .inlineContent)
        return store.inlineContent
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: UInt64) {
        precondition(field == .inlineContent)
        store.inlineContent = value
    }

    static func equals(_ lhs: UInt64, _ rhs: UInt64) -> Bool {
        return lhs == rhs
    }
}

// MARK: BrowserFont

extension BrowserFont: LayoutFieldValue {
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> BrowserFont {
        precondition(field == .font)
        return store.font
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: BrowserFont) {
        precondition(field == .font)
        store.font = value
    }

    static func equals(_ lhs: BrowserFont, _ rhs: BrowserFont) -> Bool {
        return CFEqual(lhs.ctFont, rhs.ctFont)
    }
}

// MARK: [any LayoutObject]

extension Array: LayoutFieldValue where Element == any LayoutObject {
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> Self {
        precondition(field == .children)
        return store.children
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: Self) {
        precondition(field == .children)
        store.children = value
    }

    static func equals(_ lhs: Self, _ rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy({ $0 === $1 })
    }
}

// MARK: (any LayoutObject)?

extension Optional: LayoutFieldValue where Wrapped == any LayoutObject {
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> Self {
        precondition(field == .previous)
        return store.previous
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: Self) {
        precondition(field == .previous)
        store.previous = value
    }

    static func equals(_ lhs: Self, _ rhs: Self) -> Bool {
        return lhs === rhs
    }
}
