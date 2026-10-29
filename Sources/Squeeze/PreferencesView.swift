import FinderSync
import SwiftUI

// MARK: - Settings window (Squeeze → Settings…, ⌘,)

struct PreferencesView: View {
    let prefs: Preferences
    let settings: SettingsStore

    var body: some View {
        TabView {
            FinderPreferences(prefs: prefs, settings: settings)
                .tabItem { Label("Finder", systemImage: "folder") }
            GeneralPreferences(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FinderPreferences: View {
    @Bindable var prefs: Preferences
    let settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("When you choose a Squeeze action", selection: $prefs.finderShowsWindow) {
                    Text("Work in the background").tag(false)
                    Text("Open the Squeeze window").tag(true)
                }
                .pickerStyle(.radioGroup)

                Toggle("Notify me when each file is done", isOn: $prefs.finderNotify)
                Toggle("Show finished files in Finder", isOn: $prefs.finderReveal)
                Toggle("Quit Squeeze when everything is done", isOn: $prefs.finderQuitWhenDone)
                    .disabled(prefs.finderShowsWindow)
                    .help("Only when Squeeze was working in the background with no window open.")
            } header: {
                Text("Behaviour")
            } footer: {
                Text(prefs.finderShowsWindow
                     ? "Squeeze opens, shows the files in its queue and starts straight away."
                     : "Squeeze works without a window or Dock icon. Progress shows in the menu bar.")
                    .foregroundStyle(.secondary)
            }

            Section("Save finished files") {
                Picker("Location", selection: $prefs.finderDestination) {
                    ForEach(FinderDestination.allCases) { Text($0.title).tag($0) }
                }
                switch prefs.finderDestination {
                case .nextToOriginal:
                    EmptyView()
                case .appFolder:
                    LabeledContent("Folder") {
                        Text(display(settings.outputFolder)).foregroundStyle(.secondary)
                    }
                case .customFolder:
                    LabeledContent("Folder") {
                        HStack {
                            Text(display(prefs.finderCustomFolder))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Choose…") { prefs.chooseFinderFolder() }
                        }
                    }
                }
            }

            Section {
                NamingRow(title: "Compress", prefix: $prefs.finderCompressPrefix,
                          suffix: $prefs.finderCompressSuffix, fileExtension: "mp4")
                NamingRow(title: "Convert", prefix: $prefs.finderConvertPrefix,
                          suffix: $prefs.finderConvertSuffix, fileExtension: "gif")
            } header: {
                Text("File names")
            } footer: {
                Text("Squeeze never overwrites a file. If the name is taken, it adds a number.")
                    .foregroundStyle(.secondary)
            }

            Section("Finder extension") {
                LabeledContent("Right-click → Squeeze") {
                    Button("Extension Settings…") { FIFinderSyncController.showExtensionManagementInterface() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func display(_ url: URL) -> String {
        url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

private struct NamingRow: View {
    let title: String
    @Binding var prefix: String
    @Binding var suffix: String
    let fileExtension: String

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Prefix", text: $prefix)
                        .labelsHidden()
                        .frame(width: 90)
                    Text("name").foregroundStyle(.tertiary).font(.callout.monospaced())
                    TextField("Suffix", text: $suffix)
                        .labelsHidden()
                        .frame(width: 110)
                }
                Text("holiday.mov → \(prefix)holiday\(suffix).\(fileExtension)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeneralPreferences: View {
    @Bindable var prefs: Preferences

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show Squeeze in the menu bar", selection: $prefs.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("While working") {
                Toggle("Keep the Mac awake", isOn: $prefs.keepAwake)
                Toggle("Play a sound when a queue finishes", isOn: $prefs.playSound)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu bar item

struct MenuBarView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Squeeze").font(.headline)
                Spacer()
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            let active = model.activeItems
            if active.isEmpty {
                Text("Nothing in the queue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(active.prefix(6)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.source.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            if let label = item.jobLabel {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        if case .encoding(let value) = item.status {
                            ProgressView(value: value)
                        } else {
                            Text("Waiting").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if active.count > 6 {
                    Text("and \(active.count - 6) more…").font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Open Squeeze") { MainWindow.shared.show() }
                    .buttonStyle(.glass)
                if model.isBusy {
                    Button("Stop All") {
                        model.compressQueue.stop()
                        model.convertQueue.stop()
                    }
                    .buttonStyle(.glass)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.glass)
                    .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.glass)
                    .help("Quit Squeeze")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
