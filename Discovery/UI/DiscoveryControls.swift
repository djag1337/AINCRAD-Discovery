import AppKit

extension AINCRADTheme {
    /// Window background: a touch darker than the row panels so rows read as raised.
    static var discoveryBackground: NSColor {
        let p = panel.withAlphaComponent(1)
        return p.blended(withFraction: 0.06, of: panelText) ?? p
    }
    static var discoveryDim: NSColor { panelText.withAlphaComponent(0.65) }
}

/// A launcher circle: gradient fill, themed border, accent ring on hover, accent fill and glow when selected.
final class DCircleButton: NSControl {
    var image: NSImage? { didSet { renderIcon() } }
    var isSelected = false { didSet { restyle() } }
    /// Colour for the hover ring and glyph instead of the theme accent (the window buttons use their own).
    var hoverColor: NSColor?
    private let factor: CGFloat
    private let fill = CAGradientLayer()
    private let ring = CALayer()
    private let iconLayer = CALayer()
    private var hovering = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }
    private var lastTint: NSColor?
    private var renderedSide: CGFloat = 0
    private var widthC: NSLayoutConstraint!
    private var heightC: NSLayoutConstraint!

    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    override var toolTip: String? { didSet { setAccessibilityLabel(toolTip) } }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(factor: CGFloat = 1) {
        self.factor = factor
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        fill.masksToBounds = true
        layer?.addSublayer(fill)
        layer?.addSublayer(ring)
        layer?.addSublayer(iconLayer)
        iconLayer.contentsGravity = .resizeAspect
        let d = (AINCRADTheme.buttonSize * factor).rounded()
        widthC = widthAnchor.constraint(equalToConstant: d)
        heightC = heightAnchor.constraint(equalToConstant: d)
        NSLayoutConstraint.activate([widthC, heightC])
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func updateSize() {
        let d = (AINCRADTheme.buttonSize * factor).rounded()
        widthC.constant = d; heightC.constant = d
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let d = bounds.width
        layer?.cornerRadius = d / 2
        fill.frame = bounds
        fill.cornerRadius = d / 2
        ring.frame = bounds.insetBy(dx: -5, dy: -5)
        ring.cornerRadius = (d + 10) / 2
        let s = (d * 0.46).rounded()
        iconLayer.frame = CGRect(x: (d - s) / 2, y: (d - s) / 2, width: s, height: s)
        layer?.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        if abs(renderedSide - s) > 0.5 { renderedSide = s; renderIcon() }
        restyle()
    }

    func restyle() {
        let t = AINCRADTheme.self
        let tint: NSColor
        layer?.borderWidth = t.borderWidth
        layer?.borderColor = t.circleBorder.cgColor
        ring.borderWidth = t.ringWidth
        ring.borderColor = t.accent.cgColor
        if isSelected {
            fill.colors = t.shade(t.accent)
            ring.opacity = 1
            tint = t.accentText
            layer?.shadowColor = t.accent.cgColor; layer?.shadowOpacity = t.glowOpacity
            layer?.shadowRadius = t.glow; layer?.shadowOffset = .zero
        } else if hovering || pressed {
            fill.colors = t.shade(t.hover)
            ring.opacity = 0.6
            ring.borderColor = (hoverColor ?? t.accent).cgColor
            tint = hoverColor ?? t.accent
            plainShadow()
        } else {
            fill.colors = t.shade(t.circle)
            ring.opacity = 0
            tint = t.circleIcon
            plainShadow()
        }
        if lastTint != tint { lastTint = tint; renderIcon() }
    }

    private func plainShadow() {
        let t = AINCRADTheme.self
        layer?.shadowColor = t.shadowColor.cgColor; layer?.shadowOpacity = t.shadowOpacity
        layer?.shadowRadius = t.shadowRadius; layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    // The icon is tinted and drawn at its real pixel size, otherwise SF Symbols come out soft.
    private func renderIcon() {
        guard let image, let tint = lastTint ?? Optional(AINCRADTheme.circleIcon) else { iconLayer.contents = nil; return }
        let scale = max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 2)
        let side = max(iconLayer.bounds.width, 12)
        let tinted = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let ratio = image.size.width / max(image.size.height, 1)
            var fit = rect
            if ratio > 1 { fit.size.height = rect.width / ratio; fit.origin.y = (rect.height - fit.height) / 2 }
            else { fit.size.width = rect.height * ratio; fit.origin.x = (rect.width - fit.width) / 2 }
            image.draw(in: fit)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: side * scale, height: side * scale)
        iconLayer.contents = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        iconLayer.contentsScale = scale
        iconLayer.magnificationFilter = .trilinear
        iconLayer.minificationFilter = .trilinear
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); lastTint = nil; restyle() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { hovering = true } }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside, isEnabled { sendAction(action, to: target) }
    }
}

