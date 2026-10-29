# Squeeze

Simple video compression and conversion for macOS 26 (Tahoe), with a Liquid Glass interface. Compress turns any video into a smaller MP4 at the same size and frame rate, with no cropping. Convert turns any video into MP4, MKV, WebM, MOV, ProRes, AVI, WMV, FLV, MPEG-TS, 3GP, OGV, GIF, animated WebP, M4A, MP3, WAV or FLAC.

## Build

You need macOS 26 and Xcode 26. Then run:

```bash
cd Squeeze
./build.sh
```

You get `dist/Squeeze.app` and `dist/Squeeze.dmg`. The script downloads two tools and bundles them inside the app:

- **HandBrakeCLI**, the official build from GitHub. If the download fails, the script uses Homebrew's copy (`brew install handbrake`).
- **FFmpeg**, a static, signed macOS build from [ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de). If the download fails, the app uses Homebrew's `ffmpeg` if it's installed.

Both are saved in `vendor/`, so later builds don't download them again. To use a different build, drop your own `HandBrakeCLI` or `ffmpeg` into `vendor/`.

To edit the app in Xcode, open `Package.swift` and press Run.

## Tabs

The toolbar switches between **Compress** and **Convert**. Each tab has its own queue, and both can run at the same time. The name prefix, suffix and "Save to" folder are shared between the tabs.

## Finder extension

Right-click any video (or a folder of videos) in Finder → **Squeeze**:

- **Compress**: uses the settings from the Compress tab
- **Compress With ▸**: HandBrake H.264 (default) / H.265, with or without hardware, or Apple H.264 / H.265
- **Convert To ▸**: every format from the Convert tab
- **Change Container Only ▸**: MP4, MKV, MOV, WebM, M4V or MPEG-TS, keeping the original codecs (no re-encode)
- **Open in Squeeze**: adds the files to the queue without starting

By default Squeeze works **in the background**: no window and no Dock icon. Each file is saved **next to its original** (compressed files get `_compressed` added to the name). Progress shows in the menu bar, a notification appears when each file is done (click it to show the file), and Squeeze quits when everything is finished.

All of this can be changed in **Squeeze → Settings… (⌘,) → Finder**:

- Work in the background, or open the Squeeze window
- Save next to the original, in Squeeze's "Save to" folder, or in a specific folder
- Separate prefix and suffix for compressed and converted files
- Notify when each file is done, show finished files in Finder, quit when done

**Settings → General** sets when the menu bar icon appears (always, while working, never), whether to keep the Mac awake, and the finish sound.

Files queued from Finder show a tag with their settings. Changing the app's own options doesn't affect them.

**Setup:** drag Squeeze to Applications and open it once. It registers the extension and switches it on the first time. To turn it off or back on, use Squeeze → Finder Extension… or System Settings → General → Login Items & Extensions → Finder.

How it works: Finder extensions must be sandboxed, so the extension (`Extension/FinderSync.swift`) doesn't process anything itself. It opens a `squeeze://` link with the file paths and the chosen action. The app (not sandboxed) handles that link in `FinderRequests` (`Stores.swift`).

## Convert formats

| Format | Written by | Settings |
|---|---|---|
| MP4 · H.264 / M4V | HandBrake* | x264, RF 20, AAC 160 |
| MP4 · H.265 | HandBrake* | x265 10-bit, RF 22, AAC 160 |
| MP4 · AV1 | HandBrake* | SVT-AV1 10-bit, RF 34.5, AAC 160 |
| MKV · H.264 / H.265 | HandBrake* | as above, in Matroska |
| WebM · VP9 | HandBrake* | VP9, RF 30, Opus 160 |
| WebM · AV1 | HandBrake* | SVT-AV1 10-bit, RF 34.5, Opus 160 |
| MOV · H.264 / HEVC | Apple | media engine, AAC 192 |
| MOV · ProRes 422 | Apple | ProRes 422, PCM audio |
| GIF | FFmpeg† | palettegen/paletteuse, 320/480/640/original width, 10/15/24 fps, loops |
| WebP · Animated | FFmpeg | libwebp q75, same width/fps options, loops |
| AVI · Xvid | FFmpeg | MPEG-4 Part 2 q3, MP3 VBR |
| WMV | FFmpeg | WMV8 q3, WMA 192 |
| FLV | FFmpeg | x264 CRF 20, AAC 160 |
| MPEG-TS | FFmpeg | x264 CRF 20, AAC 160 |
| 3GP | FFmpeg | x264 Baseline CRF 23, AAC 96 |
| OGV | FFmpeg | Theora q7, Vorbis q5 |
| M4A | Apple | AAC 256 |
| MP3 / WAV / FLAC | FFmpeg | LAME V2 / 16-bit PCM / lossless |

