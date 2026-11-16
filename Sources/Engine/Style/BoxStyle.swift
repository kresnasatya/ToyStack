import CoreGraphics

// MARK: - BoxStyle

struct BoxStyle: Equatable {
    var size: Size
    var spacing: Spacing
    var decoration: Decoration
    var zoom: CGFloat?

    /// Room between a box's content edge and its border edge on each side.
    var paddingAndBorder: EdgeInsets {
        return spacing.padding + decoration.border.usedWidths
    }

    static let initial: BoxStyle = BoxStyle(
        size: Size(
            width: nil,
            height: nil,
            boxSizing: .contentBox,
            constraints: Size.Constraints(maxWidth: nil, aspectRatio: nil)
        ),
        spacing: Spacing(margin: EdgeInsets(top: 0, right: 0, bottom: 0, left: 0),
                         padding: EdgeInsets(top: 0, right: 0, bottom: 0, left: 0)),
        decoration: Decoration(
            border: Decoration.Border(sides: .initial, radii: .zero),
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
        var boxSizing: BoxSizing
        var constraints: Constraints

        struct Constraints: Equatable {
            var maxWidth: Length?
            var aspectRatio: AspectRatio?
        }
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
            var sides: Sides
            var radii: CornerRadii

            var usedWidths: EdgeInsets {
                return EdgeInsets(
                    top: sides.top.usedWidth,
                    right: sides.right.usedWidth,
                    bottom: sides.bottom.usedWidth,
                    left: sides.left.usedWidth
                )
            }

            struct Sides: Equatable {
                var top: Side
                var right: Side
                var bottom: Side
                var left: Side

                static let initial: Sides = Sides(
                    top: .initial,
                    right: .initial,
                    bottom: .initial,
                    left: .initial
                )

                func same<Value: Equatable>(_ part: KeyPath<Side, Value>, as other: Sides) -> Bool {
                    return top[keyPath: part] == other.top[keyPath: part]
                        && right[keyPath: part] == other.right[keyPath: part]
                        && bottom[keyPath: part] == other.bottom[keyPath: part]
                        && left[keyPath: part] == other.left[keyPath: part]
                }
            }

            struct Side: Equatable {
                var width: CGFloat
                var color: BrowserColor
                var style: LineStyle

                static let initial: Side = Side(
                    width: 3,
                    color: BrowserColor(red: 0, green: 0, blue: 0),
                    style: .none
                )

                // CSS Backgrounds 3 §3.3: if the border-style is none or hidden,
                // the used width is 0, so the initial `medium` width takes no space.
                var usedWidth: CGFloat {
                    return style == .none || style == .hidden ? 0 : width
                }
            }
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
