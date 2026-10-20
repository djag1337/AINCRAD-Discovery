import AppKit

/// Settings (⌘,): how Discovery starts and how its bars behave. Each choice is saved as soon as it changes.
final class DiscoverySettingsController: NSWindowController {
    static let shared = DiscoverySettingsController()

    private let startFolder = NSPopUpButton(frame: .zero, pullsDown: false)
    private let startView = NSPopUpButton(frame: .zero, pullsDown: false)
    private var checks: [NSButton: (Bool) -> Void] = [:]
    private var states: [(NSButton, () -> Bool)] = []

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "AINCRAD Discovery Settings"
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        build(w)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build(_ w: NSWindow) {
        startFolder.addItems(withTitles: ["Home", "Last folder"])
        startFolder.target = self; startFolder.action = #selector(popupChanged(_:))
        startView.addItems(withTitles: ["Last used view", "List", "Columns"])
        startView.target = self; startView.action = #selector(popupChanged(_:))

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Start in:"), startFolder],
            [NSTextField(labelWithString: "Open folders in:"), startView],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing

        let hidden = check("Show hidden files", { DiscoveryPrefs.showHidden }, { DiscoveryPrefs.showHidden = $0 })
        let trash = check("Ask before moving files to the Trash", { DiscoveryPrefs.confirmTrash }, { DiscoveryPrefs.confirmTrash = $0 })
        let pin = check("Keep the toolbar and sidebar pinned (sidebar shows names)", { DiscoveryPrefs.pinEdges }, { DiscoveryPrefs.pinEdges = $0 })

        let note = NSTextField(wrappingLabelWithString: "Start-in and hidden-file choices apply to windows you open next. Pinning applies to open windows straight away; off, the toolbar and sidebar appear when the pointer reaches their edges.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 400

        let rule = NSBox()
        rule.boxType = .separator
        let chrome = check("Use AINCRAD stoplights in the toolbar", { DiscoveryPrefs.browserChrome }, { DiscoveryPrefs.browserChrome = $0 })
        let stack = NSStackView(views: [grid, rule, hidden, trash, pin, chrome, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        refresh()
    }

    private func check(_ title: String, _ read: @escaping () -> Bool, _ write: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkChanged(_:)))
        checks[b] = write
        states.append((b, read))
        return b
    }

    private func refresh() {
        startFolder.selectItem(at: DiscoveryPrefs.startFolder == .last ? 1 : 0)
        startView.selectItem(at: ["last": 0, "list": 1, "columns": 2][DiscoveryPrefs.startView.rawValue] ?? 0)
        for (button, read) in states { button.state = read() ? .on : .off }
    }

    @objc private func checkChanged(_ sender: NSButton) {
        checks[sender]?(sender.state == .on)
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        if sender === startFolder {
            DiscoveryPrefs.startFolder = sender.indexOfSelectedItem == 1 ? .last : .home
        } else {
            DiscoveryPrefs.startView = [0: DiscoveryPrefs.StartView.last, 1: .list, 2: .columns][sender.indexOfSelectedItem] ?? .last
        }
    }
}
