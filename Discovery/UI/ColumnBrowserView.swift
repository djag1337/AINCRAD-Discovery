import AppKit

/// macOS-style columns: picking a folder opens its contents in the next column to the right.
final class ColumnBrowserView: NSView, FileTableDelegate {
    weak var delegate: FileTableDelegate?
    var showHidden = false
    private let scroll = NSScrollView()
    private let content = NSView()
    private var columns: [FileTableView] = []
    private var activeIndex = 0
    private let columnWidth: CGFloat = 280

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var active: FileTableView? { columns.indices.contains(activeIndex) ? columns[activeIndex] : columns.first }
    var selectedItems: [FileItem] { active?.selectedItems ?? [] }
    var activeFolder: URL? { active?.folder }
    var rootCount: Int { columns.first?.items.count ?? 0 }

    func focus() { active?.focus() }

    /// Starts over with `folder` as the only column.
    func setRoot(_ folder: URL, select: URL? = nil) {
        truncate(after: -1)
        activeIndex = 0
        let c = addColumn(folder)
        if let select { c.select(select) }
    }

    /// Re-lists every open column (after a rename, trash or drop), keeping selections.
    func reloadAll(select: URL? = nil) {
        for c in columns { if let f = c.folder { c.setItems(FileStore.contents(of: f, sort: .name, showHidden: showHidden), folder: f) } }
        if let select, let c = columns.first(where: { $0.folder == select.deletingLastPathComponent() }) { c.select(select) }
    }

    func beginRename(_ url: URL) {
        columns.first(where: { $0.folder == url.deletingLastPathComponent() })?.beginRename(url)
    }

    func refreshTheme() { columns.forEach { $0.refreshTheme() } }

    @discardableResult
    private func addColumn(_ folder: URL) -> FileTableView {
        let c = FileTableView(style: .column)
        c.delegate = self
        content.addSubview(c)
        columns.append(c)
        c.setItems(FileStore.contents(of: folder, sort: .name, showHidden: showHidden), folder: folder)
        relayout()
        return c
    }

    private func truncate(after index: Int) {
        while columns.count > index + 1 { columns.removeLast().removeFromSuperview() }
        relayout()
    }

    private func relayout() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let h = scroll.contentSize.height
        var x: CGFloat = 0
        for c in columns {
            c.frame = NSRect(x: x, y: 0, width: columnWidth, height: h)
            x += columnWidth + 6
        }
        content.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, x), height: h)
        if let last = columns.last { content.scrollToVisible(last.frame) }
    }

    // MARK: FileTableDelegate

    func fileTable(_ t: FileTableView, didSelect items: [FileItem]) {
        guard let i = columns.firstIndex(where: { $0 === t }) else { return }
        activeIndex = i
        truncate(after: i)
        if items.count == 1, let it = items.first, it.isDirectory, !it.isPackage { addColumn(it.url) }
        delegate?.fileTable(t, didSelect: items)
    }

    func fileTable(_ t: FileTableView, perform command: FileCommand) {
        guard let i = columns.firstIndex(where: { $0 === t }) else { return }
        switch command {
        case .moveLeft:
            if i > 0 { columns[i - 1].focus() }
        case .moveRight:
            if i + 1 < columns.count, !columns[i + 1].items.isEmpty {
                columns[i + 1].focus()
                columns[i + 1].table.selectRowIndexes([0], byExtendingSelection: false)
            }
        default: delegate?.fileTable(t, perform: command)
        }
    }

    func fileTable(_ t: FileTableView, menuFor items: [FileItem]) -> NSMenu? { delegate?.fileTable(t, menuFor: items) }
    func fileTable(_ t: FileTableView, drop urls: [URL], into folder: URL, copy: Bool) { delegate?.fileTable(t, drop: urls, into: folder, copy: copy) }
    func fileTable(_ t: FileTableView, rename item: FileItem, to name: String) { delegate?.fileTable(t, rename: item, to: name) }
}
