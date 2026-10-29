import Foundation
import UniformTypeIdentifiers

// MARK: - Tabs

enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case compress, convert
    var id: String { rawValue }
    var title: String { self == .compress ? "Compress" : "Convert" }
    var emptyTitle: String { self == .compress ? "Drop Videos to Compress" : "Drop Videos to Convert" }
    var emptyMessage: String {
        self == .compress
            ? "Any format in, MP4 out. Same size, smaller file."
            : "Turn any video into MP4, MKV, WebM, MOV, AVI, GIF, MP3 and more."
    }
    var actionTitle: String { self == .compress ? "Compress" : "Convert" }
}

// MARK: - Convert formats

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case mp4H264, mp4H265, mp4AV1
    case mkvH264, mkvH265
    case webmVP9, webmAV1
    case movH264, movHEVC, movProRes
    case gif, webpAnimated
    case avi, wmv, flv, ts, threeGP, ogv, m4v
    case m4a, mp3, wav, flac

    var id: String { rawValue }

    /// Which tool writes this format.
    enum Backend: Sendable { case handbrake, apple, ffmpeg }

    static let groups = ["MP4", "MKV", "WebM", "QuickTime", "Animated", "More video", "Audio"]

    var group: String {
        switch self {
        case .mp4H264, .mp4H265, .mp4AV1: return "MP4"
        case .mkvH264, .mkvH265: return "MKV"
        case .webmVP9, .webmAV1: return "WebM"
        case .movH264, .movHEVC, .movProRes: return "QuickTime"
        case .gif, .webpAnimated: return "Animated"
        case .avi, .wmv, .flv, .ts, .threeGP, .ogv, .m4v: return "More video"
        case .m4a, .mp3, .wav, .flac: return "Audio"
        }
    }

    var title: String {
        switch self {
        case .mp4H264: return "MP4 · H.264"
        case .mp4H265: return "MP4 · H.265"
        case .mp4AV1: return "MP4 · AV1"
        case .mkvH264: return "MKV · H.264"
        case .mkvH265: return "MKV · H.265"
        case .webmVP9: return "WebM · VP9"
        case .webmAV1: return "WebM · AV1"
        case .movH264: return "MOV · H.264"
        case .movHEVC: return "MOV · HEVC"
        case .movProRes: return "MOV · ProRes 422"
        case .gif: return "GIF"
        case .webpAnimated: return "WebP · Animated"
        case .avi: return "AVI · Xvid"
        case .wmv: return "WMV"
        case .flv: return "FLV"
        case .ts: return "MPEG-TS"
        case .threeGP: return "3GP"
        case .ogv: return "OGV · Theora"
        case .m4v: return "M4V · H.264"
        case .m4a: return "M4A · AAC"
        case .mp3: return "MP3"
        case .wav: return "WAV"
        case .flac: return "FLAC"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4H264, .mp4H265, .mp4AV1: return "mp4"
        case .mkvH264, .mkvH265: return "mkv"
        case .webmVP9, .webmAV1: return "webm"
        case .movH264, .movHEVC, .movProRes: return "mov"
        case .gif: return "gif"
        case .webpAnimated: return "webp"
        case .avi: return "avi"
        case .wmv: return "wmv"
        case .flv: return "flv"
        case .ts: return "ts"
        case .threeGP: return "3gp"
        case .ogv: return "ogv"
        case .m4v: return "m4v"
        case .m4a: return "m4a"
        case .mp3: return "mp3"
        case .wav: return "wav"
        case .flac: return "flac"
        }
    }

    /// MP4 / MKV / WebM / M4V: HandBrake (FFmpeg if HandBrake is missing).
    /// MOV, ProRes, M4A: Apple. GIF: FFmpeg (Apple if FFmpeg is missing). The rest: FFmpeg.
    var backend: Backend {
        switch self {
        case .mp4H264, .mp4H265, .mp4AV1, .mkvH264, .mkvH265, .webmVP9, .webmAV1, .m4v: return .handbrake
        case .movH264, .movHEVC, .movProRes, .m4a: return .apple
        case .gif, .webpAnimated, .avi, .wmv, .flv, .ts, .threeGP, .ogv, .mp3, .wav, .flac: return .ffmpeg
        }
    }

    var isAudioOnly: Bool { [.m4a, .mp3, .wav, .flac].contains(self) }
    var isAnimatedImage: Bool { self == .gif || self == .webpAnimated }

    /// Formats where "Keep original codecs" (container-only copy) makes sense.
    var canCopyStreams: Bool {
        switch self {
        case .mp4H264, .mp4H265, .mp4AV1, .mkvH264, .mkvH265, .webmVP9, .webmAV1,
             .movH264, .movHEVC, .m4v, .ts:
            return true
        default:
            return false
        }
    }

    /// Short label for the container, used when copying streams.
    var containerName: String {
        switch fileExtension {
        case "ts": return "MPEG-TS"
        default: return fileExtension.uppercased()
        }
    }

    /// The tool(s) this format needs that aren't installed, or nil if it can run.
    var missingTool: String? {
        switch backend {
        case .handbrake:
            return HandBrakeEngine.executableURL == nil && !FFmpegEngine.isAvailable ? "HandBrakeCLI or FFmpeg" : nil
        case .ffmpeg:
            if self == .gif { return nil }   // falls back to Apple's GIF writer
            return FFmpegEngine.isAvailable ? nil : "FFmpeg"
        case .apple:
            return nil
        }
    }

    var summary: String {
        switch self {
        case .mp4H264: return "x264 · RF 20 · AAC 160 kbps. Plays everywhere."
        case .mp4H265: return "x265 10-bit · RF 22 · AAC 160 kbps. About half the size of H.264."
        case .mp4AV1: return "SVT-AV1 10-bit · RF 34.5 · AAC 160 kbps. Smallest files, slower to encode."
        case .mkvH264: return "x264 · RF 20 · AAC 160 kbps in a Matroska container."
        case .mkvH265: return "x265 10-bit · RF 22 · AAC 160 kbps in a Matroska container."
        case .webmVP9: return "VP9 · RF 30 · Opus 160 kbps. Made for the web."
        case .webmAV1: return "SVT-AV1 10-bit · RF 34.5 · Opus 160 kbps. Made for the web."
        case .movH264: return "H.264 · AAC in QuickTime, on the Apple Silicon media engine."
        case .movHEVC: return "HEVC · AAC in QuickTime, on the Apple Silicon media engine."
        case .movProRes: return "ProRes 422 · PCM audio. For editing in Final Cut or Premiere. Large files."
        case .gif:
            return FFmpegEngine.isAvailable
                ? "Animated GIF with an optimised colour palette. Loops forever, no sound."
                : "Animated GIF from the first \(Int(GIFEngine.maxSeconds)) seconds. Loops forever, no sound."
        case .webpAnimated: return "Animated WebP. Much smaller than GIF with full colour. Loops forever, no sound."
        case .avi: return "MPEG-4 Part 2 (Xvid) · MP3 audio. For older players and TVs."
        case .wmv: return "Windows Media Video 8 · WMA audio. For older Windows apps."
        case .flv: return "H.264 · AAC in Flash Video."
        case .ts: return "H.264 · AAC in an MPEG transport stream. For broadcast and set-top boxes."
        case .threeGP: return "H.264 Baseline · AAC 96 kbps. For old phones."
        case .ogv: return "Theora · Vorbis in Ogg. Fully open formats."
        case .m4v: return "x264 · RF 20 · AAC 160 kbps. Apple TV and iTunes style."
        case .m4a: return "Audio track only · AAC 256 kbps."
        case .mp3: return "Audio track only · MP3 VBR ~190 kbps."
        case .wav: return "Audio track only · uncompressed 16-bit PCM."
        case .flac: return "Audio track only · lossless FLAC."
        }
    }
}

