import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [DiscoveryWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        // Folders or files handed over at launch open their own windows, so the start window only opens if none did.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.windows.isEmpty else { return }
            self.open(self.startFolder())
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder's "Open With", AINCRAD's "Show in Discovery" and the command line all arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { open($0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { open(startFolder()) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Opens a folder in a new window. A file opens its folder with the file selected.
    func open(_ url: URL) {
        let controller = DiscoveryWindowController(startingAt: url)
        windows.append(controller)
        controller.onClose = { [weak self, weak controller] in self?.windows.removeAll { $0 === controller } }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startFolder() -> URL {
        if DiscoveryPrefs.startFolder == .last, let last = DiscoveryPrefs.lastFolder, FileManager.default.fileExists(atPath: last.path) {
            return last
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    @objc private func newWindow() { open(startFolder()) }
    @objc private func showSettings() { DiscoverySettingsController.shared.show() }

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, url: URL? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        i.representedObject = url
        return i
    }

    private func buildMenu() {
        let main = NSMenu()
        let home = FileManager.default.homeDirectoryForCurrentUser

        let appMenu = NSMenu()
        appMenu.addItem(item("Settings…", #selector(showSettings), ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit AINCRAD Discovery", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(menuItem("AINCRAD Discovery", appMenu))

        let file = NSMenu(title: "File")
        file.addItem(item("New Window", #selector(newWindow), "n", target: self))
        file.addItem(item("New Folder", #selector(DiscoveryWindowController.newFolder), "n", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Show Info", #selector(DiscoveryWindowController.showInfo), "i"))
        file.addItem(item("Move to Trash", #selector(DiscoveryWindowController.trashSelection)))
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        main.addItem(menuItem("File", file))

        let view = NSMenu(title: "View")
        view.addItem(item("as List", #selector(DiscoveryWindowController.showList), "1"))
        view.addItem(item("as Columns", #selector(DiscoveryWindowController.showColumns), "2"))
        view.addItem(.separator())
        view.addItem(item("Show Hidden Files", #selector(DiscoveryWindowController.toggleHiddenFiles), ".", [.command, .shift]))
        main.addItem(menuItem("View", view))

        let go = NSMenu(title: "Go")
        go.addItem(item("Back", #selector(DiscoveryWindowController.goBack), "["))
        go.addItem(item("Forward", #selector(DiscoveryWindowController.goForward), "]"))
        go.addItem(item("Enclosing Folder", #selector(DiscoveryWindowController.goUp), String(utf16CodeUnits: [unichar(NSUpArrowFunctionKey)], count: 1)))
        go.addItem(.separator())
        go.addItem(item("Home", #selector(DiscoveryWindowController.goToFavourite(_:)), "h", [.command, .shift], url: home))
        go.addItem(item("Desktop", #selector(DiscoveryWindowController.goToFavourite(_:)), "d", [.command, .shift], url: home.appendingPathComponent("Desktop")))
        go.addItem(item("Documents", #selector(DiscoveryWindowController.goToFavourite(_:)), "o", [.command, .shift], url: home.appendingPathComponent("Documents")))
        go.addItem(item("Downloads", #selector(DiscoveryWindowController.goToFavourite(_:)), "l", [.command, .option], url: home.appendingPathComponent("Downloads")))
        go.addItem(item("Applications", #selector(DiscoveryWindowController.goToFavourite(_:)), "a", [.command, .shift], url: URL(fileURLWithPath: "/Applications")))
        go.addItem(.separator())
        go.addItem(item("Go to Folder…", #selector(DiscoveryWindowController.goToFolder), "g", [.command, .shift]))
        go.addItem(item("Search", #selector(DiscoveryWindowController.focusSearch), "f"))
        main.addItem(menuItem("Go", go))

        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }
}
