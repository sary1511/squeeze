import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a video into a looping animated GIF with AVFoundation + ImageIO.
enum GIFEngine {
    /// GIFs keep every frame in memory until they're written, so cap the length.
    static let maxSeconds: Double = 30

    static func encode(
        input: URL,
        output: URL,
        options: GIFOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)
        guard try await asset.load(.isReadable) else {
            throw EncodeError("macOS can't read the video in this file.")
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw EncodeError("No video track found.") }

        let duration = try await asset.load(.duration).seconds
        let length = min(duration.isFinite ? duration : 0, maxSeconds)
        guard length > 0 else { throw EncodeError("This video has no length.") }

        let fps = Double(options.fps)
        let frameCount = max(Int((length * fps).rounded(.down)), 1)
        let times = (0..<frameCount).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        if let maxWidth = options.maxWidth {
            // Width is the limit; the tall bound just keeps portrait videos proportional.
            generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        }

        try? FileManager.default.removeItem(at: output)
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.gif.identifier as CFString, frameCount, nil)
        else { throw EncodeError("Couldn't create the GIF file.") }

        let fileProperties = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)

        let delay = 1.0 / fps
        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
                kCGImagePropertyGIFUnclampedDelayTime as String: delay,
            ]
        ] as CFDictionary

        var added = 0
        var lastImage: CGImage?
        for try await result in generator.images(for: times) {
            if Task.isCancelled { break }
            // If a frame can't be decoded, repeat the previous one so timing stays right.
            if let image = (try? result.image) ?? lastImage {
                CGImageDestinationAddImage(destination, image, frameProperties)
                lastImage = image
                added += 1
                progress(Double(added) / Double(frameCount) * 0.95)
            }
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        guard added == frameCount, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw EncodeError("Couldn't read enough frames to make the GIF.")
        }
        progress(1)
    }
}
