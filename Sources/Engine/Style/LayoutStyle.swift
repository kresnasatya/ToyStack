import CoreGraphics

// MARK: - LayoutStyle

struct LayoutStyle: Equatable {
    var display: Display
    var position: Positioning
    var overflow: Overflow
    var zIndex: Int

    static let initial: LayoutStyle = LayoutStyle(
        display: .inline,
        position: Positioning(kind: .staticFlow, left: nil, top: nil),
        overflow: .visible,
        zIndex: 0
    )
}

// MARK: - Display

extension LayoutStyle {
    enum Display: Equatable {
        case inline
        case block
        case none
        case other(String)

        init(css: String?) {
            switch css {
            case "block": self = .block
            case "none": self = .none
            case "inline": self = .inline
            case let value?: self = .other(value)
            case nil: self = .inline
            }
        }
    }
}

// MARK: - Position

extension LayoutStyle {
    enum Position: Equatable {
        case staticFlow
        case relative
        case absolute
        case fixed
        case sticky
        case other(String)

        init(css: String?) {
            switch css {
            case "static": self = .staticFlow
            case "relative": self = .relative
            case "absolute": self = .absolute
            case "fixed": self = .fixed
            case "sticky": self = .sticky
            case let value?: self = .other(value)
            case nil: self = .staticFlow
            }
        }
    }

    struct Positioning: Equatable {
        var kind: Position
        var left: CGFloat?
        var top: CGFloat?
    }
}

// MARK: - Overflow

extension LayoutStyle {
    enum Overflow: Equatable {
        case visible
        case hidden
        case clip
        case scroll
        case auto
        case other(String)

        init(css: String?) {
            switch css {
            case "visible": self = .visible
            case "hidden": self = .hidden
            case "clip": self = .clip
            case "scroll": self = .scroll
            case "auto": self = .auto
            case let value?: self = .other(value)
            case nil: self = .visible
            }
        }
    }
}
