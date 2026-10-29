import AppKit
import QuickLookThumbnailing
import SwiftUI

struct QueueRow: View {
    let item: QueueItem
    let thumbnail: NSImage?
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            thumbnailView

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.source.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let label = item.jobLabel {
                        Text(label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                            .fixedSize()
                            .help("Queued from Finder with these settings")
                    }
                }
                statusView
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingButton
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Show Original in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.source])
            }
            if case .done(let url, _) = item.status {
                Button("Show Compressed in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    // MARK: Pieces

    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 46)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .waiting:
            Text("Waiting · \(Files.formatted(item.sourceSize))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .encoding(let value):
            HStack(spacing: 10) {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

        case .done(_, let newSize):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(Files.formatted(item.sourceSize)) → \(Files.formatted(newSize))")
                if item.sourceSize > 0 {
                    let change = Double(newSize - item.sourceSize) / Double(item.sourceSize)
                    Text("(\(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))))")
                        .foregroundStyle(change < 0 ? .green : .orange)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        switch item.status {
        case .waiting:
            Button("Remove", systemImage: "xmark", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Remove from queue")
        case .encoding:
            EmptyView()
        case .done(let url, _):
            Button("Show in Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Show in Finder")
        case .failed:
            Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Try again")
        }
    }

    // MARK: Thumbnail

    static func makeThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 144, height: 92), scale: 2, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