\* If HandBrakeCLI is missing, FFmpeg makes these with the same codecs and quality.
† If FFmpeg is missing, Apple's ImageIO makes the GIF (first 30 seconds only).

**Keep original codecs** (MP4, MKV, WebM, MOV, M4V, MPEG-TS): FFmpeg only changes the container, without re-encoding. This means no quality loss, and it usually takes a few seconds. If the codecs don't fit the new container (for example PCM audio into MP4), Squeeze converts the file properly instead.

**When macOS can't read the source** (MKV, WebM, AVI, WMV…) and the format is MOV, ProRes or M4A, HandBrake (or FFmpeg) first makes a high-quality temporary MP4, and Apple's frameworks convert that. The temporary file is deleted afterwards.

## Compress engines

| Engine | Codec | Hardware | What runs |
|---|---|---|---|
| HandBrake | H.264 | off | x264, RF 22, fast, AAC 160 (HandBrake's default "Fast 1080p30") |
| HandBrake | H.265 | off | x265 10-bit, RF 22, fast |
| HandBrake | H.264 | on | VideoToolbox H.264, CQ 60 |
| HandBrake | H.265 | on | VideoToolbox H.265 10-bit, CQ 60 (HandBrake's VT 1080p preset) |
| Apple | H.264 / H.265 | always | AVFoundation on the media engine, bitrate matched to about RF 22 |

Three changes from HandBrake's default preset: no 1080p cap, no 30 fps cap, and no auto-crop.

The HandBrake engine reads every format, including MKV, WebM, AVI and WMV. The Apple engine reads only formats macOS supports natively (MOV, MP4, M4V and some others). For anything else it tells you to switch to HandBrake.

## Files

```
Sources/Squeeze/
  SqueezeApp.swift      app, Settings + menu bar scenes, launch / squeeze:// handling
  Preferences.swift     Settings model, AppModel, AppKit-hosted main window, notifications
  PreferencesView.swift Settings window (Finder, General) + menu bar progress view
  ContentView.swift     queue list, toolbar, drag & drop
  QueueRow.swift        one video row (thumbnail, progress, result)
  OptionsPanel.swift    Liquid Glass options card
  Stores.swift          settings (saved), job builder + queue runner
  HandBrakeEngine.swift HandBrakeCLI arguments, runner + progress parsing
  AppleEngine.swift     AVFoundation re-encoder (MP4, MOV, ProRes, M4A)
  GIFEngine.swift       video → animated GIF (AVFoundation + ImageIO)
  FFmpegEngine.swift    FFmpeg runner, probe, progress + per-format options
  ConvertEngine.swift   picks HandBrake, Apple or FFmpeg per format, with fallbacks
  Models.swift          types and file helpers
  SqueezeLink.swift     squeeze:// link format + Finder menu catalogue (shared with the extension)
Extension/
  FinderSync.swift      Finder right-click menu (sandboxed app extension)
```

## Website

`docs/` is a ready-to-publish static website: a one-page overview plus contact, terms and privacy pages. It's plain HTML, CSS and JS, with no build step.

1. **Fill in your details** at the top of `docs/assets/site.js`: GitHub repo, Google Form details, donation link, email and publisher name. Every link on every page reads from there.
2. **Publish on GitHub Pages:** push the repo, then go to Settings → Pages → Deploy from a branch → `main` / `/docs`.
3. **Release the app:** create a GitHub Release and attach the DMG as `Squeeze.dmg`. The Download buttons always point to `releases/latest/download/Squeeze.dmg`, so they pick up new versions automatically.
4. **Contact form** (Google Forms): see below.

### Contact form

The form on `contact.html` keeps the site's own design and sends each message to a Google Form you own.

1. Create a form at forms.google.com with four questions, in this order: **Name** (Short answer), **Email** (Short answer), **Topic** (Short answer), **Message** (Paragraph). In Settings, turn off "Collect email addresses" and "Restrict to users in…" so anyone can respond.
2. Click **⋮ → Get pre-filled link**, type `a`, `b`, `c`, `d` into the four answers, click **Get link** and copy it. It looks like
   `https://docs.google.com/forms/d/e/1FAIpQL…/viewform?usp=pp_url&entry.123=a&entry.456=b&entry.789=c&entry.321=d`
3. In `docs/assets/site.js`, set `googleForm.id` to the part between `/d/e/` and `/viewform`, and the four `fields` to the `entry.…` numbers in the same order (name, email, topic, message).
4. To get an email for every message: open the form's **Responses** tab → **⋮ → Get email notifications for new responses**. Click **Link to Sheets** to collect them in a spreadsheet.

## Licence note

HandBrakeCLI and this FFmpeg build (which includes x264 and x265) are both GPL. Using them yourself or inside your team is fine. If you distribute Squeeze with them bundled, the GPL applies to that distribution. Apple's frameworks have no such restriction.