enum GIFSize: Int, CaseIterable, Identifiable, Sendable {
    case small = 320, medium = 480, large = 640, original = 0
    var id: Int { rawValue }
    var title: String { self == .original ? "Original" : "\(rawValue)" }
    var maxWidth: Int? { self == .original ? nil : rawValue }
}

enum GIFRate: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10, fifteen = 15, twentyFour = 24
    var id: Int { rawValue }
    var title: String { "\(rawValue)" }
}

struct GIFOptions: Sendable {
    var maxWidth: Int?
    var fps: Int
}

// MARK: - Output naming (snapshot taken when a queue starts)

struct OutputNaming: Sendable {
    var prefix: String
    var suffix: String
    var folder: URL
    /// Save next to the original instead of in `folder`.
    var nextToOriginal = false

    func name(for baseName: String) -> String {
        clean(prefix) + baseName + clean(suffix)
    }

    /// prefix + original name + suffix + extension, never overwriting anything.
    func url(for source: URL, fileExtension: String) -> URL {
        let base = self.name(for: source.deletingPathExtension().lastPathComponent)
        let folder = nextToOriginal ? source.deletingLastPathComponent() : self.folder
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path)
                || candidate.standardizedFileURL == source.standardizedFileURL {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(fileExtension)
            n += 1
        }
        return candidate
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}

