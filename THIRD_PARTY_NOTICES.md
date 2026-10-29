# Third-party software

The Squeeze download (`Squeeze.dmg`) bundles two programs that are not part of Squeeze. Squeeze runs them as separate programs. It is not affiliated with or endorsed by either project.

## HandBrakeCLI

- Website: https://handbrake.fr
- Source code: https://github.com/HandBrake/HandBrake
- Licence: GNU General Public License, version 2
- Bundled as: `Squeeze.app/Contents/Resources/HandBrakeCLI`, the official macOS build from HandBrake's GitHub releases. The exact version is the one `build.sh` downloaded for each Squeeze release. Run `HandBrakeCLI --version` to see it.

## FFmpeg

- Website: https://ffmpeg.org
- Source code: https://ffmpeg.org/download.html#get-sources
- Licence: GNU General Public License (this build includes GPL components such as x264 and x265)
- Bundled as: `Squeeze.app/Contents/Resources/ffmpeg`, a static macOS build from https://ffmpeg.martin-riedl.de, which publishes the source and build scripts for each build. Run `ffmpeg -version` to see the version and configuration.

## Getting the source

The source code for both programs is available from the links above. If you received Squeeze from me and want a copy of the corresponding source for the exact versions bundled in a release, open an issue at https://github.com/sary1511/squeeze/issues and I will provide it.

## Apple frameworks

Squeeze also uses frameworks that are part of macOS (AVFoundation, VideoToolbox, ImageIO, SwiftUI). They are not bundled with Squeeze.

## Fonts on the website

The website (heysqueeze.site) uses Inter, Inter Tight, Archivo and Libre Caslon Text from Google Fonts, under the SIL Open Font License.
