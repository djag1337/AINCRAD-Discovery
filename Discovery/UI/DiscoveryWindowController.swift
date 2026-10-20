import AppKit

/// Routes ⌘ shortcuts and F2 before the responder chain, so they work wherever focus is.
final class DiscoveryWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class DiscoveryWindowController: NSWindowController, NSWindowDelegate, NSSearchFieldDelegate, FileTableDelegate {
    private enum ViewMode: String { case list, columns }
    private struct Favourite { let name: String; let symbol: String; let url: URL }

    private(set) var folder: URL
    /// Called when the window closes, so the app can forget it.
    var onClose: (() -> Void)?
    private var mode: ViewMode
    private var back: [URL] = [], forward: [URL] = []
    private var searching = false
    private var searchGeneration = 0
    private var search: FileSearch?
    private var searchTimer: Timer?
    private var showHidden: Bool
    private let preview = QuickLookPreview()

    private let list = FileTableView(style: .list)
    private let columns = ColumnBrowserView()
    private let pathBar = PathBarView()
    private let searchField = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private var backButton: DCircleButton!, forwardButton: DCircleButton!, upButton: DCircleButton!
    private var listButton: DCircleButton!, columnsButton: DCircleButton!, infoButton: DCircleButton!
    private var favouriteButtons: [DCircleButton] = []
    private let topBar = NSView()
    private var topBarTop: NSLayoutConstraint!, sidebarTop: NSLayoutConstraint!, containerTop: NSLayoutConstraint!
    private var topBarShown = false
    private var moveMonitors: [Any] = []
    private var hideWork: DispatchWorkItem?
    private var barHeight: CGFloat { 8 + AINCRADTheme.buttonSize + 12 + 36 + 6 }
    private var sidebarCollapsedWidth: CGFloat { AINCRADTheme.buttonSize + 12 }
    private let sidebarExpandedExtra: CGFloat = 170
    private var sidebarStack: NSStackView!
    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarBackdrop: NSView!
    private var sidebarLabels: [NSTextField] = []
    private var sidebarExpanded = false
    private var sidebarHideWork: DispatchWorkItem?
    private var containerLeading: NSLayoutConstraint!
    private let closeLight = DCircleButton(factor: 0.72)
    private let minLight = DCircleButton(factor: 0.72)
    private let zoomLight = DCircleButton(factor: 0.72)
    private var lightGroup: [NSView] = []
    private lazy var favourites: [Favourite] = {
        let h = FileManager.default.homeDirectoryForCurrentUser
        return [
            Favourite(name: "Home", symbol: "house", url: h),
            Favourite(name: "Desktop", symbol: "menubar.dock.rectangle", url: h.appendingPathComponent("Desktop")),
            Favourite(name: "Documents", symbol: "doc", url: h.appendingPathComponent("Documents")),
            Favourite(name: "Downloads", symbol: "arrow.down.circle", url: h.appendingPathComponent("Downloads")),
            Favourite(name: "Applications", symbol: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications")),
            Favourite(name: "AINCRAD Notes", symbol: "note.text", url: h.appendingPathComponent("AINCRAD Notes")),
            Favourite(name: "Trash", symbol: "trash", url: h.appendingPathComponent(".Trash")),
        ]
    }()

    init(startingAt url: URL) {
        folder = url.standardizedFileURL
        switch DiscoveryPrefs.startView {
        case .list: mode = .list
        case .columns: mode = .columns
        case .last: mode = ViewMode(rawValue: DiscoveryPrefs.lastView ?? "") ?? .list
        }
        showHidden = DiscoveryPrefs.showHidden
        // About 85% of the screen, like the browser's default, but never smaller than the minimum.
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = NSSize(width: max(860, min(1600, screen.width * 0.85)), height: max(580, min(1000, screen.height * 0.85)))
        let w = DiscoveryWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: w)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.minSize = NSSize(width: 760, height: 560)
        w.titlebarAppearsTransparent = true
        w.center()
        w.onKey = { [weak self] e in self?.handleKey(e) ?? false }
        preview.forwardKey = { [weak self] e in self?.activeTable?.keyDown(with: e) }
        buildUI()
        applyTheme()
        applyEdgePrefs()
        installMouseMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: DiscoveryPrefs.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: NSApplication.didBecomeActiveNotification, object: nil)
        visit(url, record: false)
    }

    // MARK: top bar reveal

    private func installMouseMonitor() {
        window?.acceptsMouseMovedEvents = true
        // Local covers the pointer over this window; global covers it over other apps.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.pointerMoved(); return event
        }) { moveMonitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            DispatchQueue.main.async { self?.pointerMoved() }
        }) { moveMonitors.append(global) }
    }

    /// True while the pointer is in the strip along the top edge that brings the bar out.
    private func pointerInTopZone() -> Bool {
        guard let window, window.isVisible else { return false }
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        guard mouse.x >= frame.minX, mouse.x <= frame.maxX else { return false }
        let fromTop = frame.maxY - mouse.y
        return fromTop >= -4 && fromTop <= (topBarShown ? barHeight + 18 : 24)
    }

    private var keepTopBar: Bool { (window?.firstResponder as? NSTextView)?.isFieldEditor == true || searching }

    /// True while the pointer is over the sidebar (expanded or not), with a little slack around it.
    private func pointerInSidebar() -> Bool {
        guard let window, let sidebarStack else { return false }
        let frame = sidebarStack.convert(sidebarStack.bounds, to: nil)
        let mouse = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return frame.insetBy(dx: -8, dy: -8).contains(mouse)
    }

    /// Pinned: the sidebar shows names and the toolbar stays up. Otherwise both reveal from their edges.
    /// Pinned, the list makes room for the open sidebar; hover-expanded, it stays put under the sidebar.
    private func applyEdgePrefs() {
        let pinned = DiscoveryPrefs.pinEdges
        let animated = isWindowLoaded && window?.isVisible == true
        setSidebar(expanded: pinned)
        setTopBar(shown: pinned, animated: animated)
        let leading = 18 + (pinned ? sidebarCollapsedWidth + sidebarExpandedExtra : sidebarCollapsedWidth) + 18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.2 : 0
            containerLeading.animator().constant = leading
        }
    }

    @objc private func prefsChanged() {
        applyWindowChrome()
        applyEdgePrefs()
    }

    /// AINCRAD stoplights replace the system buttons when the toggle is on. The window background stays solid.
    private func applyWindowChrome() {
        guard let window else { return }
        let custom = DiscoveryPrefs.browserChrome
        window.titlebarAppearsTransparent = true
        window.titleVisibility = custom ? .hidden : .visible
        if custom { window.styleMask.insert(.fullSizeContentView) } else { window.styleMask.remove(.fullSizeContentView) }
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = custom }
        window.isOpaque = true
        window.backgroundColor = AINCRADTheme.discoveryBackground
        window.hasShadow = true
        lightGroup.forEach { $0.isHidden = !custom }
    }

    private func pointerMoved() {
        guard !DiscoveryPrefs.pinEdges else { return }
        if pointerInSidebar() {
            sidebarHideWork?.cancel(); sidebarHideWork = nil
            setSidebar(expanded: true)
        } else if sidebarExpanded, sidebarHideWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.sidebarHideWork = nil
                if !self.pointerInSidebar() { self.setSidebar(expanded: false) }
            }
            sidebarHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        if pointerInTopZone() {
            hideWork?.cancel(); hideWork = nil
            setTopBar(shown: true)
        } else if topBarShown, !keepTopBar {
            scheduleTopBarHide()
        }
    }

    private func scheduleTopBarHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWork = nil
            if !self.keepTopBar, !self.pointerInTopZone() { self.setTopBar(shown: false) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Names slide in beside the circles and the sidebar widens over the list; the list itself never moves.
    private func setSidebar(expanded: Bool) {
        guard expanded != sidebarExpanded else { return }
        sidebarExpanded = expanded
        if expanded { sidebarLabels.forEach { $0.isHidden = false } }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sidebarWidth.animator().constant = expanded ? sidebarCollapsedWidth + sidebarExpandedExtra : sidebarCollapsedWidth
            sidebarLabels.forEach { $0.animator().alphaValue = expanded ? 1 : 0 }
            sidebarBackdrop.animator().alphaValue = expanded ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.sidebarExpanded else { return }
            self.sidebarLabels.forEach { $0.isHidden = true }
        })
    }

    /// The bar and the content below it move together; the file list fills the space the bar leaves.
    private func setTopBar(shown: Bool, animated: Bool = true) {
        guard shown != topBarShown || !animated else { return }
        topBarShown = shown
        let bar = barHeight
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            topBarTop.animator().constant = shown ? 0 : -bar - 10
            sidebarTop.animator().constant = shown ? bar + 8 : 14
            containerTop.animator().constant = shown ? bar + 6 : 12
            topBar.animator().alphaValue = shown ? 1 : 0
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Opens a folder in this window (a file path opens its folder with the file selected).
    func navigate(to url: URL) { visit(url, record: true) }

    // MARK: building the window

    private func circle(_ symbol: String, _ tip: String, _ action: Selector, factor: CGFloat = 1) -> DCircleButton {
        let b = DCircleButton(factor: factor)
        b.image = AINCRADTheme.glyph(symbol, tip)
        b.toolTip = tip
        b.target = self; b.action = action
        return b
    }

    private func spacer(width: CGFloat? = nil) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        if let width { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
        else { v.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal) }
        return v
    }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        backButton = circle("chevron.left", "Back (⌘[)", #selector(goBack))
        forwardButton = circle("chevron.right", "Forward (⌘])", #selector(goForward))
        upButton = circle("arrow.up", "Enclosing folder (⌘↑)", #selector(goUp))
        listButton = circle("list.bullet", "List view (⌘1)", #selector(showList))
        columnsButton = circle("rectangle.split.3x1", "Column view (⌘2)", #selector(showColumns))
        let searchButton = circle("magnifyingglass", "Search (⌘F)", #selector(focusSearch))
        let newFolderButton = circle("folder.badge.plus", "New folder (⇧⌘N)", #selector(newFolder))
        let trashButton = circle("trash", "Move to trash (⌘⌫)", #selector(trashSelection))
        infoButton = circle("info.circle", "Info (⌘I)", #selector(showInfo))

        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.target = self; searchField.action = #selector(searchAction)
        searchField.font = AINCRADTheme.bodyFont(size: 16)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // The AINCRAD circle buttons, with the window colours on hover, the way the browser draws its own.
        let lightButtons: [(DCircleButton, String, String, Selector, NSColor)] = [
            (closeLight, "xmark", "Close Window", #selector(closeWindowAction), AINCRADTheme.windowClose),
            (minLight, "minus", "Minimise", #selector(minimizeWindowAction), AINCRADTheme.windowMinimize),
            (zoomLight, "arrow.up.left.and.arrow.down.right", "Zoom", #selector(zoomWindowAction), AINCRADTheme.windowZoom),
        ]
        for (button, symbol, help, action, color) in lightButtons {
            button.image = AINCRADTheme.glyph(symbol, help)
            button.toolTip = help
            button.target = self; button.action = action
            button.hoverColor = color
        }
        let lights = NSStackView(views: [closeLight, minLight, zoomLight])
        lights.orientation = .horizontal
        lights.spacing = 8
        lights.alignment = .centerY
        let lightSpace = spacer(width: 14)
        lightGroup = [lights, lightSpace]

        let toolbar = NSStackView(views: [lights, lightSpace, backButton, forwardButton, upButton, spacer(width: 8), listButton, columnsButton, spacer(width: 8), newFolderButton, trashButton, infoButton, spacer(), searchButton, searchField])
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        toolbar.alignment = .centerY
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        pathBar.onSelect = { [weak self] url in self?.visit(url, record: true) }
        pathBar.translatesAutoresizingMaskIntoConstraints = false

        favouriteButtons = favourites.map { f in
            let b = circle(f.symbol, f.name, #selector(favouriteClicked(_:)))
            return b
        }
        // Each favourite is a circle with its name beside it; the names show while the pointer is over the sidebar.
        sidebarLabels = favourites.map { f in
            let l = NSTextField(labelWithString: f.name)
            l.font = AINCRADTheme.bodyFont(size: 15)
            l.textColor = AINCRADTheme.panelText
            l.lineBreakMode = .byTruncatingTail
            l.alphaValue = 0
            l.isHidden = true
            return l
        }
        let rows: [NSView] = favouriteButtons.indices.map { i in
            let row = NSStackView(views: [favouriteButtons[i], sidebarLabels[i]])
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        var sidebarViews: [NSView] = Array(rows.dropLast())
        let flex = NSView(); flex.translatesAutoresizingMaskIntoConstraints = false
        flex.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        sidebarViews += [flex, rows[rows.count - 1]]
        let sidebar = NSStackView(views: sidebarViews)
        sidebar.orientation = .vertical
        sidebar.spacing = 12
        sidebar.alignment = .leading
        sidebar.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack = sidebar
        // Collapsed it is a narrow column of circles; without a fixed width the stack takes the whole window.
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: sidebarCollapsedWidth)
        sidebarWidth.isActive = true
        sidebar.setContentHuggingPriority(.required, for: .horizontal)
        sidebar.setContentCompressionResistancePriority(.required, for: .horizontal)

        // A panel behind the expanded sidebar so it reads as floating over the list.
        let backdrop = NSView()
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 16
        backdrop.layer?.borderWidth = 1
        backdrop.alphaValue = 0
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        sidebarBackdrop = backdrop

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        for v in [list, columns] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: container.leadingAnchor), v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                v.topAnchor.constraint(equalTo: container.topAnchor), v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        list.delegate = self
        columns.delegate = self

        status.translatesAutoresizingMaskIntoConstraints = false
        status.lineBreakMode = .byTruncatingTail

        // The toolbar and path bar form a strip that slides out of the top edge and back in.
        topBar.translatesAutoresizingMaskIntoConstraints = false
        [toolbar, pathBar].forEach(topBar.addSubview)
        // Order matters: the expanded sidebar is drawn over the list.
        [topBar, container, backdrop, sidebar, status].forEach(root.addSubview)
        topBarTop = topBar.topAnchor.constraint(equalTo: root.topAnchor, constant: -barHeight)
        sidebarTop = sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 14)
        containerTop = container.topAnchor.constraint(equalTo: root.topAnchor, constant: 12)
        containerLeading = container.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18 + sidebarCollapsedWidth + 18)
        NSLayoutConstraint.activate([
            topBarTop,
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 18),
            toolbar.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -18),
            pathBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            pathBar.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 18),
            pathBar.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -18),
            pathBar.heightAnchor.constraint(equalToConstant: 36),
            topBar.bottomAnchor.constraint(equalTo: pathBar.bottomAnchor, constant: 6),
            sidebarTop,
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            sidebar.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            backdrop.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: -8),
            backdrop.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8),
            backdrop.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: -8),
            backdrop.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: 8),
            containerTop,
            // Anchored to the collapsed width, so the list does not move when the sidebar expands.
            containerLeading,
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            container.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
    }

    @objc private func applyTheme() {
        let t = AINCRADTheme.self
        window?.appearance = NSAppearance(named: t.isDark ? .darkAqua : .aqua)
        applyWindowChrome()
        sidebarBackdrop?.layer?.backgroundColor = t.discoveryBackground.cgColor
        sidebarBackdrop?.layer?.borderColor = t.circleBorder.cgColor
        sidebarLabels.forEach { $0.font = t.bodyFont(size: 15); $0.textColor = t.panelText }
        status.font = t.bodyFont(size: 14)
        status.textColor = t.discoveryDim
        searchField.font = t.bodyFont(size: 16)
        list.refreshTheme()
        columns.refreshTheme()
        pathBar.refreshTheme()
        ([backButton, forwardButton, upButton, listButton, columnsButton, infoButton] + favouriteButtons).forEach { $0?.updateSize(); $0?.restyle() }
    }

    // MARK: navigation

    private func visit(_ url: URL, record: Bool) {
        var target = url.standardizedFileURL
        var pick: URL?
        let v = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if v?.isDirectory != true || v?.isPackage == true { pick = target; target = target.deletingLastPathComponent() }
        endSearch(restore: false)
        if record, target != folder { back.append(folder); forward.removeAll() }
        folder = target
        load(select: pick)
        updateChrome()
        focusContent()
    }

    private func load(select: URL? = nil) {
        DiscoveryPrefs.lastFolder = folder
        applyMode()
        guard !searching else { return }
        if mode == .list {
            list.setItems(FileStore.contents(of: folder, sort: .name, showHidden: showHidden), folder: folder, select: select.map { [$0] } ?? [])
        } else {
            columns.showHidden = showHidden
            columns.setRoot(folder, select: select)
        }
    }

    private func refresh(select: URL? = nil) {
        if searching { let q = searchField.stringValue; startSearch(q); return }
        if mode == .list { list.setItems(FileStore.contents(of: folder, sort: .name, showHidden: showHidden), folder: folder, select: select.map { [$0] } ?? []) }
        else { columns.showHidden = showHidden; columns.reloadAll(select: select) }
        updateChrome()
    }

    private func applyMode() {
        list.isHidden = !(mode == .list || searching)
        columns.isHidden = !(mode == .columns && !searching)
        listButton.isSelected = mode == .list
        columnsButton.isSelected = mode == .columns
    }

    private func updateChrome() {
        let name = FileManager.default.displayName(atPath: folder.path)
        window?.title = searching ? "Search in \(name)" : name
        window?.representedURL = folder
        backButton.isEnabled = !back.isEmpty
        forwardButton.isEnabled = !forward.isEmpty
        upButton.isEnabled = folder.path != "/"
        var crumbs: [PathBarView.Crumb] = []
        var u = folder
        while true {
            crumbs.insert((FileManager.default.displayName(atPath: u.path), u), at: 0)
            if u.path == "/" { break }
            u = u.deletingLastPathComponent()
        }
        if searching { crumbs.append(("Results", nil)) }
        pathBar.set(crumbs)
        for (i, f) in favourites.enumerated() {
            favouriteButtons[i].isSelected = !searching && f.url.standardizedFileURL == folder
            favouriteButtons[i].isEnabled = FileManager.default.fileExists(atPath: f.url.path)
        }
        updateStatus()
    }

    private func updateStatus() {
        let total = searching || mode == .list ? list.items.count : (columns.active?.items.count ?? columns.rootCount)
        let n = selection.count
        let items = "\(total) \(total == 1 ? "item" : "items")"
        status.stringValue = n > 0 ? "\(n) selected, \(items)" : items
    }

    private var activeTable: NSTableView? { searching || mode == .list ? list.table : columns.active?.table }
    private var selection: [FileItem] { searching || mode == .list ? list.selectedItems : columns.selectedItems }
    private var targetFolder: URL { (!searching && mode == .columns ? columns.activeFolder : nil) ?? folder }

    private func focusContent() {
        if searching || mode == .list { list.focus() } else { columns.focus() }
    }

    @objc private func closeWindowAction() { window?.performClose(nil) }
    @objc private func minimizeWindowAction() { window?.miniaturize(nil) }
    @objc private func zoomWindowAction() { window?.performZoom(nil) }

    @objc func goBack() {
        guard let u = back.popLast() else { return }
        forward.append(folder)
        move(to: u)
    }

    @objc func goForward() {
        guard let u = forward.popLast() else { return }
        back.append(folder)
        move(to: u)
    }

    private func move(to u: URL) {
        endSearch(restore: false)
        folder = u
        load()
        updateChrome()
        focusContent()
    }

    @objc func goUp() {
        guard folder.path != "/" else { return }
        let child = folder
        visit(folder.deletingLastPathComponent(), record: true)
        if mode == .list { list.select(child) }
    }

    @objc private func favouriteClicked(_ sender: DCircleButton) {
        guard let i = favouriteButtons.firstIndex(where: { $0 === sender }) else { return }
        visit(favourites[i].url, record: true)
    }

    /// Go menu entries for the standard folders (the URL rides on the menu item).
    @objc func goToFavourite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        visit(url, record: true)
    }

    @objc func goToFolder() {
        guard let window else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "~/Documents"
        let alert = NSAlert()
        alert.messageText = "Go to Folder"
        alert.informativeText = "Type a path, such as ~/Documents."
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let path = (field.stringValue as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                let missing = NSAlert()
                missing.messageText = "There is no item at “\(field.stringValue)”."
                missing.beginSheetModal(for: window)
                return
            }
            self.visit(URL(fileURLWithPath: path), record: true)
        }
    }

    @objc func toggleHiddenFiles() {
        showHidden.toggle()
        refresh()
    }

    @objc func showList() { setMode(.list) }
    @objc func showColumns() { setMode(.columns) }

    private func setMode(_ m: ViewMode) {
        mode = m
        DiscoveryPrefs.lastView = m.rawValue
        let pick = selection.first?.url
        if searching { applyMode(); return }
        load(select: pick)
        updateChrome()
        focusContent()
    }

    // MARK: search

    @objc func focusSearch() { setTopBar(shown: true); window?.makeFirstResponder(searchField) }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField === searchField else { return }
        searchTimer?.invalidate()
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { endSearch(restore: true); return }
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in self?.startSearch(q) }
    }

    @objc private func searchAction() {
        if searchField.stringValue.isEmpty { endSearch(restore: true) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard control === searchField else { return false }
        switch sel {
        case #selector(NSResponder.cancelOperation(_:)):
            clearSearchField()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)):
            focusContent()
            if let t = activeTable, t.selectedRow < 0, t.numberOfRows > 0 { t.selectRowIndexes([0], byExtendingSelection: false) }
            return true
        default: return false
        }
    }

    private func startSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        search?.stop()
        searchGeneration += 1
        let gen = searchGeneration
        searching = true
        applyMode()
        list.setItems([], folder: nil)
        let s = FileSearch(query: q, scope: folder)
        s.onResults = { [weak self] results in
            DispatchQueue.main.async {
                guard let self, gen == self.searchGeneration, self.searching else { return }
                self.list.setItems(results, folder: nil)
                self.updateStatus()
            }
        }
        search = s
        s.start()
        updateChrome()
    }

    private func endSearch(restore: Bool) {
        searchTimer?.invalidate()
        search?.stop(); search = nil
        searchGeneration += 1
        guard searching else { return }
        searching = false
        searchField.stringValue = ""
        if restore { load(); focusContent() } else { applyMode() }
        updateChrome()
    }

    private func clearSearchField() {
        guard searching || !searchField.stringValue.isEmpty else { return }
        searchField.stringValue = ""
        if searching { endSearch(restore: true) } else { searchTimer?.invalidate(); focusContent() }
    }

    // MARK: keyboard

    private func handleKey(_ e: NSEvent) -> Bool {
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let editing = (window?.firstResponder as? NSTextView)?.isFieldEditor == true
        if m == .command {
            switch (e.keyCode, ch) {
            case (126, _): goUp()
            case (51, _) where !editing: trashSelection()
            case (_, "["): goBack()
            case (_, "]"): goForward()
            case (_, "f"): focusSearch()
            case (_, "i"): showInfo()
            case (_, "1"): showList()
            case (_, "2"): showColumns()
            default: return false
            }
            return true
        }
        if m == [.command, .shift] {
            switch ch {
            case "n": newFolder()
            case ".": showHidden.toggle(); refresh()
            default: return false
            }
            return true
        }
        if m.isEmpty, e.keyCode == 120, !editing { renameSelection(); return true }
        return false
    }

    // MARK: FileTableDelegate

    func fileTable(_ t: FileTableView, didSelect items: [FileItem]) {
        updateStatus()
        preview.update(urls: selection.map(\.url))
    }

    func fileTable(_ t: FileTableView, perform command: FileCommand) {
        switch command {
        case .open: selection.forEach(open)
        case .preview: preview.toggle(urls: selection.map(\.url))
        case .rename: renameSelection()
        case .trash: trashSelection()
        case .escape: clearSearchField()
        case .moveLeft, .moveRight: break
        }
    }

    func fileTable(_ t: FileTableView, menuFor items: [FileItem]) -> NSMenu? {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self; i.isEnabled = enabled
            m.addItem(i)
        }
        if items.isEmpty { add("New folder", #selector(newFolder), enabled: !searching); return m }
        add("Open", #selector(openSelection))
        add("Show in Finder", #selector(showInFinder))
        m.addItem(.separator())
        add("Rename", #selector(renameSelection), enabled: items.count == 1)
        add("Move to trash", #selector(trashSelection))
        m.addItem(.separator())
        add("Copy path", #selector(copyPath))
        return m
    }

    func fileTable(_ t: FileTableView, drop urls: [URL], into dest: URL, copy: Bool) {
        let dest = dest.standardizedFileURL
        do {
            let moving = urls.filter { $0.deletingLastPathComponent().standardizedFileURL != dest && $0.standardizedFileURL != dest }
            if copy { try DiscoveryOps.copy(moving, into: dest) } else { try DiscoveryOps.move(moving, into: dest) }
        } catch { fail(error) }
        refresh()
    }

    func fileTable(_ t: FileTableView, rename item: FileItem, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), clean != item.name else { return }
        do { refresh(select: try DiscoveryOps.rename(item.url, to: clean)) } catch { fail(error) }
    }

    // MARK: actions

    private func open(_ item: FileItem) {
        if item.isDirectory && !item.isPackage { visit(item.url, record: true) }
        else { NSWorkspace.shared.open(item.url) }
    }

    @objc private func openSelection() { selection.forEach(open) }

    @objc private func showInFinder() {
        let urls = selection.map(\.url)
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [folder] : urls)
    }

    @objc private func copyPath() {
        let paths = selection.map(\.url.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    @objc private func renameSelection() {
        guard selection.count == 1, let it = selection.first else { return }
        if searching || mode == .list { list.beginRename(it.url) } else { columns.beginRename(it.url) }
    }

    @objc func trashSelection() {
        let items = selection
        guard !items.isEmpty else { return }
        guard DiscoveryPrefs.confirmTrash, let window else { moveToTrash(items); return }
        let alert = NSAlert()
        alert.messageText = items.count == 1 ? "Move “\(items[0].name)” to the Trash?" : "Move \(items.count) items to the Trash?"
        alert.informativeText = "You can put them back from the Trash in Finder."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.moveToTrash(items) }
        }
    }

    private func moveToTrash(_ items: [FileItem]) {
        Task { @MainActor in
            do { try await DiscoveryOps.trash(items.map(\.url)) } catch { fail(error) }
            refresh()
        }
    }

    @objc func newFolder() {
        guard !searching else { return }
        let dir = targetFolder
        var name = "untitled folder", n = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) { name = "untitled folder \(n)"; n += 1 }
        do {
            let url = try DiscoveryOps.newFolder(in: dir, named: name)
            refresh(select: url)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.mode == .list { self.list.beginRename(url) } else { self.columns.beginRename(url) }
            }
        } catch { fail(error) }
    }

    @objc func showInfo() {
        let fmt = ByteCountFormatter(); fmt.countStyle = .file
        let date = DateFormatter(); date.dateStyle = .medium; date.timeStyle = .short
        var lines: [String]
        let sel = selection
        if sel.count == 1, let it = sel.first {
            lines = [it.name, "Kind: \(it.kind)"]
            if let s = it.size { lines.append("Size: \(fmt.string(fromByteCount: s))") }
            if let d = it.modified { lines.append("Modified: \(date.string(from: d))") }
            lines.append("Where: \(it.url.deletingLastPathComponent().path)")
        } else if sel.count > 1 {
            lines = ["\(sel.count) items", "Total size: \(fmt.string(fromByteCount: sel.compactMap(\.size).reduce(0, +)))"]
        } else {
            let count = searching || mode == .list ? list.items.count : columns.rootCount
            lines = [FileManager.default.displayName(atPath: folder.path), "\(count) \(count == 1 ? "item" : "items")", "Where: \(folder.path)"]
        }
        let label = NSTextField(wrappingLabelWithString: lines.joined(separator: "\n"))
        label.font = AINCRADTheme.bodyFont(size: 15)
        label.textColor = AINCRADTheme.panelText
        label.isSelectable = true
        label.preferredMaxLayoutWidth = 320
        let size = label.fittingSize
        label.frame = NSRect(x: 14, y: 12, width: 320, height: size.height)
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 348, height: size.height + 24))
        vc.view.addSubview(label)
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = vc
        pop.show(relativeTo: infoButton.bounds, of: infoButton, preferredEdge: .minY)
    }

    private func fail(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    func windowWillClose(_ notification: Notification) {
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
        NotificationCenter.default.removeObserver(self)
        hideWork?.cancel()
        sidebarHideWork?.cancel()
        endSearch(restore: false)
        preview.close()
        onClose?()
    }
}
