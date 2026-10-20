import AppKit
import Quartz

/// The seam for previews: the controller only talks to this protocol, so a richer previewer can replace Quick Look later.
protocol PreviewProviding: AnyObject {
    func toggle(urls: [URL])
    func update(urls: [URL])
    func close()
}

final class QuickLookPreview: NSObject, PreviewProviding, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// Lets the arrow keys keep moving the file selection while the panel is key.
    var forwardKey: ((NSEvent) -> Void)?
    private var urls: [URL] = []

    private var panel: QLPreviewPanel? { QLPreviewPanel.shared() }

    func toggle(urls: [URL]) {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        guard !urls.isEmpty else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func update(urls: [URL]) {
        self.urls = urls
        guard let panel, panel.isVisible, panel.dataSource === self else { return }
        if urls.isEmpty { panel.orderOut(nil) } else { panel.reloadData() }
    }

    func close() {
        if let panel, panel.isVisible, panel.dataSource === self { panel.orderOut(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [125, 126].contains(event.keyCode) else { return false }
        forwardKey?(event)
        return true
    }
}
