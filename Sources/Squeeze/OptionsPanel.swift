import SwiftUI

/// The floating Liquid Glass card at the bottom of the window.
struct OptionsPanel: View {
    @Bindable var settings: SettingsStore
    let mode: AppMode
    let isLocked: Bool

    private var handBrakeMissing: Bool {
        settings.engine == .handbrake && HandBrakeEngine.executableURL == nil
    }

    private var copying: Bool {
        settings.copyStreams && settings.format.canCopyStreams && FFmpegEngine.isAvailable
    }

    private var hardwareBinding: Binding<Bool> {
        Binding(
            get: { settings.engine == .apple ? true : settings.hardware },
            set: { settings.hardware = $0 }
        )
    }

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                if mode == .compress { encodingRow } else { formatRow }
                Divider()
                namingRow
                destinationRow
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.75 : 1)
    }

    private var fileExtension: String {
        mode == .compress ? "mp4" : settings.format.fileExtension
    }

    // MARK: Rows

    private var encodingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                LabeledContent("Engine") {
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(Engine.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                LabeledContent("Codec") {
                    Picker("Codec", selection: $settings.codec) {
                        ForEach(Codec.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Spacer(minLength: 0)

                Toggle("Hardware", isOn: hardwareBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(settings.engine == .apple)
                    .help(settings.engine == .apple
                          ? "Apple's engine always uses the Apple Silicon media engine."
                          : "Use the Apple Silicon media engine: much faster, slightly larger files.")
            }

            if handBrakeMissing {
                Label("HandBrakeCLI not found. Rebuild with build.sh or run “brew install handbrake”.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(settings.options.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                LabeledContent("Format") {
                    Picker("Format", selection: $settings.format) {
                        ForEach(OutputFormat.groups, id: \.self) { group in
                            Section(group) {
                                ForEach(OutputFormat.allCases.filter { $0.group == group }) { format in
                                    Text(format.title).tag(format)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if settings.format.isAnimatedImage {
                    LabeledContent("Width") {
                        Picker("Width", selection: $settings.gifSize) {
                            ForEach(GIFSize.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    LabeledContent("FPS") {
                        Picker("FPS", selection: $settings.gifRate) {
                            ForEach(GIFRate.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                Spacer(minLength: 0)

                if settings.format.canCopyStreams && FFmpegEngine.isAvailable {
                    Toggle("Keep original codecs", isOn: $settings.copyStreams)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Only change the container, without re-encoding. Fast and lossless.")
                }
            }

            if let missing = settings.format.missingTool {
                Label("\(missing) not found, so \(settings.format.title) isn't available. Rebuild with build.sh.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if copying {
                Text("Keeps the original video and audio and only changes the container to \(settings.format.containerName). No quality loss and usually done in seconds. If the codecs don't fit \(settings.format.containerName), Squeeze converts the file properly instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(settings.format.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var namingRow: some View {
        HStack(spacing: 8) {
            Text("Name")
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField("Prefix", text: $settings.prefix)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            Text("filename")
                .font(.callout.monospaced())
                .foregroundStyle(.tertiary)
            TextField("Suffix", text: $settings.suffix)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            Text(".\(fileExtension)")
                .font(.callout.monospaced())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Text(settings.naming.name(for: "video") + ".\(fileExtension)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Example output name")
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 8) {
            Text("Save to")
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Label {
                Text(settings.nextToOriginal
                     ? "Same folder as each original"
                     : settings.outputFolder.path(percentEncoded: false)
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: settings.nextToOriginal ? "arrow.turn.down.right" : "folder.fill")
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Next to original", isOn: $settings.nextToOriginal)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Save each finished file in the same folder as its original")
            Button("Choose…") { settings.chooseOutputFolder() }
                .buttonStyle(.glass)
                .disabled(settings.nextToOriginal)
        }
    }
}