/// A small tab-style pill: glass panel, accent when it is the current one.
final class DPillView: NSView {
    var onTap: (() -> Void)?
    var isCurrent = false { didSet { refresh() } }
    private let fill = CAGradientLayer()
    private let shine = CALayer()
    private let label = NSTextField(labelWithString: "")
    private var hovering = false { didSet { refresh() } }

    static func font() -> NSFont { AINCRADTheme.bodyFont(size: 15, weight: .medium) }
    static func width(for title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font()]).width) + 26
    }

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(fill)
        layer?.addSublayer(shine)
        label.stringValue = title
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        toolTip = title
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let h = bounds.height
        fill.frame = bounds
        fill.cornerRadius = h / 2
        fill.masksToBounds = true
        shine.frame = CGRect(x: h / 2, y: h - 1.5, width: max(0, bounds.width - h), height: 1)
        shine.backgroundColor = NSColor.white.withAlphaComponent(AINCRADTheme.shine).cgColor
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        let lh = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: 13, y: ((h - lh) / 2).rounded(), width: max(0, bounds.width - 26), height: lh)
    }

    func refresh() {
        let t = AINCRADTheme.self
        label.font = Self.font()
        layer?.cornerRadius = bounds.height / 2
        layer?.borderWidth = t.borderWidth
        layer?.masksToBounds = false
        let state: (fill: NSColor, border: NSColor, text: NSColor)
        if isCurrent { state = (t.accent, t.accent, t.accentText) }
        else if hovering { state = (t.hover, t.accent, t.panelText) }
        else { state = (t.panel, t.panelBorder, t.panelText) }
        fill.colors = t.shade(state.fill)
        layer?.borderColor = state.border.cgColor
        label.textColor = state.text
        if isCurrent {
            layer?.shadowColor = t.accent.cgColor; layer?.shadowOpacity = t.glowOpacity * 0.6
            layer?.shadowRadius = min(t.glow, 5); layer?.shadowOffset = .zero
        } else {
            layer?.shadowColor = t.shadowColor.cgColor; layer?.shadowOpacity = t.shadowOpacity * 0.6
            layer?.shadowRadius = min(t.shadowRadius, 4); layer?.shadowOffset = CGSize(width: 0, height: -2)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onTap?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The folder path as tappable pills; long paths scroll sideways and stay pinned to the current folder.
final class PathBarView: NSView {
    typealias Crumb = (title: String, url: URL?)
    var onSelect: ((URL) -> Void)?
    private let scroll = DSidewaysScrollView()
    private let content = NSView()
    private var crumbs: [Crumb] = []
    private var pills: [DPillView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func set(_ crumbs: [Crumb]) {
        self.crumbs = crumbs
        pills.forEach { $0.removeFromSuperview() }
        pills = crumbs.enumerated().map { i, c in
            let p = DPillView(title: c.title)
            p.isCurrent = i == crumbs.count - 1
            p.onTap = { [weak self] in if let u = c.url { self?.onSelect?(u) } }
            content.addSubview(p)
            return p
        }
        needsLayout = true
        DispatchQueue.main.async { [weak self] in self?.scrollToEnd() }
    }

    func refreshTheme() { pills.forEach { $0.refresh() }; needsLayout = true }

    override func layout() {
        super.layout()
        // The pills share the bar: each keeps its natural width, and any spare room is split evenly between them.
        // They only scroll once they are wider than the bar.
        let gap: CGFloat = 8
        let h = bounds.height - 8
        let natural = crumbs.map { DPillView.width(for: $0.title) }
        let room = bounds.width - 8 - gap * CGFloat(max(pills.count - 1, 0))
        let spare = (room - natural.reduce(0, +)) / CGFloat(max(pills.count, 1))
        var x: CGFloat = 4
        for (i, p) in pills.enumerated() {
            let w = max(60, natural[i] + spare)
            p.frame = NSRect(x: x, y: 4, width: w, height: h)
            x = p.frame.maxX + gap
        }
        content.frame = NSRect(x: 0, y: 0, width: max(bounds.width, x - gap), height: bounds.height)
    }

    private func scrollToEnd() {
        guard let last = pills.last else { return }
        content.scrollToVisible(last.frame.insetBy(dx: -12, dy: 0))
    }
}

/// Moves sideways for a plain mouse wheel (vertical deltas) as well as a trackpad swipe.
final class DSidewaysScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : -event.scrollingDeltaY
        guard let doc = documentView else { return }
        let maxX = max(0, doc.frame.width - contentView.bounds.width)
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x + delta * (event.hasPreciseScrollingDeltas ? 1 : 12), 0), maxX)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

