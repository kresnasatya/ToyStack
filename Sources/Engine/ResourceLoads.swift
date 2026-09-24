typealias ResourceLoad = (index: Int, url: WebURL, ref: WebURL?)

struct ResourceLoads {
    let styleURLs: [ResourceLoad]
    let scriptURLs: [ResourceLoad]
}
