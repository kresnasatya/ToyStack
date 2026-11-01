import CoreGraphics
import Foundation

// MARK: - LayoutFieldAccess

@MainActor
protocol LayoutFieldAccess {
    associatedtype Value
    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> Value
    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: Value)
    static func equals(_ lhs: Value, _ rhs: Value) -> Bool
}

// MARK: CGFloatFieldAccess
enum CGFloatFieldAccess: LayoutFieldAccess {
    typealias Value = CGFloat

    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> CGFloat {
        switch field {
        case .x: return store.x
        case .y: return store.y
        case .width: return store.width
        case .height: return store.height
        case .zoom: return store.zoom
        case .ascent: return store.ascent
        case .descent: return store.descent
        default: preconditionFailure("\(field.rawValue) is not CGFloat field")
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
        default: preconditionFailure("\(field.rawValue) is not CGFloat field")
        }
    }

    static func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        return lhs == rhs
    }
}

// MARK: BrowserFont

@MainActor
enum FontFieldAccess: LayoutFieldAccess {
    typealias Value = BrowserFont

    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> BrowserFont {
        precondition(field == .font)
        return store.font
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: BrowserFont) {
        precondition(field == .font)
        store.font = value
    }

    static func equals(_ lhs: BrowserFont, _ rhs: BrowserFont) -> Bool {
        CFEqual(lhs.ctFont, rhs.ctFont)
    }
}

// MARK: UInt64

@MainActor
enum InlineContentFieldAccess: LayoutFieldAccess {
    typealias Value = UInt64

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

// MARK: [any LayoutObject]

@MainActor
enum ChildrenFieldAccess: LayoutFieldAccess {
    typealias Value = [any LayoutObject]

    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> [any LayoutObject] {
        precondition(field == .children)
        return store.children
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: [any LayoutObject]) {
        precondition(field == .children)
        store.children = value
    }

    static func equals(_ lhs: [any LayoutObject], _ rhs: [any LayoutObject]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy({ $0 === $1 })
    }
}

// MARK: (any LayoutObject)?

@MainActor
enum PreviousFieldAccess: LayoutFieldAccess {
    typealias Value = (any LayoutObject)?

    static func read(_ store: LayoutFieldStore, _ field: LayoutField) -> (any LayoutObject)? {
        precondition(field == .previous)
        return store.previous
    }

    static func write(_ store: LayoutFieldStore, _ field: LayoutField, _ value: (any LayoutObject)?) {
        precondition(field == .previous)
        store.previous = value
    }

    static func equals(_ lhs: (any LayoutObject)?, _ rhs: (any LayoutObject)?) -> Bool {
        return lhs === rhs
    }
}
