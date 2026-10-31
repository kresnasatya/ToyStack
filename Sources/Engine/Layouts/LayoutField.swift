import Foundation

// MARK: - LayoutField

@MainActor
enum LayoutField: String, CaseIterable {
    case x
    case y
    case width
    case height
    case zoom
    case children
    case previous
    case font
    case ascent
    case descent
    case inlineContent

    var mask: UInt16 {
        switch self {
        case .x: return 1 << 0
        case .y: return 1 << 1
        case .width: return 1 << 2
        case .height: return 1 << 3
        case .zoom: return 1 << 4
        case .children: return 1 << 5
        case .previous: return 1 << 6
        case .font: return 1 << 7
        case .ascent: return 1 << 8
        case .descent: return 1 << 9
        case .inlineContent: return 1 << 10
        }
    }

    static let allMask: UInt16 = LayoutField.allCases.reduce(0) { mask, field in
        mask | field.mask
    }
}
