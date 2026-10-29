import Foundation

/// Runs HandBrake's own engine (HandBrakeCLI). Every job starts from HandBrake's
/// default "Fast 1080p30" preset, minus the 1080p cap, the 30 fps cap and auto-crop.
enum HandBrakeEngine {

    /// Bundled copy first, then common Homebrew / manual install locations.
    static var executableURL: URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "HandBrakeCLI", withExtension: nil) {
            candidates.append(bundled)
        }
        candidates += [
            "/opt/homebrew/bin/HandBrakeCLI",
            "/usr/local/bin/HandBrakeCLI",
            "/Applications/HandBrakeCLI",
        ].map { URL(fileURLWithPath: $0) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: Arguments

    /// Shared by every job: start from HandBrake's default preset so every
    /// unlisted setting (filters, audio track selection…) is what HandBrake does,
    /// then keep the source's size and frame rate and turn off auto-crop.
    private static func base(input: URL, output: URL, container: String, maxWidth: Int? = nil) -> [String] {
        let limit = maxWidth.map { String($0) } ?? "16384"
        return [
            "-i", input.path,
            "-o", output.path,
            "--preset", "Fast 1080p30",
            "--format", container,
            "--maxWidth", limit,          // lifts the preset's 1080p ceiling (never upscales)
            "--maxHeight", "16384",
            "--crop", "0:0:0:0",          // no cropping
            "--vfr",                      // same frame rate as the source
            "--encoder-level", "auto",
        ]
    }

    private static func video(_ encoder: String, preset: String, profile: String, quality: String) -> [String] {
        ["--encoder", encoder, "--encoder-preset", preset, "--encoder-profile", profile, "--quality", quality]
    }

    private static let aac = ["--aencoder", "av_aac", "--ab", "160", "--mixdown", "stereo"]
    private static let opus = ["--aencoder", "opus", "--ab", "160", "--mixdown", "stereo"]

    /// Compress tab.
    static func arguments(input: URL, output: URL, options: EncodeOptions) -> [String] {
        var args = base(input: input, output: output, container: "av_mp4") + aac
        switch (options.codec, options.hardware) {
        case (.h264, false): args += video("x264", preset: "fast", profile: "main", quality: "22")
        case (.h265, false): args += video("x265_10bit", preset: "fast", profile: "main10", quality: "22")
        case (.h264, true):  args += video("vt_h264", preset: "speed", profile: "auto", quality: "60")
        case (.h265, true):  args += video("vt_h265_10bit", preset: "speed", profile: "auto", quality: "60")
        }
        return args
    }

    /// Convert tab (MP4 / MKV / WebM / M4V). Values follow HandBrake's own presets.
    static func convertArguments(input: URL, output: URL, format: OutputFormat) -> [String] {
        let x264 = video("x264", preset: "fast", profile: "high", quality: "20")
        let x265 = video("x265_10bit", preset: "fast", profile: "main10", quality: "22")
        let av1 = video("svt_av1_10bit", preset: "6", profile: "main", quality: "34.5")
        let vp9 = video("vp9", preset: "medium", profile: "auto", quality: "30")

        switch format {
        case .mp4H264, .m4v: return base(input: input, output: output, container: "av_mp4") + x264 + aac
        case .mp4H265:       return base(input: input, output: output, container: "av_mp4") + x265 + aac
        case .mp4AV1:        return base(input: input, output: output, container: "av_mp4") + av1 + aac
        case .mkvH264:       return base(input: input, output: output, container: "av_mkv") + x264 + aac
        case .mkvH265:       return base(input: input, output: output, container: "av_mkv") + x265 + aac
        case .webmVP9:       return base(input: input, output: output, container: "av_webm") + vp9 + opus
        case .webmAV1:       return base(input: input, output: output, container: "av_webm") + av1 + opus
        default:
            // Written by Apple or FFmpeg; HandBrake only makes an intermediate for these.
            return intermediateArguments(input: input, output: output, gif: nil)
        }
    }

    /// High-quality temporary MP4 for files macOS can't read on its own (MKV, WebM, AVI…),
    /// so Apple's frameworks can then write MOV, ProRes, GIF or M4A from it.
    /// For GIFs it's already scaled down, silent and only as long as the GIF.
    static func intermediateArguments(input: URL, output: URL, gif: GIFOptions?) -> [String] {
        if let gif {
            return base(input: input, output: output, container: "av_mp4", maxWidth: gif.maxWidth)
                + video("x264", preset: "veryfast", profile: "high", quality: "18")
                + ["--audio", "none", "--stop-at", "seconds:\(Int(GIFEngine.maxSeconds) + 1)"]
        }
        return base(input: input, output: output, container: "av_mp4")
            + video("x264", preset: "veryfast", profile: "high", quality: "16")
            + ["--aencoder", "av_aac", "--ab", "256", "--mixdown", "stereo"]
    }

    // MARK: Running

    static func encode(
        input: URL,
        output: URL,
        options: EncodeOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await run(arguments(input: input, output: output, options: options), output: output, progress: progress)
    }

    static func run(
        _ arguments: [String],
        output: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let exe = executableURL else {
            throw EncodeError("HandBrakeCLI wasn't found. Rebuild Squeeze with build.sh, or run “brew install handbrake”.")
        }

        let process = Process()
        process.executableURL = exe
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let log = LogBuffer()
        let parser = ProgressParser()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if let value = parser.parse(text) { progress(value) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            log.append(handle.availableData)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { finished in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    if finished.terminationStatus == 0 {
                        continuation.resume()
                    } else if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        let reason = log.lastErrorLine() ?? "HandBrake stopped with code \(finished.terminationStatus)."
                        continuation.resume(throwing: EncodeError(reason))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        try Task.checkCancellation()

        // HandBrakeCLI can exit 0 without writing anything (e.g. no valid title found).
        guard Files.size(of: output) > 0 else {
            throw EncodeError(log.lastErrorLine() ?? "HandBrake couldn't read this file.")
        }
        progress(1)
    }
}

// MARK: - Helpers

/// Parses lines like "Encoding: task 1 of 1, 42.17 % (95.3 fps, avg 97.1 fps, ETA 00m31s)".
private final class ProgressParser: @unchecked Sendable {
    private let regex = try! NSRegularExpression(pattern: #"task (\d+) of (\d+), ([0-9]+(?:\.[0-9]+)?) %"#)

    func parse(_ text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let taskRange = Range(match.range(at: 1), in: text),
              let countRange = Range(match.range(at: 2), in: text),
              let pctRange = Range(match.range(at: 3), in: text),
              let task = Double(text[taskRange]),
              let count = Double(text[countRange]), count > 0,
              let pct = Double(text[pctRange])
        else { return nil }
        return min(max(((task - 1) + pct / 100) / count, 0), 1)
    }
}

/// Keeps the tail of HandBrake's log so a useful error can be shown.
private final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 64_000 { data = data.suffix(32_000) }
    }

    func lastErrorLine() -> String? {
        lock.lock(); defer { lock.unlock() }
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let line = lines.last(where: { $0.localizedCaseInsensitiveContains("error") }) ?? lines.last
        return line.map { String($0.prefix(240)) }
    }
}
