import AppKit
import CoreText

/// AINCRAD's look, read live from AINCRAD's active theme (~/Library/Application Support/AINCRAD):
/// colours, accent and fonts follow whatever theme you pick there, and change the moment you switch.
/// Without AINCRAD installed, Discovery uses Aincrad Classic (white and orange).
enum AINCRADTheme {
    static let changed = Notification.Name("AINCRADDiscoveryThemeChanged")

    private(set) static var accent = NSColor(srgbRed: 0.961, green: 0.651, blue: 0.137, alpha: 1)
    private(set) static var panel = NSColor(srgbRed: 0.969, green: 0.969, blue: 0.973, alpha: 0.98)
    private(set) static var panelText = NSColor(srgbRed: 0.263, green: 0.278, blue: 0.306, alpha: 1)
    private(set) static var panelBorder = NSColor.white.withAlphaComponent(0.9)
    private(set) static var footer = NSColor(srgbRed: 0.902, green: 0.906, blue: 0.918, alpha: 0.97)
    private(set) static var circle = NSColor(srgbRed: 0.973, green: 0.973, blue: 0.976, alpha: 0.95)
    private(set) static var hover = NSColor.white
    private(set) static var circleBorder = NSColor.white
    private(set) static var circleIcon = NSColor(srgbRed: 0.557, green: 0.573, blue: 0.6, alpha: 1)
    private(set) static var circleDiameter: CGFloat = 54
    private(set) static var cornerRadius: CGFloat = 4
    private(set) static var borderWidth: CGFloat = 1
    private(set) static var glow: CGFloat = 12
    private(set) static var glowOpacity: Float = 0.65
    private(set) static var shadowRadius: CGFloat = 10
    private(set) static var shadowOpacity: Float = 0.35
    private(set) static var bodySize: CGFloat = 20
    private(set) static var shadowColor = NSColor(white: 0, alpha: 0.36)
    private(set) static var iconBadge = NSColor(srgbRed: 0.365, green: 0.38, blue: 0.412, alpha: 1)
    private(set) static var iconGlyph = NSColor.white
    private(set) static var windowClose = NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1)
    private(set) static var windowMinimize = NSColor(srgbRed: 0.996, green: 0.737, blue: 0.18, alpha: 1)
    private(set) static var windowZoom = NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)
    private(set) static var gradient: CGFloat = 0.07
    private(set) static var shine: CGFloat = 0.7
    private(set) static var itemHeight: CGFloat = 38
    private(set) static var ringWidth: CGFloat = 2
    private(set) static var accentText = NSColor.white
    private(set) static var bodyFamily = "Rajdhani"
    private(set) static var displayFamily = "Orbitron"
    /// Your AINCRAD player name ("" if none is set).
    private(set) static var playerName = ""
    private(set) static var themeName = "Aincrad Classic"

    /// Light themes (white panels) or dark ones, judged from the panel colour.
    static var isDark: Bool { luminance(panel) < 0.5 }

    // Kept for the code that styled the dark chrome before themes were live.
    static var darkPanel: NSColor { panel }
    static var darkText: NSColor { panelText }

    /// The selected tab colour.
    static var tabBezel: NSColor { accent }

    private static var aincradFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AINCRAD", isDirectory: true)
    }

    /// Registers the bundled fonts, loads the theme, and listens for AINCRAD switching themes.
    static func start() {
        // Xcode flattens Resources/Fonts into the bundle root, so look in both places.
        for url in (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []) + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        reload()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.djag.aincrad.themeChanged"), object: nil, queue: .main) { _ in
            reload()
        }
        // A fallback for older AINCRAD builds that don't announce theme changes.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in reload() }
    }

    static func reload() {
        let before = signature
        var colors: [String: String] = [:], font: [String: Any] = [:], geometry: [String: Any] = [:], effects: [String: Any] = [:]
        if let settings = json(aincradFolder.appendingPathComponent("settings.json")) {
            playerName = (settings["playerName"] as? String) ?? ""
            let id = (settings["theme"] as? String) ?? "aincrad-classic"
            if let theme = json(aincradFolder.appendingPathComponent("themes/\(id).json")) {
                colors = (theme["colors"] as? [String: String]) ?? [:]
                font = (theme["font"] as? [String: Any]) ?? [:]
                geometry = (theme["geometry"] as? [String: Any]) ?? [:]
                effects = (theme["effects"] as? [String: Any]) ?? [:]
                themeName = (theme["name"] as? String) ?? id
            }
        }
        accent = color(colors["accent"]) ?? NSColor(srgbRed: 0.961, green: 0.651, blue: 0.137, alpha: 1)
        panel = color(colors["panel"]) ?? NSColor(srgbRed: 0.969, green: 0.969, blue: 0.973, alpha: 0.95)
        panelText = color(colors["panelText"]) ?? NSColor(srgbRed: 0.263, green: 0.278, blue: 0.306, alpha: 1)
        panelBorder = color(colors["panelBorder"]) ?? NSColor.white.withAlphaComponent(0.9)
        footer = color(colors["infoFooter"]) ?? NSColor(srgbRed: 0.902, green: 0.906, blue: 0.918, alpha: 0.96)
        circle = color(colors["circle"]) ?? panel
        hover = color(colors["hover"]) ?? .white
        circleBorder = color(colors["circleBorder"]) ?? .white
        circleIcon = color(colors["circleIcon"]) ?? NSColor(srgbRed: 0.557, green: 0.573, blue: 0.6, alpha: 1)
        func num(_ d: [String: Any], _ k: String, _ fallback: Double) -> Double { (d[k] as? NSNumber)?.doubleValue ?? fallback }
        circleDiameter = CGFloat(num(geometry, "circleDiameter", 54))
        cornerRadius = CGFloat(num(geometry, "cornerRadius", 4))
        borderWidth = CGFloat(num(effects, "borderWidth", 1))
        glow = CGFloat(num(effects, "selectedGlow", 12))
        glowOpacity = Float(num(effects, "glowOpacity", 0.65))
        shadowRadius = CGFloat(num(effects, "shadowRadius", 10))
        shadowOpacity = Float(num(effects, "shadowOpacity", 0.35))
        bodySize = CGFloat(num(font, "size", 20))
        shadowColor = color(colors["shadow"]) ?? NSColor(white: 0, alpha: 0.36)
        iconBadge = color(colors["iconBadge"]) ?? NSColor(srgbRed: 0.365, green: 0.38, blue: 0.412, alpha: 1)
        iconGlyph = color(colors["iconGlyph"]) ?? .white
        windowClose = color(colors["windowClose"]) ?? NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1)
        windowMinimize = color(colors["windowMinimize"]) ?? NSColor(srgbRed: 0.996, green: 0.737, blue: 0.18, alpha: 1)
        windowZoom = color(colors["windowZoom"]) ?? NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)
        gradient = CGFloat(num(effects, "gradient", 0.07))
        shine = CGFloat(num(effects, "shine", 0.7))
        itemHeight = CGFloat(num(geometry, "itemHeight", 38))
        ringWidth = CGFloat(num(effects, "selectedRingWidth", 2))
        accentText = color(colors["accentText"]) ?? .white
        bodyFamily = (font["family"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Rajdhani"
        displayFamily = (font["display"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bodyFamily
        if signature != before { NotificationCenter.default.post(name: changed, object: nil) }
    }

    private static var signature: String {
        [accent, panel, panelText, footer, circleBorder, circleIcon, iconBadge, windowClose, windowMinimize, windowZoom].map { $0.description }.joined() + "\(circleDiameter)\(cornerRadius)\(borderWidth)\(bodySize)" + bodyFamily + displayFamily + playerName
    }

    private static func json(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// "#RRGGBB" or "#RRGGBBAA", as AINCRAD's themes write them.
    static func color(_ hex: String?) -> NSColor? {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
        h.removeFirst()
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let a = h.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        let rgb = h.count == 8 ? v >> 8 : v
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
    }

    static func css(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "rgba(%d,%d,%d,%.3f)", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255), s.alphaComponent)
    }

    static func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB) ?? c
        return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent
    }

    private static func font(_ family: String, _ size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let w = weight >= .semibold ? 9 : 6
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: w, size: size) ?? NSFont(name: family, size: size)
    }

    /// The toolbar button diameter: the launcher's circle times the "Toolbar size" setting (default 100%).
    static var buttonSize: CGFloat { max(36, min(84, circleDiameter.rounded())) }
    static var rowHeight: CGFloat { 38 }
    /// Tab rows are launcher rows scaled with the toolbar.
    static var tabHeight: CGFloat { max(34, buttonSize - 6) }
    static var tabFontSize: CGFloat { max(15, min(24, bodySize * 0.8)) }

    /// A launcher-style glyph: the same SF Symbols, a touch bolder.
    static func glyph(_ name: String, _ help: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .medium))
    }

    /// The launcher's two-stop fill: a touch lighter at the top and darker at the bottom (effects.gradient).
    static func shade(_ color: NSColor) -> [CGColor] {
        let c = color.usingColorSpace(.sRGB) ?? color
        let top = (c.blended(withFraction: gradient, of: .white) ?? c).withAlphaComponent(c.alphaComponent)
        let bottom = (c.blended(withFraction: gradient, of: .black) ?? c).withAlphaComponent(c.alphaComponent)
        return [top.cgColor, bottom.cgColor]
    }

    static func displayFont(size: CGFloat) -> NSFont {
        font(displayFamily, size, weight: .semibold) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func bodyFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        font(bodyFamily, size, weight: weight) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// The launcher's glass circle buttons.
    static func styleCircle(_ button: NSButton) {
        button.isBordered = false
        button.contentTintColor = panelText
        button.wantsLayer = true
        button.layer?.cornerRadius = 15
        button.layer?.backgroundColor = circle.cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = accent.withAlphaComponent(0.35).cgColor
    }

    static func makeMark(size: CGFloat = 24) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        accent.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: size - 4, height: size - 4))
        ring.lineWidth = max(1.5, size * 0.075)
        ring.stroke()
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: size * 0.31, y: size * 0.29))
        slash.line(to: NSPoint(x: size * 0.69, y: size * 0.71))
        slash.lineWidth = max(1.5, size * 0.075)
        slash.lineCapStyle = .round
        slash.stroke()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
