import Foundation

/// One entry in a folder. Shared contract between the model (FileStore) and the UI: do not change its shape
/// without updating both. Values are read once when a folder is listed.
struct FileItem: Equatable, Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool          // .app bundles and similar: shown as items, not folders you walk into
    let isHidden: Bool
    let size: Int64?             // nil for folders and when unknown
    let modified: Date?
    let kind: String             // localized kind, e.g. "PDF document", "Folder"

    var id: URL { url }
}

/// How a folder's entries are ordered.
enum FileSort: String, CaseIterable {
    case name, modified, size, kind
}
