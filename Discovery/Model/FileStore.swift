import Foundation

/// Lists folders. Owned by the model piece; the UI calls only these signatures.
/// Contract:
/// - `contents(of:sort:showHidden:)` is synchronous and returns folders first, then files, sorted by `sort`.
/// - It never throws to the UI: an unreadable folder returns [] and logs the reason.
enum FileStore {
    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
                                                 .contentModificationDateKey, .localizedTypeDescriptionKey]

    static func contents(of folder: URL, sort: FileSort = .name, showHidden: Bool = false) -> [FileItem] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        } catch {
            fputs("FileStore: cannot list \(folder.path): \(error.localizedDescription)\n", stderr)
            return []
        }
        let items: [FileItem] = urls.compactMap { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let hidden = (v?.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
            if hidden && !showHidden { return nil }
            let isDir = v?.isDirectory ?? false
            return FileItem(url: url, name: url.lastPathComponent, isDirectory: isDir, isPackage: v?.isPackage ?? false,
                            isHidden: hidden, size: isDir ? nil : v?.fileSize.map(Int64.init), modified: v?.contentModificationDate,
                            kind: v?.localizedTypeDescription ?? (isDir ? "Folder" : "Document"))
        }
        return items.sorted { a, b in
            // Packages behave like files, so only plain folders group first.
            let fa = a.isDirectory && !a.isPackage, fb = b.isDirectory && !b.isPackage
            if fa != fb { return fa }
            return ordered(a, b, sort)
        }
    }

    private static func byName(_ a: FileItem, _ b: FileItem) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    private static func ordered(_ a: FileItem, _ b: FileItem, _ sort: FileSort) -> Bool {
        switch sort {
        case .name: return byName(a, b)
        case .modified:
            if a.modified != b.modified { return (a.modified ?? .distantPast) > (b.modified ?? .distantPast) }
            return byName(a, b)
        case .size:
            if a.size != b.size { return (a.size ?? -1) > (b.size ?? -1) }
            return byName(a, b)
        case .kind:
            let c = a.kind.localizedStandardCompare(b.kind)
            return c == .orderedSame ? byName(a, b) : c == .orderedAscending
        }
    }
}
