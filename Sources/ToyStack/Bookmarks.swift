@MainActor
final class Bookmarks {
    private(set) var urls: [String] = []

    func contains(_ url: String) -> Bool {
        urls.contains(url)
    }

    func toggle(_ url: String) {
        if let idx = urls.firstIndex(of: url) {
            urls.remove(at: idx)
        } else {
            urls.append(url)
        }
    }
}
