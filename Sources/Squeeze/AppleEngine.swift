import AVFoundation
import Foundation

/// How Apple's encoder should write the video track.
struct AppleVideo: Sendable {
    enum Kind: Sendable { case h264, hevc, proRes422 }
    var kind: Kind
    /// Target bits per pixel per frame (ignored for ProRes).
    var bitsPerPixel: Double = 0.09
    /// Never exceed this multiple of the source bitrate (ignored for ProRes).
    var maxSourceRatio: Double = 0.8
}

enum AppleAudio: Sendable {
    case aac(bitrate: Int)
    case pcm
}

/// Re-encodes with AVFoundation on Apple's hardware media engine.
/// Same width, height, orientation and frame rate as the source.
enum AppleEngine {

    /// True when AVFoundation can open the file and finds the track we need.
    static func canRead(_ url: URL, needsVideo: Bool) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isReadable)) == true else { return false }
        let type: AVMediaType = needsVideo ? .video : .audio
        let tracks = (try? await asset.loadTracks(withMediaType: type)) ?? []
        return !tracks.isEmpty
    }

    /// Compress tab: MP4 with H.264 or H.265.
    static func encode(
        input: URL,
        output: URL,
        codec: Codec,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let video = codec == .h264
            ? AppleVideo(kind: .h264, bitsPerPixel: 0.09, maxSourceRatio: 0.8)
            : AppleVideo(kind: .hevc, bitsPerPixel: 0.06, maxSourceRatio: 0.8)
        try await transcode(input: input, output: output, fileType: .mp4,
                            video: video, audio: .aac(bitrate: 160_000), progress: progress)
    }

    /// General reader → writer transcode. Pass `video: nil` for an audio-only file.
    static func transcode(
        input: URL,
        output: URL,
        fileType: AVFileType,
        video: AppleVideo?,
        audio: AppleAudio,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)

        guard try await asset.load(.isReadable) else {
            throw EncodeError("macOS can't read this file directly.")
        }
        var videoTrack: AVAssetTrack?
        if video != nil { videoTrack = try await asset.loadTracks(withMediaType: .video).first }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        if video != nil && videoTrack == nil { throw EncodeError("No video track found.") }
        if video == nil && audioTrack == nil { throw EncodeError("This file has no audio track.") }

        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = fileType != .mov

        // MARK: Video
        var videoPair: (AVAssetWriterInput, AVAssetReaderTrackOutput)?
        if let video, let videoTrack {
            let (naturalSize, transform, nominalFPS, dataRate) = try await videoTrack.load(
                .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate)

            // Encoders need even dimensions.
            let width = max(Int(naturalSize.width.rounded()) & ~1, 2)
            let height = max(Int(naturalSize.height.rounded()) & ~1, 2)
            let fps = nominalFPS > 0 ? Double(nominalFPS) : 30

            let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: video.kind == .proRes422
                    ? kCVPixelFormatType_422YpCbCr8
                    : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
            readerOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(readerOutput) else { throw EncodeError("Couldn't decode the video track.") }
            reader.add(readerOutput)

            var settings: [String: Any] = [AVVideoWidthKey: width, AVVideoHeightKey: height]
            switch video.kind {
            case .proRes422:
                settings[AVVideoCodecKey] = AVVideoCodecType.proRes422
            case .h264, .hevc:
                // AVFoundation has no constant-quality (RF) mode for H.264/H.265,
                // so target a bitrate from the frame size, capped against the source.
                var bitrate = Double(width * height) * fps * video.bitsPerPixel
                if dataRate > 0 { bitrate = min(bitrate, Double(dataRate) * video.maxSourceRatio) }
                bitrate = max(bitrate, 400_000)

                var compression: [String: Any] = [
                    AVVideoAverageBitRateKey: Int(bitrate),
                    AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
                    AVVideoMaxKeyFrameIntervalKey: Int((fps * 10).rounded()),
                ]
                if video.kind == .h264 {
                    compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
                    compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
                }
                settings[AVVideoCodecKey] = video.kind == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc
                settings[AVVideoCompressionPropertiesKey] = compression
            }

            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            writerInput.transform = transform          // keeps portrait videos portrait
            writerInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(writerInput) else { throw EncodeError("This video can't be written in that format.") }
            writer.add(writerInput)
            videoPair = (writerInput, readerOutput)
        }

        // MARK: Audio
        var audioPair: (AVAssetWriterInput, AVAssetReaderTrackOutput)?
        if let audioTrack {
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            readerOutput.alwaysCopiesSampleData = false

            let writerSettings: [String: Any]
            switch audio {
            case .aac(let bitrate):
                writerSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: bitrate,
                ]
            case .pcm:
                var layout = AudioChannelLayout()
                layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
                writerSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                    AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
                ]
            }
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            writerInput.expectsMediaDataInRealTime = false

            if reader.canAdd(readerOutput), writer.canAdd(writerInput) {
                reader.add(readerOutput)
                writer.add(writerInput)
                audioPair = (writerInput, readerOutput)
            } else if video == nil {
                throw EncodeError("Couldn't decode the audio track.")
            }
        }

        // MARK: Transcode
        guard reader.startReading() else {
            throw reader.error ?? EncodeError("Couldn't start reading the file.")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? EncodeError("Couldn't start writing the file.")
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = max(duration.seconds, 0.001)
        let flag = CancelFlag()
        let report: (Double) -> Void = { pts in progress(min(pts / totalSeconds, 0.999)) }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                if let pair = videoPair {
                    pump(input: pair.0, output: pair.1, label: "squeeze.video", group: group, flag: flag, onSample: report)
                }
                if let pair = audioPair {
                    pump(input: pair.0, output: pair.1, label: "squeeze.audio", group: group, flag: flag,
                         onSample: videoPair == nil ? report : nil)
                }
                group.notify(queue: .global()) { continuation.resume() }
            }
        } onCancel: {
            flag.cancel()
        }

        if flag.isCancelled || Task.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw reader.error ?? EncodeError("Reading the source failed.")
        }
        if writer.status == .failed {
            reader.cancelReading()
            try? FileManager.default.removeItem(at: output)
            throw writer.error ?? EncodeError("Writing the file failed.")
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw writer.error ?? EncodeError("Couldn't finish the file.")
        }
        progress(1)
    }

    /// Feeds one track from the reader into the writer on its own queue.
    private static func pump(
        input: AVAssetWriterInput,
        output: AVAssetReaderOutput,
        label: String,
        group: DispatchGroup,
        flag: CancelFlag,
        onSample: ((Double) -> Void)?
    ) {
        group.enter()
        let queue = DispatchQueue(label: label)
        let state = PumpState()

        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData && !state.finished {
                guard !flag.isCancelled, let sample = output.copyNextSampleBuffer() else {
                    state.finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                if let onSample {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if pts.isFinite, pts - state.lastReported >= 0.25 {
                        state.lastReported = pts
                        onSample(pts)
                    }
                }
                if !input.append(sample) {
                    state.finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }
}

private final class PumpState: @unchecked Sendable {
    var finished = false
    var lastReported = -1.0
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
