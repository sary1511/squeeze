import Foundation

/// Runs a bundled static FFmpeg. Used for formats HandBrake and Apple can't write
/// (AVI, WMV, FLV, MPEG-TS, 3GP, OGV, WebP, MP3, WAV, FLAC), for palette-optimised
/// GIFs, for fast container-only copies, and as a fallback when HandBrake is missing.
enum FFmpegEngine {

    /// Bundled copy first, then Homebrew.
    static var executableURL: URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            candidates.append(bundled)
        }
        candidates += ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].map { URL(fileURLWithPath: $0) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool { executableURL != nil }

    // MARK: - Probe

    struct ProbeInfo: Sendable {
        var duration: Double?
        var videoCodec: String?
        var hasVideo: Bool
        var hasAudio: Bool
    }

    /// `ffmpeg -i file` prints the stream list and exits with an error because
    /// no output was given. That's expected; we only read what it printed.
    static func probe(_ input: URL) async throws -> ProbeInfo {
        let result = try await execute(["-hide_banner", "-nostdin", "-i", input.path], onLine: nil)
        let text = result.stderr

        var duration: Double?
        if let m = firstMatch(#"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)"#, in: text), m.count == 3,
           let h = Double(m[0]), let min = Double(m[1]), let s = Double(m[2]) {
            duration = h * 3600 + min * 60 + s
        }
        let videoCodec = firstMatch(#"Stream #\d+:\d+[^:]*: Video: ([A-Za-z0-9_]+)"#, in: text)?.first
        return ProbeInfo(
            duration: duration,
            videoCodec: videoCodec,
            hasVideo: videoCodec != nil,
            hasAudio: text.contains(": Audio: "))
    }

    // MARK: - Run

    /// Runs `ffmpeg -i input <outputOptions> output` with live progress.
    static func run(
        input: URL,
        output: URL,
        outputOptions: [String],
        duration: Double?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: output)
        let args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats",
                    "-i", input.path] + outputOptions + [output.path]

        let total = (duration ?? 0) > 0 ? duration! : nil
        let result = try await execute(args) { line in
            // -progress prints key=value lines; out_time_us is microseconds.
            guard let total, line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms="),
                  let value = Double(line.split(separator: "=").last ?? ""), value >= 0 else { return }
            progress(min(value / 1_000_000 / total, 0.999))
        }

        try Task.checkCancellation()
        guard result.status == 0, Files.size(of: output) > 0 else {
            try? FileManager.default.removeItem(at: output)
            let reason = result.stderr
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last(where: { !$0.isEmpty })
            throw EncodeError(reason.map { "FFmpeg: \($0.prefix(220))" } ?? "FFmpeg stopped with code \(result.status).")
        }
        progress(1)
    }

    // MARK: - Arguments

    /// Container-only copy: no re-encode, so no quality loss and it takes seconds.
    static func copyOptions(for format: OutputFormat, info: ProbeInfo) -> [String] {
        var args = ["-map", "0:v:0?", "-map", "0:a?"]
        if format.fileExtension == "mkv" { args += ["-map", "0:s?"] }
        args += ["-c", "copy"]
        switch format.fileExtension {
        case "mp4", "m4v", "mov":
            args += ["-movflags", "+faststart"]
            if info.videoCodec == "hevc" { args += ["-tag:v", "hvc1"] }   // QuickTime-compatible HEVC
        case "ts":
            args += ["-f", "mpegts"]
        default:
            break
        }
        return args
    }

    /// Full conversion options for a format, or nil if FFmpeg isn't the right tool.
    static func convertOptions(for format: OutputFormat, gif: GIFOptions) -> [String]? {
        let even = ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]       // same size; encoders need even numbers
        let firstVideoAllAudio = ["-map", "0:v:0", "-map", "0:a:0?"]
        let x264 = ["-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p"]
        let x265 = ["-c:v", "libx265", "-preset", "fast", "-crf", "22", "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1"]
        let av1 = ["-c:v", "libsvtav1", "-preset", "6", "-crf", "35", "-pix_fmt", "yuv420p10le"]
        let vp9 = ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-row-mt", "1"]
        let aac = ["-c:a", "aac", "-b:a", "160k", "-ac", "2"]
        let opus = ["-c:a", "libopus", "-b:a", "160k", "-ac", "2"]
        let faststart = ["-movflags", "+faststart"]

        switch format {
        // Same results as the HandBrake versions, used when HandBrakeCLI is missing.
        case .mp4H264, .m4v: return firstVideoAllAudio + even + x264 + aac + faststart
        case .mp4H265:       return firstVideoAllAudio + even + x265 + aac + faststart
        case .mp4AV1:        return firstVideoAllAudio + even + av1 + aac + faststart
        case .mkvH264:       return firstVideoAllAudio + even + x264 + aac
        case .mkvH265:       return firstVideoAllAudio + even + Array(x265.dropLast(2)) + aac   // no hvc1 tag in MKV
        case .webmVP9:       return firstVideoAllAudio + vp9 + opus
        case .webmAV1:       return firstVideoAllAudio + even + av1 + opus

        // FFmpeg-only formats.
        case .avi:
            return firstVideoAllAudio + even + ["-c:v", "mpeg4", "-vtag", "xvid", "-q:v", "3",
                                                "-c:a", "libmp3lame", "-q:a", "2", "-ac", "2"]
        case .wmv:
            return firstVideoAllAudio + even + ["-c:v", "wmv2", "-q:v", "3", "-c:a", "wmav2", "-b:a", "192k", "-ac", "2"]
        case .flv:
            return firstVideoAllAudio + even + x264 + ["-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-ac", "2"]
        case .ts:
            return firstVideoAllAudio + even + x264 + aac + ["-f", "mpegts"]
        case .threeGP:
            return firstVideoAllAudio + even
                + ["-c:v", "libx264", "-profile:v", "baseline", "-preset", "fast", "-crf", "23", "-pix_fmt", "yuv420p",
                   "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-ac", "2"]
        case .ogv:
            return firstVideoAllAudio + ["-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "5", "-ac", "2"]

        case .gif:
            let scale = gif.maxWidth.map { ",scale=w='min(\($0),iw)':h=-1:flags=lanczos" } ?? ""
            let graph = "[0:v]fps=\(gif.fps)\(scale),split[a][b];[a]palettegen=stats_mode=diff[p];"
                + "[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
            return ["-filter_complex", graph, "-an", "-loop", "0"]
        case .webpAnimated:
            let scale = gif.maxWidth.map { ",scale=w='min(\($0),iw)':h=-1:flags=lanczos" } ?? ""
            return ["-map", "0:v:0", "-vf", "fps=\(gif.fps)\(scale)", "-c:v", "libwebp", "-q:v", "75",
                    "-compression_level", "4", "-loop", "0", "-an"]

        case .mp3:  return ["-vn", "-map", "0:a:0", "-c:a", "libmp3lame", "-q:a", "2"]
        case .wav:  return ["-vn", "-map", "0:a:0", "-c:a", "pcm_s16le"]
        case .flac: return ["-vn", "-map", "0:a:0", "-c:a", "flac"]

        case .movH264, .movHEVC, .movProRes, .m4a:
            return nil   // Apple writes these (hardware encoders, native ProRes)
        }
    }

    /// High-quality temporary MP4 that Apple's frameworks can read.
    static let intermediateOptions = ["-map", "0:v:0", "-map", "0:a:0?",
                                      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                                      "-c:v", "libx264", "-preset", "veryfast", "-crf", "16", "-pix_fmt", "yuv420p",
                                      "-c:a", "aac", "-b:a", "256k", "-ac", "2"]

    // MARK: - Process plumbing

    private struct Result {
        var status: Int32
        var stderr: String
    }

    private static func execute(_ args: [String], onLine: (@Sendable (String) -> Void)?) async throws -> Result {
        guard let exe = executableURL else {
            throw EncodeError("FFmpeg wasn't found. Rebuild Squeeze with build.sh, or run “brew install ffmpeg”.")
        }

        let process = Process()
        process.executableURL = exe
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let errors = TextBuffer()
        let lines = LineSplitter()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let onLine else { return }
            for line in lines.feed(data) { onLine(line) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            errors.append(handle.availableData)
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { finished in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    errors.append(stderr.fileHandleForReading.readDataToEndOfFile())
                    continuation.resume(returning: finished.terminationStatus)
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
        return Result(status: status, stderr: errors.text)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}

private final class TextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 256_000 { data = data.suffix(128_000) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Splits a byte stream into complete lines.
private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""

    func feed(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending += String(decoding: data, as: UTF8.self)
        var parts = pending.components(separatedBy: "\n")
        pending = parts.removeLast()
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
