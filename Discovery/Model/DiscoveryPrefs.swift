import Foundation

/// Discovery's settings, kept in UserDefaults. They are read when needed, so most changes apply to open windows straight away.
enum DiscoveryPrefs {
    enum StartFolder: String { case home, last }
    enum StartView: String { case last, list, columns }

    private static var defaults: UserDefaults { .standard }

    static var startFolder: StartFolder {
        get { StartFolder(rawValue: defaults.string(forKey: "prefs.startFolder") ?? "") ?? .home }
        set { defaults.set(newValue.rawValue, forKey: "prefs.startFolder") }
    }

    static var startView: StartView {
        get { StartView(rawValue: defaults.string(forKey: "prefs.startView") ?? "") ?? .last }
        set { defaults.set(newValue.rawValue, forKey: "prefs.startView") }
    }

    /// The view used last time (list or columns), for "Last used view".
    static var lastView: String? {
        get { defaults.string(forKey: "discovery.viewMode") }
        set { defaults.set(newValue, forKey: "discovery.viewMode") }
    }

    /// The folder open when Discovery last showed one, for "Last folder".
    static var lastFolder: URL? {
        get { defaults.string(forKey: "prefs.lastFolder").map { URL(fileURLWithPath: $0) } }
        set { defaults.set(newValue?.path, forKey: "prefs.lastFolder") }
    }

    static var showHidden: Bool {
        get { bool("prefs.showHidden", default: false) }
        set { defaults.set(newValue, forKey: "prefs.showHidden") }
    }

    static var confirmTrash: Bool {
        get { bool("prefs.confirmTrash", default: true) }
        set { defaults.set(newValue, forKey: "prefs.confirmTrash") }
    }

    static let changed = Notification.Name("discovery.prefsChanged")

    /// AINCRAD stoplights in the toolbar in place of the system buttons.
    static var browserChrome: Bool {
        get { bool("prefs.browserChrome", default: true) }
        set {
            defaults.set(newValue, forKey: "prefs.browserChrome")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// The toolbar and sidebar stay out in view: the sidebar shows names and the toolbar never tucks away.
    /// Off, the sidebar widens over the list and the toolbar slides away until the pointer reaches the edges.
    static var pinEdges: Bool {
        get { bool("prefs.pinEdges", default: false) }
        set {
            defaults.set(newValue, forKey: "prefs.pinEdges")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }
}
