import CoreGraphics
import Foundation

// MARK: - LayoutFieldAccess

@MainActor
protocol LayoutFieldAccess {
    associatedtype Value
    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> Value
    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: Value)
    static func equals(_ lhs: Value, _ rhs: Value) -> Bool
}

// MARK: CGFloatFieldAccess
enum CGFloatFieldAccess: LayoutFieldAccess {
    typealias Value = CGFloat

    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> CGFloat {
        let fields: LayoutFieldStore = tree.node(id).state.fields
        switch field {
        case .x: return fields.geometry.origin.x
        case .y: return fields.geometry.origin.y
        case .width: return fields.geometry.size.width
        case .height: return fields.geometry.size.height
        case .zoom: return fields.geometry.zoom
        case .ascent: return fields.inlineText.ascent
        case .descent: return fields.inlineText.descent
        default: preconditionFailure("\(field.rawValue) is not CGFloat field")
        }
    }

    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: CGFloat) {
        tree.writeCGFloat(field, value, for: id)
    }

    static func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        return lhs == rhs
    }
}

// MARK: BrowserFont

@MainActor
enum FontFieldAccess: LayoutFieldAccess {
    typealias Value = BrowserFont

    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> BrowserFont {
        precondition(field == .font)
        return tree.node(id).state.fields.inlineText.font
    }

    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: BrowserFont) {
        precondition(field == .font)
        tree.writeFont(value, for: id)
    }

    static func equals(_ lhs: BrowserFont, _ rhs: BrowserFont) -> Bool {
        CFEqual(lhs.ctFont, rhs.ctFont)
    }
}

// MARK: UInt64

@MainActor
enum InlineContentFieldAccess: LayoutFieldAccess {
    typealias Value = UInt64

    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> UInt64 {
        precondition(field == .inlineContent)
        return tree.node(id).state.fields.inlineText.inlineContent
    }

    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: UInt64) {
        precondition(field == .inlineContent)
        tree.writeInlineContent(value, for: id)
    }

    static func equals(_ lhs: UInt64, _ rhs: UInt64) -> Bool {
        return lhs == rhs
    }
}

// MARK: [LayoutID]

@MainActor
enum ChildrenFieldAccess: LayoutFieldAccess {
    typealias Value = [LayoutID]

    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> [LayoutID] {
        precondition(field == .children)
        return tree.children(of: id)
    }

    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: [LayoutID]) {
        precondition(field == .children)
        tree.setChildren(value, of: id)
    }

    static func equals(_ lhs: [LayoutID], _ rhs: [LayoutID]) -> Bool {
        return lhs == rhs
    }
}

// MARK: LayoutID?

@MainActor
enum PreviousFieldAccess: LayoutFieldAccess {
    typealias Value = LayoutID?

    static func read(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField) -> LayoutID? {
        precondition(field == .previous)
        return tree.node(id).links.previous
    }

    static func write(_ tree: LayoutTree, _ id: LayoutID, _ field: LayoutField, _ value: LayoutID?) {
        precondition(field == .previous)
        tree.setPrevious(value, of: id)
    }

    static func equals(_ lhs: LayoutID?, _ rhs: LayoutID?) -> Bool {
        return lhs == rhs
    }
}
