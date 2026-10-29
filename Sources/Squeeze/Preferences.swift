import AppKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

// MARK: - Preferences (Squeeze → Settings…)

enum FinderDestination: String, CaseIterable, Identifiable {
    case nextToOriginal, appFolder, customFolder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nextToOriginal: return "Next to the original"
        case .appFolder: return "Squeeze's “Save to” folder"
        case .customFolder: return "A specific folder"
        }
    }
}

enum MenuBarMode: String, CaseIterable, Identifiable {
    case always, whileWorking, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: return "Always"
        case .whileWorking: return "While working"
        case .never: return "Never"
        }
    }
}

@MainActor
@Observable
final class Preferences {
    @ObservationIgnored private let defaults = UserDefaults.standard

    // Finder
    /// false = work in the background (no window, no Dock icon).
    var finderShowsWindow: Bool { didSet { defaults.set(finderShowsWindow, forKey: "pref.finderShowsWindow") } }
    var finderDestination: FinderDestination { didSet { defaults.set(finderDestination.rawValue, forKey: "pref.finderDestination") } }
    var finderCustomFolder: URL { didSet { defaults.set(finderCustomFolder.path, forKey: "pref.finderCustomFolder") } }
    var finderCompressPrefix: String { didSet { defaults.set(finderCompressPrefix, forKey: "pref.finderCompressPrefix") } }
    var finderCompressSuffix: String { didSet { defaults.set(finderCompressSuffix, forKey: "pref.finderCompressSuffix") } }
    var finderConvertPrefix: String { didSet { defaults.set(finderConvertPrefix, forKey: "pref.finderConvertPrefix") } }
    var finderConvertSuffix: String { didSet { defaults.set(finderConvertSuffix, forKey: "pref.finderConvertSuffix") } }
    var finderNotify: Bool { didSet { defaults.set(finderNotify, forKey: "pref.finderNotify") } }
    var finderReveal: Bool { didSet { defaults.set(finderReveal, forKey: "pref.finderReveal") } }
    var finderQuitWhenDone: Bool { didSet { defaults.set(finderQuitWhenDone, forKey: "pref.finderQuitWhenDone") } }

    // General
    var menuBarMode: MenuBarMode { didSet { defaults.set(menuBarMode.rawValue, forKey: "pref.menuBarMode") } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: "pref.playSound") } }
    var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: "pref.keepAwake") } }

    init() {
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
        func string(_ key: String, _ fallback: String) -> String { d.string(forKey: key) ?? fallback }

        finderShowsWindow = bool("pref.finderShowsWindow", false)
        finderDestination = FinderDestination(rawValue: string("pref.finderDestination", "")) ?? .nextToOriginal
        finderCustomFolder = d.string(forKey: "pref.finderCustomFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        finderCompressPrefix = string("pref.finderCompressPrefix", "")
        finderCompressSuffix = string("pref.finderCompressSuffix", "_compressed")
        finderConvertPrefix = string("pref.finderConvertPrefix", "")
        finderConvertSuffix = string("pref.finderConvertSuffix", "")
        finderNotify = bool("pref.finderNotify", true)
        finderReveal = bool("pref.finderReveal", false)
        finderQuitWhenDone = bool("pref.finderQuitWhenDone", true)

        menuBarMode = MenuBarMode(rawValue: string("pref.menuBarMode", "")) ?? .whileWorking
        playSound = bool("pref.playSound", true)
        keepAwake = bool("pref.keepAwake", true)
    }

    /// Where and how files queued from Finder are saved.
    func finderNaming(for action: SqueezeLink.Action, appFolder: URL) -> OutputNaming {
        let isCompress = action == .compress
        let prefix = isCompress ? finderCompressPrefix : finderConvertPrefix
        let suffix = isCompress ? finderCompressSuffix : finderConvertSuffix
        switch finderDestination {
        case .nextToOriginal:
            return OutputNaming(prefix: prefix, suffix: suffix, folder: appFolder, nextToOriginal: true)
        case .appFolder:
            return OutputNaming(prefix: prefix, suffix: suffix, folder: appFolder)
        case .customFolder:
            return OutputNaming(prefix: prefix, suffix: suffix, folder: finderCustomFolder)
        }
    }

    func chooseFinderFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = finderCustomFolder
        panel.prompt = "Choose"
        panel.message = "Where should files from the Finder menu be saved?"
        if panel.runModal() == .OK, let url = panel.url { finderCustomFolder = url }
    }
}

// MARK: - App model (shared by the window, the menu bar item and Finder requests)

@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings = SettingsStore()
    let prefs = Preferences()
    let compressQueue = QueueManager(kind: .compress)
    let convertQueue = QueueManager(kind: .convert)

    /// Finished files from Finder requests waiting to be revealed when the queue goes idle.
    private var pendingReveal: [URL] = []

    var isBusy: Bool { compressQueue.isRunning || convertQueue.isRunning }
    var activeItems: [QueueItem] {
        (compressQueue.items + convertQueue.items).filter { item in
            if case .encoding = item.status { return true }
            return item.isWaiting
        }
    }

    private init() {
        for queue in [compressQueue, convertQueue] {
            queue.onItemFinished = { [weak self] item in self?.itemFinished(item) }
            queue.onIdle = { [weak self] in self?.queueBecameIdle() }
        }
    }

    private func itemFinished(_ item: QueueItem) {
        guard item.fromFinder else { return }
        if prefs.finderNotify { Notifier.post(for: item) }
        if prefs.finderReveal, case .done(let url, _) = item.status { pendingReveal.append(url) }
    }

    private func queueBecameIdle() {
        guard !isBusy else { return }
        if !pendingReveal.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(pendingReveal)
            pendingReveal.removeAll()
        }
        // Launched from Finder with no window open: quit once everything is done.
        if prefs.finderQuitWhenDone && !MainWindow.shared.isVisible && !Self.hasOtherVisibleWindows {
            // Give the last notification a moment to be delivered.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if !AppModel.shared.isBusy && !MainWindow.shared.isVisible { NSApp.terminate(nil) }
            }
        }
    }

    /// True when the Settings window (or any other titled window) is open.
    static var hasOtherVisibleWindows: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && $0 !== MainWindow.shared.window }
    }
}

// MARK: - Main window (AppKit-hosted so Squeeze can run with no window at all)

@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()
    private(set) var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let model = AppModel.shared
            let root = ContentView(compressQueue: model.compressQueue,
                                   convertQueue: model.convertQueue,
                                   settings: model.settings)
                .frame(minWidth: 640, minHeight: 500)
            let controller = NSHostingController(rootView: root)
            controller.sceneBridgingOptions = [.toolbars, .title]   // SwiftUI toolbar + title → NSWindow

            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = "Squeeze"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 780, height: 620))
            window.center()
            window.setFrameAutosaveName("SqueezeMainWindow")
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        if AppModel.shared.isBusy {
            // Keep working in the background; progress stays in the menu bar.
            NSApp.setActivationPolicy(.accessory)
        } else if !AppModel.hasOtherVisibleWindows {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Notifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func post(for item: QueueItem) {
        let content = UNMutableNotificationContent()
        let name = item.source.lastPathComponent
        switch item.status {
        case .done(let url, let size):
            content.title = "Done: \(name)"
            var body = "Saved as \(url.lastPathComponent)"
            if item.sourceSize > 0 {
                body += " · \(Files.formatted(item.sourceSize)) → \(Files.formatted(size))"
            }
            content.body = body
            content.userInfo = ["path": url.path]
        case .failed(let message):
            content.title = "Couldn't process \(name)"
            content.body = message
            content.userInfo = ["path": item.source.path]
        default:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
