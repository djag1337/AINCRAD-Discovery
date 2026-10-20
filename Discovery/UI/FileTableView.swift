import AppKit

enum FileCommand { case open, preview, rename, trash, escape, moveLeft, moveRight }

protocol FileTableDelegate: AnyObject {
    func fileTable(_ t: FileTableView, didSelect items: [FileItem])
    func fileTable(_ t: FileTableView, perform command: FileCommand)
    func fileTable(_ t: FileTableView, menuFor items: [FileItem]) -> NSMenu?
    func fileTable(_ t: FileTableView, drop urls: [URL], into folder: URL, copy: Bool)
    func fileTable(_ t: FileTableView, rename item: FileItem, to name: String)
}

final class KeyTableView: NSTableView {
    var onCommand: ((FileCommand) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onFocus: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func keyDown(with e: NSEvent) {
        let plain = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty
        switch e.keyCode {
        case 36, 76: onCommand?(.open)
        case 49 where plain: onCommand?(.preview)
        case 53: onCommand?(.escape)
        case 123 where plain: onCommand?(.moveLeft)
        case 124 where plain: onCommand?(.moveRight)
        default: super.keyDown(with: e)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        window?.makeFirstResponder(self)
        if row >= 0 { if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) } }
        else { deselectAll(nil) }
        return menuProvider?()
    }
}

/// Launcher-style row: a rounded glass panel, accent when selected, accent outline on hover.
final class ItemRowView: NSTableRowView {
    private var hovering = false { didSet { needsDisplay = true } }

    override var isSelected: Bool {
        didSet {
            needsDisplay = true
            for case let c as ItemCell in subviews { c.selected = isSelected }
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}

    private var rowRect: NSRect { bounds.insetBy(dx: 3, dy: 2) }

    override func draw(_ dirtyRect: NSRect) {
        let t = AINCRADTheme.self
        let r = rowRect
        let path = NSBezierPath(roundedRect: r, xRadius: t.cornerRadius, yRadius: t.cornerRadius)
        let base = isSelected ? t.accent : (hovering ? t.hover : t.panel)
        let colors = t.shade(base).compactMap { NSColor(cgColor: $0) }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let top = NSPoint(x: r.midX, y: isFlipped ? r.minY : r.maxY), bottom = NSPoint(x: r.midX, y: isFlipped ? r.maxY : r.minY)
        NSGradient(starting: colors[0], ending: colors[1])?.draw(from: top, to: bottom, options: [])
        NSGraphicsContext.restoreGraphicsState()
        (isSelected ? t.accent : (hovering ? t.accent : t.panelBorder)).setStroke()
        path.lineWidth = t.borderWidth
        path.stroke()
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let t = AINCRADTheme.self
        let path = NSBezierPath(roundedRect: rowRect, xRadius: t.cornerRadius, yRadius: t.cornerRadius)
        t.accent.setStroke()
        path.lineWidth = max(2, t.ringWidth)
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

/// One cell: optional icon, a label, optional chevron (column browser rows that open a folder).
final class ItemCell: NSView {
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    var secondary = false { didSet { applyColors() } }
    var selected = false { didSet { applyColors() } }
    var showsIcon = false { didSet { icon.isHidden = !showsIcon; needsLayout = true } }
    var showsChevron = false { didSet { chevron.isHidden = !showsChevron; needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.isHidden = true
        chevron.image = AINCRADTheme.glyph("chevron.right")
        chevron.imageScaling = .scaleProportionallyDown
        chevron.isHidden = true
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.focusRingType = .none
        label.drawsBackground = false
        [icon, label, chevron].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func applyColors() {
        let t = AINCRADTheme.self
        label.font = t.bodyFont(size: 16, weight: .medium)
        label.textColor = selected ? t.accentText : (secondary ? t.discoveryDim : t.panelText)
        chevron.contentTintColor = selected ? t.accentText : t.discoveryDim
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 12
        if showsIcon {
            let s = min(24, h - 6)
            icon.frame = NSRect(x: x, y: ((h - s) / 2).rounded(), width: s, height: s)
            x = icon.frame.maxX + 10
        }
        var right = bounds.width - 10
        if showsChevron { chevron.frame = NSRect(x: right - 12, y: ((h - 12) / 2).rounded(), width: 12, height: 12); right -= 20 }
        let lh = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: x, y: ((h - lh) / 2).rounded(), width: max(0, right - x), height: lh)
    }

    func beginEditing(delegate: NSTextFieldDelegate, text: String) {
        label.delegate = delegate
        label.isEditable = true
        label.isSelectable = true
        label.drawsBackground = true
        label.backgroundColor = AINCRADTheme.panel.withAlphaComponent(1)
        label.textColor = AINCRADTheme.panelText
        window?.makeFirstResponder(label)
        let stem = (text as NSString).deletingPathExtension
        label.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem.isEmpty ? text : stem).utf16.count)
    }

    func endEditing() {
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        applyColors()
    }
}

final class ThemedHeaderCell: NSTableHeaderCell {
    /// 1 ascending, -1 descending, 0 not the sort column.
    var arrow = 0

    override func draw(withFrame f: NSRect, in v: NSView) {
        let t = AINCRADTheme.self
        t.panel.withAlphaComponent(1).blended(withFraction: 0.05, of: t.panelText)?.setFill()
        f.fill()
        t.panelBorder.setFill()
        NSRect(x: f.minX, y: v.isFlipped ? f.maxY - 1 : f.minY, width: f.width, height: 1).fill()
        drawInterior(withFrame: f, in: v)
    }

    override func drawInterior(withFrame f: NSRect, in v: NSView) {
        let t = AINCRADTheme.self
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        let str = NSAttributedString(string: stringValue, attributes: [.font: t.bodyFont(size: 14, weight: .semibold), .foregroundColor: arrow == 0 ? t.discoveryDim : t.accent, .paragraphStyle: para])
        let h = ceil(str.size().height)
        str.draw(with: NSRect(x: f.minX + 12, y: (f.midY - h / 2).rounded(), width: max(0, f.width - 36), height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        guard arrow != 0 else { return }
        let s: CGFloat = v.isFlipped ? 1 : -1
        let cx = f.maxX - 14, cy = f.midY, dir = CGFloat(arrow)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: cy - 3 * s * dir))
        p.line(to: NSPoint(x: cx - 4, y: cy + 2 * s * dir))
        p.line(to: NSPoint(x: cx + 4, y: cy + 2 * s * dir))
        p.close()
        t.accent.setFill()
        p.fill()
    }
}

/// A sortable list of files (or the one column of the column browser). Dumb about navigation: it reports, the controller acts.
final class FileTableView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    enum Style { case list, column }

    private static let sizeFormatter: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .file; return f }()
    private static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()

