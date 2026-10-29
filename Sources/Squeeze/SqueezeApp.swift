import AppKit
import FinderSync
import SwiftUI
import UserNotifications

@main
struct SqueezeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        // The main window is AppKit-hosted (MainWindow) so that Finder actions can
        // run with no window at all. SwiftUI provides Settings and the menu bar item.
        Settings {
            PreferencesView(prefs: model.prefs, settings: model.settings)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Videos…") {
                    MainWindow.shared.show()
                    let queue = model.settings.mode == .compress ? model.compressQueue : model.convertQueue
                    queue.addWithPanel()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(before: .windowList) {
                Button("Squeeze Window") { MainWindow.shared.show() }
                    .keyboardShortcut("0")
                Divider()
            }
        }

        MenuBarExtra(isInserted: Binding(
            get: {
                switch model.prefs.menuBarMode {
                case .always: return true
                case .whileWorking: return model.isBusy
                case .never: return false
                }
            },
            set: { _ in }
        )) {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.isBusy ? "arrow.down.right.and.arrow.up.left.circle.fill" : "film.stack")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var receivedLink = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        registerFinderExtension()

        // A normal launch (Dock, Launchpad, Spotlight) opens the window.
        // A launch from the Finder menu arrives as a squeeze:// link instead,
        // and the Finder settings decide whether a window appears.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            MainWindow.shared.show()
        } else {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                // Launched for some other reason without a Finder link: show the window.
                if self?.receivedLink == false && !MainWindow.shared.isVisible { MainWindow.shared.show() }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == SqueezeLink.scheme {
                receivedLink = true
                FinderRequests.handle(url)
            } else if url.isFileURL {
                // Files dropped on the Dock icon.
                MainWindow.shared.show()
                let model = AppModel.shared
                (model.settings.mode == .compress ? model.compressQueue : model.convertQueue).add([url])
            }
        }
    }

    /// Clicking the Dock icon with no window open brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !MainWindow.shared.isVisible { MainWindow.shared.show() }
        return true
    }

    /// Closing windows never quits while work is running; MainWindow decides.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a notification shows the file in Finder.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            Task { @MainActor in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        completionHandler()
    }

    // MARK: Finder extension

    /// Makes sure macOS knows about the bundled Finder extension, and switches it
    /// on the first time Squeeze runs. (Users can turn it off in System Settings.)
    private func registerFinderExtension() {
        guard let plugIns = Bundle.main.builtInPlugInsURL else { return }
        let appex = plugIns.appendingPathComponent("SqueezeFinder.appex")
        guard FileManager.default.fileExists(atPath: appex.path) else { return }

        runPluginKit(["-a", appex.path])
        let key = "finderExtensionEnabledOnce"
        if !UserDefaults.standard.bool(forKey: key) {
            runPluginKit(["-e", "use", "-i", SqueezeLink.extensionBundleID])
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    private func runPluginKit(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
    }
}
