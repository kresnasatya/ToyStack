import CoreGraphics

// MARK: - LayoutStyle

struct LayoutStyle: Equatable {
    var display: Display
    var position: Positioning
    var overflow: Overflow
    var zIndex: Int

    static let initial: LayoutStyle = LayoutStyle(
        display: .inline,
        position: Positioning(kind: .staticFlow, left: nil, top: nil, floating: .none),
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

        // CSS Display 3 §2.2 and §2.3: a value that names only the inside layout (flex,
        // grid, flow-root, table) or list-item is block-level on the outside. ToyStack lays
        // the children out as normal blocks, but the box still starts on its own line.
        init(css: String?) {
            switch css {
            case "block", "flex", "grid", "flow-root", "list-item", "table": self = .block
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
        var floating: Floating
    }
}

// MARK: - Float

extension LayoutStyle {
    /// CSS 2.1 §9.3: floats are one of the three positioning schemes, so they
    /// live beside `position` rather than beside `display`.
    struct Floating: Equatable {
        var side: FloatSide
        var clear: ClearSide

        static let none: Floating = Floating(side: .none, clear: .none)
    }

    enum FloatSide: Equatable {
        case none
        case left
        case right

        init(css: String?) {
            switch css {
            case "left": self = .left
            case "right": self = .right
            default: self = .none
            }
        }
    }

    enum ClearSide: Equatable {
        case none
        case left
        case right
        case both

        init(css: String?) {
            switch css {
            case "left": self = .left
            case "right": self = .right
            case "both": self = .both
            default: self = .none
            }
        }

        func clears(_ side: FloatSide) -> Bool {
            switch (self, side) {
            case (.both, .left), (.both, .right), (.left, .left), (.right, .right): return true
            default: return false
            }
        }
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