    let style: Style
    weak var delegate: FileTableDelegate?
    /// Where drops on empty space land; nil while showing search results.
    private(set) var folder: URL?
    private(set) var items: [FileItem] = []
    let table = KeyTableView()
    private let scroll = NSScrollView()
    private var sortKey: FileSort = .name
    private var ascending = true
    private var applyingSort = false
    private var editingRow = -1

    /// The table has to match the visible width, or the columns squeeze into a strip at the edge.
    override func layout() {
        super.layout()
        let width = scroll.contentSize.width
        guard width > 0 else { return }
        table.setFrameSize(NSSize(width: width, height: table.frame.height))
        // Fixed widths for the small columns; the name column takes whatever is left.
        if style == .list, table.tableColumns.count == 4 {
            table.tableColumns[1].width = 90
            table.tableColumns[2].width = 170
            table.tableColumns[3].width = 150
            table.tableColumns[0].width = max(160, width - 90 - 170 - 150 - 4)
        }
    }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.focusRingType = .none
        table.rowHeight = max(30, AINCRADTheme.itemHeight - (style == .list ? 4 : 0))
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy], forLocal: false)
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular
        table.onCommand = { [weak self] c in guard let self else { return }; self.delegate?.fileTable(self, perform: c) }
        table.menuProvider = { [weak self] in guard let self else { return nil }; return self.delegate?.fileTable(self, menuFor: self.selectedItems) }

        func column(_ id: String, _ title: String, _ width: CGFloat, min: CGFloat, align: NSTextAlignment = .left) {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.width = width; c.minWidth = min
            let h = ThemedHeaderCell(textCell: title)
            h.alignment = align
            c.headerCell = h
            if style == .list { c.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true) }
            table.addTableColumn(c)
        }
        if style == .list {
            column("name", "Name", 340, min: 160)
            column("size", "Size", 90, min: 60, align: .right)
            column("modified", "Modified", 170, min: 120)
            column("kind", "Kind", 150, min: 90)
            // layout() sets the widths from the real table width.
            table.columnAutoresizingStyle = .noColumnAutoresizing
            table.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 28))
            applyingSort = true
            table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            applyingSort = false
            updateArrows()
        } else {
            column("name", "Name", 260, min: 120)
            table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            table.headerView = nil
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var selectedItems: [FileItem] { table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil } }

    func focus() { window?.makeFirstResponder(table) }

    func refreshTheme() {
        table.rowHeight = max(30, AINCRADTheme.itemHeight - (style == .list ? 4 : 0))
        table.reloadData()
        table.headerView?.needsDisplay = true
    }

    /// Replaces the rows. Selection survives by URL; a different folder also scrolls back to the top.
    func setItems(_ new: [FileItem], folder: URL?, select: [URL] = []) {
        let keep = select.isEmpty ? selectedItems.map(\.url) : select
        let changedFolder = folder != self.folder
        self.folder = folder
        items = Self.sorted(new, by: sortKey, ascending: ascending)
        table.reloadData()
        if changedFolder { table.scrollRowToVisible(0) }
        let rows = IndexSet(items.indices.filter { keep.contains(items[$0].url) })
        if !rows.isEmpty {
            table.selectRowIndexes(rows, byExtendingSelection: false)
            if let first = rows.first { table.scrollRowToVisible(first) }
        }
    }

    func select(_ url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url }) else { return }
        table.selectRowIndexes([i], byExtendingSelection: false)
        table.scrollRowToVisible(i)
    }

    func beginRename(_ url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url }) else { return }
        table.selectRowIndexes([i], byExtendingSelection: false)
        table.scrollRowToVisible(i)
        guard let cell = table.view(atColumn: 0, row: i, makeIfNecessary: true) as? ItemCell else { return }
        editingRow = i
        cell.beginEditing(delegate: self, text: items[i].name)
    }

    // MARK: sorting

    static func sorted(_ items: [FileItem], by key: FileSort, ascending: Bool) -> [FileItem] {
        func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult { a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame) }
        return items.sorted { a, b in
            let ad = a.isDirectory && !a.isPackage, bd = b.isDirectory && !b.isPackage
            if ad != bd { return ad }
            var r: ComparisonResult
            switch key {
            case .name: r = a.name.localizedStandardCompare(b.name)
            case .size: r = cmp(a.size ?? -1, b.size ?? -1)
            case .modified: r = cmp(a.modified ?? .distantPast, b.modified ?? .distantPast)
            case .kind: r = a.kind.localizedStandardCompare(b.kind)
            }
            if r == .orderedSame { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !applyingSort, let d = tableView.sortDescriptors.first, let key = d.key, let k = FileSort(rawValue: key) else { return }
        sortKey = k; ascending = d.ascending
        let keep = selectedItems.map(\.url)
        items = Self.sorted(items, by: k, ascending: ascending)
        table.reloadData()
        table.selectRowIndexes(IndexSet(items.indices.filter { keep.contains(items[$0].url) }), byExtendingSelection: false)
        updateArrows()
    }

    private func updateArrows() {
        for c in table.tableColumns { (c.headerCell as? ThemedHeaderCell)?.arrow = c.identifier.rawValue == sortKey.rawValue ? (ascending ? 1 : -1) : 0 }
        table.headerView?.needsDisplay = true
    }

    // MARK: data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        return (tableView.makeView(withIdentifier: id, owner: self) as? ItemRowView) ?? { let v = ItemRowView(); v.identifier = id; return v }()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, items.indices.contains(row) else { return nil }
        let item = items[row]
        let id = NSUserInterfaceItemIdentifier("cell-" + col.identifier.rawValue)
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ItemCell) ?? { let c = ItemCell(frame: .zero); c.identifier = id; return c }()
        cell.selected = tableView.isRowSelected(row)
        let isFolder = item.isDirectory && !item.isPackage
        switch col.identifier.rawValue {
        case "name":
            cell.label.stringValue = item.name
            cell.showsIcon = true
            cell.icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
            cell.showsChevron = style == .column && isFolder
            cell.secondary = false
        case "size":
            cell.label.stringValue = item.size.map { Self.sizeFormatter.string(fromByteCount: $0) } ?? "--"
            cell.label.alignment = .right
            cell.secondary = true
        case "modified":
            cell.label.stringValue = item.modified.map { Self.dateFormatter.string(from: $0) } ?? "--"
            cell.secondary = true
        default:
            cell.label.stringValue = item.kind
            cell.secondary = true
        }
        cell.applyColors()
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { delegate?.fileTable(self, didSelect: selectedItems) }

    @objc private func doubleClicked() {
        guard table.clickedRow >= 0 else { return }
        delegate?.fileTable(self, perform: .open)
    }

    // MARK: rename

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let cell = field.superview as? ItemCell, items.indices.contains(editingRow) else { return }
        let item = items[editingRow]
        let name = field.stringValue
        editingRow = -1
        cell.endEditing()
        field.stringValue = item.name
        window?.makeFirstResponder(table)
        if name != item.name { delegate?.fileTable(self, rename: item, to: name) }
    }

    // MARK: drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        items.indices.contains(row) ? items[row].url as NSURL : nil
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        let urls = fileURLs(info)
        guard !urls.isEmpty else { return [] }
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        let canMove = info.draggingSourceOperationMask.contains(.move)
        if op == .on, items.indices.contains(row), items[row].isDirectory, !items[row].isPackage {
            let target = items[row].url
            if urls.contains(target) || urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == target }) { return [] }
            return (optionHeld || !canMove) ? .copy : .move
        }
        guard let folder, !urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == folder }) else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
        let urls = fileURLs(info)
        if op == .on, items.indices.contains(row), items[row].isDirectory, !items[row].isPackage {
            let copy = NSEvent.modifierFlags.contains(.option) || !info.draggingSourceOperationMask.contains(.move)
            delegate?.fileTable(self, drop: urls, into: items[row].url, copy: copy)
            return true
        }
        guard let folder else { return false }
        delegate?.fileTable(self, drop: urls, into: folder, copy: true)
        return true
    }
}