/// What a queue does to each file.
struct QueueJob: Sendable {
    let fileExtension: String
    let naming: OutputNaming
    let run: @Sendable (_ input: URL, _ output: URL, _ progress: @escaping @Sendable (Double) -> Void) async throws -> Void
}

// MARK: - Compress options

enum Engine: String, CaseIterable, Identifiable, Sendable {
    case handbrake, apple
    var id: String { rawValue }
    var title: String { self == .handbrake ? "HandBrake" : "Apple" }
}

enum Codec: String, CaseIterable, Identifiable, Sendable {
    case h264, h265
    var id: String { rawValue }
    var title: String { self == .h264 ? "H.264" : "H.265" }
}

struct EncodeOptions: Sendable {
    var engine: Engine
    var codec: Codec
    var hardware: Bool

    /// One-line, human readable summary of what will actually run.
    var summary: String {
        switch engine {
        case .handbrake:
            switch (codec, hardware) {
            case (.h264, false): return "x264 · RF 22 · fast · AAC 160 kbps — HandBrake's default"
            case (.h265, false): return "x265 10-bit · RF 22 · fast · AAC 160 kbps"
            case (.h264, true):  return "VideoToolbox H.264 · CQ 60 · AAC 160 kbps"
            case (.h265, true):  return "VideoToolbox H.265 10-bit · CQ 60 · AAC 160 kbps"
            }
        case .apple:
            return "AVFoundation \(codec.title) · Apple Silicon media engine · AAC 160 kbps"
        }
    }
}

// MARK: - Queue item

struct QueueItem: Identifiable, Equatable {
    static func == (a: QueueItem, b: QueueItem) -> Bool {
        a.id == b.id && a.status == b.status
    }

    enum Status: Equatable {
        case waiting
        case encoding(Double)
        case done(URL, Int64)
        case failed(String)
    }

    let id = UUID()
    let source: URL
    let sourceSize: Int64
    var status: Status = .waiting
    /// Set for items queued from Finder with their own settings ("Convert To → GIF").
    /// Otherwise the queue's current settings are used.
    var job: QueueJob? = nil
    var jobLabel: String? = nil
    var fromFinder = false

    var isWaiting: Bool { status == .waiting }
    var isFinished: Bool {
        switch status {
        case .done, .failed: return true
        default: return false
        }
    }
}

// MARK: - Errors

struct EncodeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - File helpers

enum Files {
    /// Extensions macOS doesn't always map to a video UTType but HandBrake reads fine.
    static var extraVideoExtensions: Set<String> { SqueezeLink.videoExtensions }

    static var openPanelTypes: [UTType] {
        [.movie, .audiovisualContent] + extraVideoExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func isVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if extraVideoExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .audiovisualContent) { return true }
        return false
    }

    static func size(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Expands dropped folders into the video files they contain.
    static func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let child = enumerator?.nextObject() as? URL {
                    if isVideo(child) { result.append(child) }
                }
            } else if isVideo(url) {
                result.append(url)
            }
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
