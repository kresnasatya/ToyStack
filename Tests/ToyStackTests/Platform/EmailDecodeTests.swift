import Testing

@testable import Engine

// The decoder script is copied unchanged from Cloudflare (served on
// theodorusclarence.com). Cloudflare hides e-mail links behind
// "/cdn-cgi/l/email-protection#<hex>" and this script turns them back into "mailto:".
@Suite(.serialized)
@MainActor
struct EmailDecodeTests {
    private let decoder: String = #"""
        !function(){"use strict";function e(e){try{if("undefined"==typeof console)return;"error"in console?console.error(e):console.log(e)}catch(e){}}function t(e){return d.innerHTML='<a href="'+e.replace(/"/g,"&quot;")+'"></a>',d.childNodes[0].getAttribute("href")||""}function r(e,t){var r=e.substr(t,2);return parseInt(r,16)}function n(n,c){for(var o="",a=r(n,c),i=c+2;i<n.length;i+=2){var l=r(n,i)^a;o+=String.fromCharCode(l)}try{o=decodeURIComponent(escape(o))}catch(u){e(u)}return t(o)}function c(t){for(var r=t.querySelectorAll("a"),c=0;c<r.length;c++)try{var o=r[c],a=o.href.indexOf(l);a>-1&&(o.href="mailto:"+n(o.href,a+l.length))}catch(i){e(i)}}function o(t){for(var r=t.querySelectorAll(u),c=0;c<r.length;c++)try{var o=r[c],a=o.parentNode,i=o.getAttribute(f);if(i){var l=n(i,0),d=document.createTextNode(l);a.replaceChild(d,o)}}catch(h){e(h)}}function a(t){for(var r=t.querySelectorAll("template"),n=0;n<r.length;n++)try{i(r[n].content)}catch(c){e(c)}}function i(t){try{c(t),o(t),a(t)}catch(r){e(r)}}var l="/cdn-cgi/l/email-protection#",u=".__cf_email__",f="data-cfemail",d=document.createElement("div");i(document),function(){var e=document.currentScript||document.scripts[document.scripts.length-1];e.parentNode.removeChild(e)}()}();
        """#

    @Test func protectedLinkBecomesMailtoAndTheDecoderRemovesItself() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><a id="mail" href="/cdn-cgi/l/email-protection#ec8189ac9884898388839e999f8f808d9e89828f89c28f8381">Email</a><a id="blog" href="/blog">Blog</a></p><script id="decoder" src="/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js"></script>"#,
            rules: ""
        )
        page.frame.setURL(WebURL("https://theodorusclarence.com/"))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        let decoderScript: ElementRef = try #require(page.firstElement(id: "decoder"))

        page.frame.js.run(script: "email-decode", code: decoder, element: decoderScript.id)

        let mail: ElementRef = try #require(page.firstElement(id: "mail"))
        let blog: ElementRef = try #require(page.firstElement(id: "blog"))
        #expect(mail.attributes["href"] == "mailto:me@theodorusclarence.com")
        #expect(blog.attributes["href"] == "/blog")
        #expect(page.firstElement(id: "decoder") == nil)
    }
}
