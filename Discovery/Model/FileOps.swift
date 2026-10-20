import AppKit

struct FileOpError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// File changes. Nothing here overwrites an existing item or deletes permanently.
enum FileOps {
    private static let fm = FileManager.default

    static func rename(_ url: URL, to newName: String) throws -> URL {
        let name = try validated(newName)
        if name == url.lastPathComponent { return url }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) { throw FileOpError("An item named \"\(name)\" already exists here.") }
        do { try fm.moveItem(at: url, to: dest) } catch { throw FileOpError("Couldn't rename: \(error.localizedDescription)") }
        return dest
    }

    static func newFolder(in folder: URL, named: String = "untitled folder") throws -> URL {
        let base = try validated(named)
        let dest = unique(base, in: folder)
        do { try fm.createDirectory(at: dest, withIntermediateDirectories: false) }
        catch { throw FileOpError("Couldn't create the folder: \(error.localizedDescription)") }
        return dest
    }

    static func moveToTrash(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle(urls) { _, error in
                if let error { c.resume(throwing: FileOpError("Couldn't move to Trash: \(error.localizedDescription)")) }
                else { c.resume() }
            }
        }
    }

    static func copy(_ urls: [URL], into folder: URL) throws {
        try transfer(urls, into: folder, verb: "copy") { try fm.copyItem(at: $0, to: $1) }
    }

    static func move(_ urls: [URL], into folder: URL) throws {
        try transfer(urls, into: folder, verb: "move") { try fm.moveItem(at: $0, to: $1) }
    }

    private static func transfer(_ urls: [URL], into folder: URL, verb: String, _ op: (URL, URL) throws -> Void) throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw FileOpError("The destination folder doesn't exist.")
        }
        let dstPath = folder.resolvingSymlinksInPath().path
        for url in urls {
            let src = url.resolvingSymlinksInPath().path
            if dstPath == src || dstPath.hasPrefix(src + "/") { throw FileOpError("Can't \(verb) \"\(url.lastPathComponent)\" into itself.") }
        }
        for url in urls {
            // Moving into the folder it is already in is a no-op, not a duplicate.
            if verb == "move", url.deletingLastPathComponent().resolvingSymlinksInPath().path == dstPath { continue }
            do { try op(url, unique(url.lastPathComponent, in: folder)) }
            catch { throw FileOpError("Couldn't \(verb) \"\(url.lastPathComponent)\": \(error.localizedDescription)") }
        }
    }

    private static func validated(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { throw FileOpError("The name can't be empty.") }
        if n == "." || n == ".." { throw FileOpError("\"\(n)\" isn't a valid name.") }
        if n.contains("/") { throw FileOpError("Names can't contain \"/\".") }
        return n
    }

    // "name", "name 2", "name 3"; the number goes before the extension.
    private static func unique(_ name: String, in folder: URL) -> URL {
        var dest = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: dest.path) else { return dest }
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        var i = 2
        repeat {
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)")
            i += 1
        } while fm.fileExists(atPath: dest.path)
        return dest
    }
}
