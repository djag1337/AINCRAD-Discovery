import Foundation

/// Spotlight filename search. Matches kMDItemDisplayName only; never reads file contents.
final class FileSearch {
    static let limit = 200
    var onResults: (([FileItem]) -> Void)?
    private let text: String
    private let scope: URL?
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    init(query: String, scope: URL?) {
        text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
    }

    deinit { stop() }

    func start() {
        guard query == nil, !text.isEmpty else { return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemDisplayNameKey, text)
        q.searchScopes = [scope?.path ?? NSMetadataQueryUserHomeScope]
        let nc = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering] {
            observers.append(nc.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in self?.publish() })
        }
        query = q
        q.start()
    }

    func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        onResults = nil
    }

    private func publish() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var seen = Set<URL>(), out: [FileItem] = []
        for case let r as NSMetadataItem in q.results {
            guard let path = r.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard seen.insert(url).inserted, let item = Self.item(url) else { continue }
            out.append(item)
            if out.count >= Self.limit { break }
        }
        onResults?(out)
    }

    private static func item(_ url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
                                         .contentModificationDateKey, .localizedTypeDescriptionKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDir = v.isDirectory ?? false
        return FileItem(url: url, name: url.lastPathComponent, isDirectory: isDir, isPackage: v.isPackage ?? false,
                        isHidden: v.isHidden ?? false, size: isDir ? nil : v.fileSize.map(Int64.init),
                        modified: v.contentModificationDate, kind: v.localizedTypeDescription ?? (isDir ? "Folder" : "Document"))
    }
}
