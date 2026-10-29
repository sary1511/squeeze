import Cocoa
import FinderSync

/// Right-click → Squeeze in Finder. Every action is handed to the Squeeze app
/// through a squeeze:// URL, which queues the files and starts processing.
@objc(SqueezeFinderSync)
final class SqueezeFinderSync: FIFinderSync {

    override init() {
        super.init()
        // Offer the menu everywhere, including external drives.
        var roots = [URL(fileURLWithPath: "/")]
        roots += (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                       options: [.skipHiddenVolumes]) ?? [])
        FIFinderSyncController.default().directoryURLs = Set(roots)
    }

    // MARK: Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selected = FIFinderSyncController.default().selectedItemURLs(),
              selected.contains(where: Self.isCandidate)
        else { return nil }

        let squeeze = NSMenu(title: "Squeeze")

        squeeze.addItem(item("Compress", #selector(compress(_:)), symbol: "arrow.down.right.and.arrow.up.left"))

        let presets = NSMenu(title: "Compress With")
        for (index, preset) in SqueezeLink.compressPresets.enumerated() {
            presets.addItem(item(preset.title, #selector(compressWithPreset(_:)), tag: index))
        }
        squeeze.addItem(submenu("Compress With", presets, symbol: "slider.horizontal.3"))

        squeeze.addItem(.separator())

        let convert = NSMenu(title: "Convert To")
        var index = 0
        for (groupIndex, group) in SqueezeLink.convertMenu.enumerated() {
            if groupIndex > 0 { convert.addItem(.separator()) }
            for format in group {
                convert.addItem(item(format.title, #selector(convertTo(_:)), tag: index))
                index += 1
            }
        }
        squeeze.addItem(submenu("Convert To", convert, symbol: "arrow.triangle.2.circlepath"))

        let copy = NSMenu(title: "Change Container Only")
        for (i, format) in SqueezeLink.copyMenu.enumerated() {
            copy.addItem(item(format.title, #selector(changeContainer(_:)), tag: i))
        }
        squeeze.addItem(submenu("Change Container Only", copy, symbol: "shippingbox"))

        squeeze.addItem(.separator())
        squeeze.addItem(item("Open in Squeeze", #selector(openInSqueeze(_:)), symbol: "macwindow"))

        let menu = NSMenu(title: "")
        let root = submenu("Squeeze", squeeze, symbol: "film.stack")
        menu.addItem(root)
        return menu
    }

    // MARK: Actions (Finder copies menu items, so only `tag` survives — not representedObject)

    @objc func compress(_ sender: NSMenuItem) {
        send(SqueezeLink.Request(action: .compress, files: selection()))
    }

    @objc func compressWithPreset(_ sender: NSMenuItem) {
        guard SqueezeLink.compressPresets.indices.contains(sender.tag) else { return }
        let preset = SqueezeLink.compressPresets[sender.tag]
        var request = SqueezeLink.Request(action: .compress, files: selection())
        request.engine = preset.engine
        request.codec = preset.codec
        request.hardware = preset.hardware
        send(request)
    }

    @objc func convertTo(_ sender: NSMenuItem) {
        let formats = SqueezeLink.convertFormats
        guard formats.indices.contains(sender.tag) else { return }
        var request = SqueezeLink.Request(action: .convert, files: selection())
        request.format = formats[sender.tag].id
        send(request)
    }

    @objc func changeContainer(_ sender: NSMenuItem) {
        guard SqueezeLink.copyMenu.indices.contains(sender.tag) else { return }
        var request = SqueezeLink.Request(action: .convert, files: selection())
        request.format = SqueezeLink.copyMenu[sender.tag].id
        request.copyStreams = true
        send(request)
    }

    @objc func openInSqueeze(_ sender: NSMenuItem) {
        send(SqueezeLink.Request(action: .open, files: selection()))
    }

    // MARK: Helpers

    private func selection() -> [URL] {
        (FIFinderSyncController.default().selectedItemURLs() ?? []).filter(Self.isCandidate)
    }

    private func send(_ request: SqueezeLink.Request) {
        guard !request.files.isEmpty, let url = request.url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func isCandidate(_ url: URL) -> Bool {
        url.hasDirectoryPath || SqueezeLink.videoExtensions.contains(url.pathExtension.lowercased())
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu, symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.submenu = menu
        return item
    }
}
