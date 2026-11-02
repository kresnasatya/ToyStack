import CoreGraphics

// MARK: - BoxStyle

struct BoxStyle: Equatable {
    var size: Size
    var spacing: Spacing
    var decoration: Decoration
    var zoom: CGFloat?

    static let initial: BoxStyle = BoxStyle(
        size: Size(width: nil, height: nil, maxWidth: nil, aspectRatio: nil),
        spacing: Spacing(margin: EdgeInsets(top: 0, right: 0, bottom: 0, left: 0),
                         padding: EdgeInsets(top: 0, right: 0, bottom: 0, left: 0)),
        decoration: Decoration(
            border: Decoration.Border(width: 3, color: BrowserColor(red: 0, green: 0, blue: 0), style: .none, radii: .zero),
            outline: Decoration.Outline(width: 3, color: nil, style: .none)
        ),
        zoom: nil
    )
}

// MARK: - Size

extension BoxStyle {
    struct Size: Equatable {
        var width: CGFloat?
        var height: CGFloat?
        var maxWidth: Length?
        var aspectRatio: AspectRatio?
    }
}

// MARK: - Spacing

extension BoxStyle {
    struct Spacing: Equatable {
        var margin: EdgeInsets
        var padding: EdgeInsets
    }
}

// MARK: - Decoration

extension BoxStyle {
    struct Decoration: Equatable {
        var border: Border
        var outline: Outline

        struct Border: Equatable {
            var width: CGFloat
            var color: BrowserColor
            var style: LineStyle
            var radii: CornerRadii
        }

        struct Outline: Equatable {
            var width: CGFloat
            var color: BrowserColor?
            var style: LineStyle
        }

        enum LineStyle: Equatable {
            case none
            case hidden
            case solid
            case dashed
            case dotted
            case other(String)

            init(css: String?) {
                switch css {
                case "none": self = .none
                case "hidden": self = .hidden
                case "solid": self = .solid
                case "dashed": self = .dashed
                case "dotted": self = .dotted
                case let value?: self = .other(value)
                case nil: self = .none
                }
            }
        }
    }
}
