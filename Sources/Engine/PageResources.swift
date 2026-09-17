typealias ResourceURL = (index: Int, url: WebURL, ref: WebURL?)

struct PageResources {
    let styleURLs: [ResourceURL]
    let scriptURLs: [ResourceURL]
}
