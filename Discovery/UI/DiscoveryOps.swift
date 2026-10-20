import Foundation

/// The only place the UI touches FileOps, so a change to its signatures is a one-file fix.
enum DiscoveryOps {
    static func rename(_ url: URL, to name: String) throws -> URL { try FileOps.rename(url, to: name) }
    static func newFolder(in folder: URL, named name: String) throws -> URL { try FileOps.newFolder(in: folder, named: name) }
    static func trash(_ urls: [URL]) async throws { try await FileOps.moveToTrash(urls) }
    static func copy(_ urls: [URL], into folder: URL) throws { try FileOps.copy(urls, into: folder) }
    static func move(_ urls: [URL], into folder: URL) throws { try FileOps.move(urls, into: folder) }
}
