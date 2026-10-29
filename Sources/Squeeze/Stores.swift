import AppKit
import Foundation
import Observation

// MARK: - Settings (persisted)

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var engine: Engine { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    var codec: Codec { didSet { defaults.set(codec.rawValue, forKey: "codec") } }
    var hardware: Bool { didSet { defaults.set(hardware, forKey: "hardware") } }
    var prefix: String { didSet { defaults.set(prefix, forKey: "prefix") } }
    var suffix: String { didSet { defaults.set(suffix, forKey: "suffix") } }
    var outputFolder: URL { didSet { defaults.set(outputFolder.path, forKey: "outputFolder") } }

    var mode: AppMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var format: OutputFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    var gifSize: GIFSize { didSet { defaults.set(gifSize.rawValue, forKey: "gifSize") } }
    var gifRate: GIFRate { didSet { defaults.set(gifRate.rawValue, forKey: "gifRate") } }
    var copyStreams: Bool { didSet { defaults.set(copyStreams, forKey: "copyStreams") } }
    var nextToOriginal: Bool { didSet { defaults.set(nextToOriginal, forKey: "nextToOriginal") } }

    init() {
        let defaults = UserDefaults.standard
        engine = Engine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .handbrake
        codec = Codec(rawValue: defaults.string(forKey: "codec") ?? "") ?? .h264
        hardware = defaults.bool(forKey: "hardware")
        prefix = defaults.string(forKey: "prefix") ?? ""
        suffix = defaults.string(forKey: "suffix") ?? ""
        mode = AppMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .compress
        format = OutputFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .mp4H264
        gifSize = GIFSize(rawValue: defaults.object(forKey: "gifSize") as? Int ?? 480) ?? .medium
        gifRate = GIFRate(rawValue: defaults.object(forKey: "gifRate") as? Int ?? 15) ?? .fifteen
        copyStreams = defaults.bool(forKey: "copyStreams")
        nextToOriginal = defaults.bool(forKey: "nextToOriginal")
        if let path = defaults.string(forKey: "outputFolder") {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputFolder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
    }

    var options: EncodeOptions {
        // Apple's engine always runs on the hardware media engine.
        EncodeOptions(engine: engine, codec: codec, hardware: engine == .apple ? true : hardware)
    }

    var naming: OutputNaming {
        OutputNaming(prefix: prefix, suffix: suffix, folder: outputFolder, nextToOriginal: nextToOriginal)
    }

    var gifOptions: GIFOptions {
        GIFOptions(maxWidth: gifSize.maxWidth, fps: gifRate.rawValue)
    }

    /// Settings are captured when a queue starts (or when Finder queues a file),
    /// so changing them mid-run doesn't affect files already in line.
    func job(for mode: AppMode) -> QueueJob {
        switch mode {
        case .compress: return compressJob(options: options)
        case .convert: return convertJob(format: format, copy: copyStreams && format.canCopyStreams)
        }
    }

    func compressJob(options: EncodeOptions, naming: OutputNaming? = nil) -> QueueJob {
        QueueJob(fileExtension: "mp4", naming: naming ?? self.naming) { input, output, progress in
            switch options.engine {
            case .handbrake:
                try await HandBrakeEngine.encode(input: input, output: output, options: options, progress: progress)
            case .apple:
                try await AppleEngine.encode(input: input, output: output, codec: options.codec, progress: progress)
            }
        }
    }

    func convertJob(format: OutputFormat, copy: Bool, naming: OutputNaming? = nil) -> QueueJob {
        let gif = gifOptions
        return QueueJob(fileExtension: format.fileExtension, naming: naming ?? self.naming) { input, output, progress in
            try await ConvertEngine.convert(input: input, output: output, format: format, gif: gif,
                                            copyStreams: copy, progress: progress)
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolder
        panel.prompt = "Choose"
        panel.message = "Where should Squeeze save finished videos?"
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url }
    }

}

// MARK: - Queue

@MainActor
@Observable
final class QueueManager {
    let kind: AppMode
    var items: [QueueItem] = []
    var thumbnails: [URL: NSImage] = [:]
    var isDropTargeted = false
    private(set) var isRunning = false
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// Hooks for notifications, revealing files and quitting when done.
    @ObservationIgnored var onItemFinished: ((QueueItem) -> Void)?
    @ObservationIgnored var onIdle: (() -> Void)?

    init(kind: AppMode) { self.kind = kind }

    var hasWaiting: Bool { items.contains { $0.isWaiting } }
    var hasFinished: Bool { items.contains { $0.isFinished } }

    var summary: String {
        guard !items.isEmpty else { return "" }
        let done = items.filter { if case .done = $0.status { return true } else { return false } }.count
        return "\(done) of \(items.count) done"
    }

    func add(_ urls: [URL], job: QueueJob? = nil, label: String? = nil, fromFinder: Bool = false) {
        for url in Files.expand(urls) {
            let alreadyQueued = items.contains { $0.source == url && !$0.isFinished }
            if !alreadyQueued {
                var item = QueueItem(source: url, sourceSize: Files.size(of: url))
                item.job = job
                item.jobLabel = label
                item.fromFinder = fromFinder
                items.append(item)
                if thumbnails[url] == nil {
                    Task { [weak self] in
                        let image = await QueueRow.makeThumbnail(for: url)
                        self?.thumbnails[url] = image
                    }
                }
            }
        }
    }

    func addWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = Files.openPanelTypes
        panel.prompt = "Add"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id && !isEncoding($0) }
    }

    func retry(_ id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].status = .waiting }
    }

    func clearFinished() {
        items.removeAll { $0.isFinished }
    }

    func start(with settings: SettingsStore) {
        guard !isRunning, hasWaiting else { return }
        isRunning = true
        let defaultJob = settings.job(for: kind)
        runTask = Task { [weak self] in
            await self?.run(defaultJob)
        }
    }

    func stop() {
        runTask?.cancel()
    }

    // MARK: Private

    private func isEncoding(_ item: QueueItem) -> Bool {
        if case .encoding = item.status { return true }
        return false
    }

    private func set(_ id: UUID, _ status: QueueItem.Status) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].status = status }
    }

    private func setProgress(_ id: UUID, _ value: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .encoding = items[i].status else { return }
        items[i].status = .encoding(value)
    }

    private func run(_ defaultJob: QueueJob) async {
        let prefs = AppModel.shared.prefs
        // Keep the Mac awake while working (Settings → General).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: prefs.keepAwake ? [.userInitiated, .idleSystemSleepDisabled] : [.userInitiated],
            reason: "Squeeze is processing videos")
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            isRunning = false
            runTask = nil
            onIdle?()
        }

        while !Task.isCancelled, let item = items.first(where: { $0.isWaiting }) {
            let id = item.id
            let job = item.job ?? defaultJob
            let output = job.naming.url(for: item.source, fileExtension: job.fileExtension)
            set(id, .encoding(0))

            let report: @Sendable (Double) -> Void = { [weak self] value in
                Task { @MainActor [weak self] in self?.setProgress(id, value) }
            }

            do {
                try FileManager.default.createDirectory(
                    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await job.run(item.source, output, report)
                try Task.checkCancellation()
                set(id, .done(output, Files.size(of: output)))
            } catch {
                try? FileManager.default.removeItem(at: output)
                if Task.isCancelled || error is CancellationError {
                    set(id, .waiting)   // stopped: goes back in line for next Start
                } else {
                    set(id, .failed(error.localizedDescription))
                }
            }
            if let finished = items.first(where: { $0.id == id }), finished.isFinished {
                onItemFinished?(finished)
            }
        }

        if !Task.isCancelled && !hasWaiting && prefs.playSound {
            _ = NSApp.requestUserAttention(.informationalRequest)
            NSSound(named: "Glass")?.play()
        }
    }
}

