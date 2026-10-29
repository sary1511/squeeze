import AVFoundation
import Foundation

/// Convert tab. Picks the right tool for each format:
///  • "Keep original codecs" → FFmpeg container-only copy (falls back to a full conversion)
///  • MP4 / MKV / WebM / M4V → HandBrake (FFmpeg if HandBrake is missing)
///  • AVI, WMV, FLV, TS, 3GP, OGV, WebP, MP3, WAV, FLAC → FFmpeg
///  • GIF → FFmpeg palette GIF (Apple's ImageIO if FFmpeg is missing)
///  • MOV, ProRes, M4A → Apple frameworks; when macOS can't read the source,
///    HandBrake or FFmpeg first makes a high-quality temporary MP4.
enum ConvertEngine {

    static func convert(
        input: URL,
        output: URL,
        format: OutputFormat,
        gif: GIFOptions,
        copyStreams: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {

        // 1. Container-only copy.
        if copyStreams, format.canCopyStreams, FFmpegEngine.isAvailable {
            do {
                let info = try await FFmpegEngine.probe(input)
                try await FFmpegEngine.run(
                    input: input, output: output,
                    outputOptions: FFmpegEngine.copyOptions(for: format, info: info),
                    duration: info.duration, progress: progress)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Codecs don't fit this container (e.g. PCM audio into MP4): convert properly instead.
                try? FileManager.default.removeItem(at: output)
                progress(0)
            }
        }

        switch format.backend {
        case .handbrake:
            if HandBrakeEngine.executableURL != nil {
                try await HandBrakeEngine.run(
                    HandBrakeEngine.convertArguments(input: input, output: output, format: format),
                    output: output, progress: progress)
            } else {
                try await runFFmpeg(input: input, output: output, format: format, gif: gif, progress: progress)
            }

        case .ffmpeg:
            if format == .gif && !FFmpegEngine.isAvailable {
                try await viaApple(input: input, output: output, format: format, gif: gif, progress: progress)
            } else {
                try await runFFmpeg(input: input, output: output, format: format, gif: gif, progress: progress)
            }

        case .apple:
            try await viaApple(input: input, output: output, format: format, gif: gif, progress: progress)
        }
    }

    // MARK: - FFmpeg

    private static func runFFmpeg(
        input: URL, output: URL, format: OutputFormat, gif: GIFOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let options = FFmpegEngine.convertOptions(for: format, gif: gif) else {
            throw EncodeError("\(format.title) can't be made with FFmpeg.")
        }
        let info = try await FFmpegEngine.probe(input)
        if format.isAudioOnly && !info.hasAudio { throw EncodeError("This file has no audio track.") }
        if !format.isAudioOnly && !info.hasVideo { throw EncodeError("This file has no video track.") }
        try await FFmpegEngine.run(input: input, output: output, outputOptions: options,
                                   duration: info.duration, progress: progress)
    }

    // MARK: - Apple (with a temporary MP4 when macOS can't read the source)

    private static func viaApple(
        input: URL, output: URL, format: OutputFormat, gif: GIFOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let canMakeIntermediate = HandBrakeEngine.executableURL != nil || FFmpegEngine.isAvailable

        if await AppleEngine.canRead(input, needsVideo: !format.isAudioOnly) {
            do {
                try await writeWithApple(input: input, output: output, format: format, gif: gif, progress: progress)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Readable but not decodable (an unusual codec inside a MOV, say).
                if !canMakeIntermediate { throw error }
                try? FileManager.default.removeItem(at: output)
            }
        }

        guard canMakeIntermediate else {
            throw EncodeError("macOS can't read this file by itself, and neither HandBrakeCLI nor FFmpeg was found to convert it.")
        }

        let tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Squeeze-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }
        let intermediate = tempFolder.appendingPathComponent("intermediate.mp4")
        let firstHalf: @Sendable (Double) -> Void = { progress($0 * 0.5) }

        if HandBrakeEngine.executableURL != nil {
            let args = HandBrakeEngine.intermediateArguments(
                input: input, output: intermediate, gif: format == .gif ? gif : nil)
            try await HandBrakeEngine.run(args, output: intermediate, progress: firstHalf)
        } else {
            let info = try await FFmpegEngine.probe(input)
            try await FFmpegEngine.run(input: input, output: intermediate,
                                       outputOptions: FFmpegEngine.intermediateOptions,
                                       duration: info.duration, progress: firstHalf)
        }
        try Task.checkCancellation()
        try await writeWithApple(input: intermediate, output: output, format: format, gif: gif) {
            progress(0.5 + $0 * 0.5)
        }
    }

    private static func writeWithApple(
        input: URL,
        output: URL,
        format: OutputFormat,
        gif: GIFOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch format {
        case .movH264:
            try await AppleEngine.transcode(
                input: input, output: output, fileType: .mov,
                video: AppleVideo(kind: .h264, bitsPerPixel: 0.15, maxSourceRatio: 1.2),
                audio: .aac(bitrate: 192_000), progress: progress)
        case .movHEVC:
            try await AppleEngine.transcode(
                input: input, output: output, fileType: .mov,
                video: AppleVideo(kind: .hevc, bitsPerPixel: 0.10, maxSourceRatio: 1.2),
                audio: .aac(bitrate: 192_000), progress: progress)
        case .movProRes:
            try await AppleEngine.transcode(
                input: input, output: output, fileType: .mov,
                video: AppleVideo(kind: .proRes422),
                audio: .pcm, progress: progress)
        case .m4a:
            try await AppleEngine.transcode(
                input: input, output: output, fileType: .m4a,
                video: nil, audio: .aac(bitrate: 256_000), progress: progress)
        case .gif:
            try await GIFEngine.encode(input: input, output: output, options: gif, progress: progress)
        default:
            throw EncodeError("\(format.title) isn't written by Apple's frameworks.")
        }
    }
}
