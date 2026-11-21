import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct CommentLayoutTests {
    private let css: String = """
        body { display: block; }
        div { display: block; }
        p { display: block; }
    """

    @Test func commentsDoNotChangeLayoutOrPaint() {
        let plain: LayoutTestPage = LayoutTestPage(
            html: "<div><p>one</p>two<span>three</span></div>",
            rules: css
        )
        let commented: LayoutTestPage = LayoutTestPage(
            html: "<div><!--$--><p>one</p><!-- -->two<span><!--x-->three</span><!--/$--></div>",
            rules: css
        )
        #expect(renderSignature(commented.frame) == renderSignature(plain.frame))
    }
}
