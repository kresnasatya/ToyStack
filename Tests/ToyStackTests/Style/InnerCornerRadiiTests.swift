import CoreGraphics
import Testing

@testable import Engine

@Suite
struct InnerCornerRadiiTests {
    private let box: Rect = Rect(left: 0, top: 0, right: 100, bottom: 40)

    @Test func eachCornerLosesTheBordersThatMeetThere() {
        let outer: CornerRadii = .uniform(.px(10))
        let inner: CornerRadii = outer.inner(in: box, inset: EdgeInsets(top: 1, right: 2, bottom: 3, left: 4))

        #expect(inner.topLeft == CornerRadius(horizontal: .px(6), vertical: .px(9)))
        #expect(inner.topRight == CornerRadius(horizontal: .px(8), vertical: .px(9)))
        #expect(inner.bottomRight == CornerRadius(horizontal: .px(8), vertical: .px(7)))
        #expect(inner.bottomLeft == CornerRadius(horizontal: .px(6), vertical: .px(7)))
    }

    @Test func aBorderWiderThanTheCurveLeavesASquareCorner() {
        let inner: CornerRadii = CornerRadii.uniform(.px(3))
            .inner(in: box, inset: EdgeInsets(top: 5, right: 5, bottom: 5, left: 5))

        #expect(inner.isZero)
    }

    @Test func percentagesResolveAgainstTheBorderBox() {
        let inner: CornerRadii = CornerRadii.uniform(.percent(10))
            .inner(in: box, inset: EdgeInsets(top: 2, right: 2, bottom: 2, left: 2))

        #expect(inner.topLeft == CornerRadius(horizontal: .px(8), vertical: .px(2)))
    }
}
