import SwiftUI

struct ContentView: View {
    // Owned by SqueezeApp. Plain references (no @State) so the app also builds
    // with the Command Line Tools, which don't ship SwiftUI's macro plugin.
    let compressQueue: QueueManager
    let convertQueue: QueueManager
    let settings: SettingsStore

    private var mode: AppMode { settings.mode }
    private var queue: QueueManager { mode == .compress ? compressQueue : convertQueue }
    private var otherQueue: QueueManager { mode == .compress ? convertQueue : compressQueue }

    private var subtitle: String {
        var parts: [String] = []
        if !queue.summary.isEmpty { parts.append(queue.summary) }
        if otherQueue.isRunning { parts.append("\(otherQueue.kind.title) running in background") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if queue.items.isEmpty {
                EmptyQueueView(mode: mode, isTargeted: queue.isDropTargeted) { queue.addWithPanel() }
            } else {
                List {
                    ForEach(queue.items) { item in
                        QueueRow(
                            item: item,
                            thumbnail: queue.thumbnails[item.source],
                            onRemove: { queue.remove(item.id) },
                            onRetry: { queue.retry(item.id) }
                        )
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .id(mode)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OptionsPanel(settings: settings, mode: mode, isLocked: queue.isRunning)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 8)
        }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls)
            return true
        } isTargeted: { queue.isDropTargeted = $0 }
        .navigationTitle("Squeeze")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .animation(.smooth, value: queue.items.count)
        .animation(.smooth, value: mode)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: Binding(get: { settings.mode }, set: { settings.mode = $0 })) {
                ForEach(AppMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Switch between compressing and converting")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Add Videos", systemImage: "plus") { queue.addWithPanel() }
                .help("Add videos to the queue")
            Button("Clear Finished", systemImage: "checklist.checked") { queue.clearFinished() }
                .disabled(!queue.hasFinished)
                .help("Remove finished videos from the list")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            if queue.isRunning {
                Button("Stop", systemImage: "stop.fill") { queue.stop() }
                    .help("Stop after cancelling the current video")
            } else {
                Button(mode.actionTitle, systemImage: "play.fill") { queue.start(with: settings) }
                    .buttonStyle(.glassProminent)
                    .disabled(!queue.hasWaiting)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("\(mode.actionTitle) all waiting videos (⌘↩)")
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyQueueView: View {
    let mode: AppMode
    let isTargeted: Bool
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(mode.emptyTitle, systemImage: mode == .compress ? "film.stack" : "arrow.triangle.2.circlepath")
        } description: {
            Text(mode.emptyMessage)
        } actions: {
            Button("Add Videos…", action: onAdd)
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
                )
                .padding(20)
                .animation(.smooth(duration: 0.2), value: isTargeted)
        }
    }
}
