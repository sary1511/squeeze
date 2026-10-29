import Foundation

/// Shared by the app and the Finder extension (compiled into both).
/// The extension is sandboxed, so it hands work to the app by opening a
/// `squeeze://` URL that carries the selected file paths and the action.
enum SqueezeLink {
    static let scheme = "squeeze"
    static let extensionBundleID = "com.vyeola.squeeze.finder"

    /// File extensions treated as video (in addition to anything macOS calls audiovisual).
    static let videoExtensions: Set<String> = [
        "mkv", "webm", "avi", "flv", "f4v", "wmv", "asf", "mts", "m2ts", "ts", "vob",
        "mpg", "mpeg", "m2v", "3gp", "3g2", "ogv", "mxf", "divx", "rm", "rmvb", "dv",
        "mov", "mp4", "m4v", "gif", "webp"
    ]

    // MARK: Menu catalogue

    struct CompressPreset {
        let title: String
        let engine: String      // Engine raw value
        let codec: String       // Codec raw value
        let hardware: Bool
    }

    static let compressPresets: [CompressPreset] = [
        .init(title: "HandBrake · H.264 (HandBrake default)", engine: "handbrake", codec: "h264", hardware: false),
        .init(title: "HandBrake · H.265", engine: "handbrake", codec: "h265", hardware: false),
        .init(title: "HandBrake · H.264 · Hardware", engine: "handbrake", codec: "h264", hardware: true),
        .init(title: "HandBrake · H.265 · Hardware", engine: "handbrake", codec: "h265", hardware: true),
        .init(title: "Apple · H.264", engine: "apple", codec: "h264", hardware: true),
        .init(title: "Apple · H.265", engine: "apple", codec: "h265", hardware: true),
    ]

    struct FormatEntry {
        let id: String          // OutputFormat raw value
        let title: String
    }

    /// "Convert To" menu, in groups separated by dividers.
    static let convertMenu: [[FormatEntry]] = [
        [.init(id: "mp4H264", title: "MP4 · H.264"), .init(id: "mp4H265", title: "MP4 · H.265"),
         .init(id: "mp4AV1", title: "MP4 · AV1")],
        [.init(id: "mkvH264", title: "MKV · H.264"), .init(id: "mkvH265", title: "MKV · H.265")],
        [.init(id: "webmVP9", title: "WebM · VP9"), .init(id: "webmAV1", title: "WebM · AV1")],
        [.init(id: "movH264", title: "MOV · H.264"), .init(id: "movHEVC", title: "MOV · HEVC"),
         .init(id: "movProRes", title: "MOV · ProRes 422")],
        [.init(id: "gif", title: "GIF"), .init(id: "webpAnimated", title: "WebP · Animated")],
        [.init(id: "avi", title: "AVI · Xvid"), .init(id: "wmv", title: "WMV"), .init(id: "flv", title: "FLV"),
         .init(id: "ts", title: "MPEG-TS"), .init(id: "threeGP", title: "3GP"), .init(id: "ogv", title: "OGV · Theora"),
         .init(id: "m4v", title: "M4V · H.264")],
        [.init(id: "m4a", title: "M4A · AAC"), .init(id: "mp3", title: "MP3"), .init(id: "wav", title: "WAV"),
         .init(id: "flac", title: "FLAC")],
    ]

    static var convertFormats: [FormatEntry] { convertMenu.flatMap { $0 } }

    /// "Change Container Only" menu (no re-encode).
    static let copyMenu: [FormatEntry] = [
        .init(id: "mp4H264", title: "MP4"),
        .init(id: "mkvH264", title: "MKV"),
        .init(id: "movH264", title: "MOV"),
        .init(id: "webmVP9", title: "WebM"),
        .init(id: "m4v", title: "M4V"),
        .init(id: "ts", title: "MPEG-TS"),
    ]

    // MARK: Request

    enum Action: String {
        case open, compress, convert
    }

    struct Request {
        var action: Action
        var files: [URL]
        var engine: String?
        var codec: String?
        var hardware: Bool?
        var format: String?
        var copyStreams = false

        var url: URL? {
            var components = URLComponents()
            components.scheme = SqueezeLink.scheme
            components.host = action.rawValue
            var items = files.map { URLQueryItem(name: "file", value: $0.path) }
            if let engine { items.append(URLQueryItem(name: "engine", value: engine)) }
            if let codec { items.append(URLQueryItem(name: "codec", value: codec)) }
            if let hardware { items.append(URLQueryItem(name: "hardware", value: hardware ? "1" : "0")) }
            if let format { items.append(URLQueryItem(name: "format", value: format)) }
            if copyStreams { items.append(URLQueryItem(name: "copy", value: "1")) }
            components.queryItems = items
            return components.url
        }

        init(action: Action, files: [URL]) {
            self.action = action
            self.files = files
        }

        init?(url: URL) {
            guard url.scheme == SqueezeLink.scheme,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let action = Action(rawValue: components.host ?? "")
            else { return nil }
            let items = components.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

            self.action = action
            self.files = items.filter { $0.name == "file" }.compactMap { $0.value }.map { URL(fileURLWithPath: $0) }
            self.engine = value("engine")
            self.codec = value("codec")
            self.hardware = value("hardware").map { $0 == "1" }
            self.format = value("format")
            self.copyStreams = value("copy") == "1"
        }
    }
}