// MARK: - Requests from the Finder extension

/// Handles squeeze:// links opened by the Finder extension.
/// Uses the Finder settings (Settings → Finder): save location, file names,
/// and whether to show the window or quietly work in the background.
@MainActor
enum FinderRequests {
    static func handle(_ url: URL) {
        let model = AppModel.shared
        let settings = model.settings
        let prefs = model.prefs
        guard let request = SqueezeLink.Request(url: url), !request.files.isEmpty else { return }

        // "Open in Squeeze" always shows the window and uses the app's own settings.
        if request.action == .open {
            MainWindow.shared.show()
            let queue = settings.mode == .compress ? model.compressQueue : model.convertQueue
            queue.add(request.files)
            return
        }

        let showWindow = prefs.finderShowsWindow
        if showWindow {
            MainWindow.shared.show()
        } else if !MainWindow.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)   // no Dock icon, no window
        }
        if prefs.finderNotify { Notifier.requestPermission() }

        let naming = prefs.finderNaming(for: request.action, appFolder: settings.outputFolder)

        switch request.action {
        case .open:
            break

        case .compress:
            if showWindow { settings.mode = .compress }
            var options = settings.options
            var label = "Finder"
            if let engine = request.engine.flatMap(Engine.init(rawValue:)),
               let codec = request.codec.flatMap(Codec.init(rawValue:)) {
                let hardware = engine == .apple ? true : (request.hardware ?? false)
                options = EncodeOptions(engine: engine, codec: codec, hardware: hardware)
                label = "\(engine.title) · \(codec.title)" + (engine == .handbrake && hardware ? " · Hardware" : "")
            }
            model.compressQueue.add(request.files, job: settings.compressJob(options: options, naming: naming),
                                    label: label, fromFinder: true)
            model.compressQueue.start(with: settings)

        case .convert:
            guard let format = request.format.flatMap(OutputFormat.init(rawValue:)) else { return }
            if showWindow { settings.mode = .convert }
            let copy = request.copyStreams && format.canCopyStreams
            model.convertQueue.add(request.files,
                                   job: settings.convertJob(format: format, copy: copy, naming: naming),
                                   label: copy ? "\(format.containerName) · same codecs" : format.title,
                                   fromFinder: true)
            model.convertQueue.start(with: settings)
        }
    }
}
