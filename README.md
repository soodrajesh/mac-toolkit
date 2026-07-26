# Toolbox

Native macOS PDF & image toolkit. Pure Swift + SwiftUI, no Xcode, zero third-party
dependencies. Offline and private — nothing leaves your Mac, except the Video
Downloader tool (downloads videos from the web as requested).

![Toolbox screenshot](docs/screenshot.png)

## Prerequisites

- **macOS 13+** and the **Swift toolchain** (`swift --version`) — required to build.
- **Ghostscript** (recommended) — for high-quality, text-preserving PDF compression:

  ```bash
  brew install ghostscript
  ```

  Without it the app still runs, but Compress PDF falls back to native
  rasterization (good for scans, not for text PDFs). The app auto-detects `gs`
  at `/opt/homebrew/bin`, `/usr/local/bin`, or on `PATH`.

- **yt-dlp + ffmpeg** (required for Video Downloader) — batch download videos from
  any site and extract audio:

  ```bash
  brew install yt-dlp ffmpeg
  ```

  Both are required; the app auto-detects them and shows a hint if missing. yt-dlp
  supports 1000+ video sites (YouTube, TikTok, Instagram, Twitter/X, Twitch, Reddit, etc.).

- **Transcribe** — needs a one-time Speech Recognition permission grant; clicking
  **Transcribe** prompts for it automatically the first time. Language picker is
  scoped to English (US / UK / India).

## Build & run

```bash
./build.sh
```

`build.sh` compiles the sources, renders the app icon from an SF Symbol, bundles
`Toolbox.app`, and installs it to `/Applications`. Launch it from Launchpad /
Spotlight, or:

```bash
open /Applications/Toolbox.app
```

## Compression presets (Compress PDF)

Ghostscript mode offers presets — pick based on how small you need it:

| Preset | Image DPI | Use for |
|--------|-----------|---------|
| Screen | 72 | Email / smallest size (biggest reduction) |
| eBook | 150 | Balanced (default) |
| Printer | 300 | High quality (may not shrink text PDFs) |

Text/vector PDFs compress less than scans — most of their size is already-small
fonts and vectors, not downsamplable images. Use **Screen** for the deepest cuts.

## Features

- **Compress PDF** — Ghostscript (if installed) for high-quality, text-preserving
  compression; native rasterization fallback otherwise.
- **Merge PDF** — combine files; reorder by drag or ↑/↓ arrows.
- **Split PDF** — one file per page, or by page ranges (`1-3, 5, 8-10`).
- **PDF Pages** — rotate, delete, extract pages; PDF → images; images → PDF.
- **PDF Security** — add/remove password, diagonal watermark.
- **Page Numbers** — stamp page numbers/labels (`{n}`, `{total}`) at any corner/edge.
- **Crop / Trim Margins** — *batch*: trim whitespace margins from every page by a
  percentage (uniform or per-side); lossless (sets the PDF crop box).
- **Organize Pages** — *single PDF*: a visual thumbnail grid — drag to reorder,
  rotate or remove individual pages (with per-page restore from a trash strip),
  then save as a new PDF.
- **Convert & Compress** — *batch*: many images at once → change format (incl.
  HEIC → JPEG), compress by quality, cap max size, EXIF/GPS always stripped.
- **Image Editor** — *single image*: crop with draggable handles, rotate, flip,
  Paint-style Resize & Skew (percentage or pixels, keep aspect), live selection +
  output-size readout.
- **Blur / Pixelate** — drag over regions to hide faces/addresses/numbers, with live
  preview, or click **Auto-detect faces** (Vision) to find and add them automatically.
- **Redact** — permanently black out regions in a PDF or image (content underneath
  is destroyed, not just covered); choose fill color, live preview, multi-page PDF support.
- **Collage** — Grid / Horizontal / Vertical for uniform layouts, or **Freeform**: an
  interactive poster maker — drag, resize, rotate, and set opacity on each image, plus
  **Add Text** (font, size, color, bold/italic). Exports a full-res PNG.
- **Icon Generator** — image → favicon.ico + full PNG set (16–1024) + AppIcon.icns.
- **Remove Background** — one-click subject cutout (Vision, macOS 14+); keep it
  transparent or drop in a new **solid color / image** background, with live preview.
- **Watermark** — *batch*: stamp a text or logo watermark onto many images at once,
  at a corner/center or tiled, with adjustable size and opacity.
- **Barcode / QR** — generate QR / Code 128 / PDF417 / Aztec (save PNG), and
  read/decode any supported symbology from an image.
- **OCR / Text** — extract text from scanned PDFs/images, or build a **searchable
  PDF** (invisible selectable text layer) — on-device (Vision).
- **Transcribe** — *batch*: speech-to-text for audio or video files, on-device
  (Speech framework), English (US/UK/India). Video files have their audio
  extracted first (reuses the Convert & Compress Video pipeline, ffmpeg fallback
  included). Outputs a `.txt` transcript, optionally also `.srt` subtitles.
  Refuses to run rather than fall back to Apple's server-based recognizer if
  on-device recognition isn't available — this tool never sends audio anywhere.
- **Video Downloader** — *batch*: paste multiple video URLs (YouTube, TikTok, Instagram,
  Twitch, etc.) and download them as MP4 videos or extract audio as MP3 files.
  Choose quality presets (720p, 480p, etc. for video; 128/192/320 kbps for audio).
  Requires `yt-dlp` and `ffmpeg`.
- **Convert & Compress Video** — *batch*: re-encode local video files to MP4 at a
  target quality/resolution. Native AVFoundation; falls back to `ffmpeg` (if
  installed) for codecs it can't re-encode (e.g. VP9/AV1 from high-res YouTube
  downloads). Preview pane has a real play/pause/scrub player (falls back to a
  static frame if the codec can't be decoded for playback either); shows a real
  progress % while processing, not just a spinner.
- **Extract Audio (video)** — *batch*: pull the audio track out of local video
  files as M4A (native AVFoundation) or MP3 (via ffmpeg — AVFoundation has no MP3
  encoder). Same live preview player and real progress %.
- **Trim Audio** — load one audio file, drag on the waveform to draw one or more
  cut regions (pinch to zoom for precision), play/pause with a click-to-seek
  playhead to find exact points, then **Extract Selected** (keep only the
  regions, concatenated into one file) or **Delete Selected** (remove them,
  keeping the rest). Optional fade in/out per region.
- **Merge Audio** — combine multiple audio files into one, in list order (drag
  rows to reorder) — plain concatenation, no crossfade.
- **Loop Audio** — repeat a short clip back-to-back until it fills a target
  duration (e.g. loop a 30s clip to 60 minutes), trimming the final repeat to
  land exactly on time. No crossfade at loop seams.

  Audio tools use native AVFoundation (no ffmpeg) — output is AAC/M4A; MP3
  output isn't possible without ffmpeg since AVFoundation has no MP3 encoder.

## Optional: stronger PDF compression

```bash
brew install ghostscript
```

The Compress PDF tool auto-detects it and shows a "Ghostscript detected" badge.

## Layout

```
Sources/
  App.swift, Tool.swift, Support.swift
  Components/  JobModel.swift, ToolScaffold.swift, RegionSelector.swift,
               WaveformView.swift, AudioPlayerController.swift, VideoPreviewPlayer.swift
               (drop well, numbered file list, output picker, interactive canvas,
               details/metadata panel, play/pause/scrub video preview)
  Services/    PDFService, ImageService, ImageEditService, CollageService,
               FreeformService, BackgroundService, IconService, QRService,
               OCRService, Ghostscript, AudioService, VideoService,
               WatermarkService, FaceDetectionService, FileInfoService,
               TranscriptionService
  Views/       one per sidebar tool — PDFOrganizeView.swift adds a
               drag-reorderable page thumbnail grid (see PDFService.organize)
```

Shared UX: numbered drag/arrow-reorderable file lists (drop a folder to add every
matching file inside it, recursively) — click any row in a multi-file batch to
switch the preview and **Details** panel to that file specifically (dimensions/EXIF
for images, document properties for PDFs, codec/bitrate/tags for audio & video),
falling back to the first file when nothing's explicitly clicked; a remembered
output folder (persisted across launches); a real progress bar (per-file, not
just a spinner — every batch tool reports true progress as each file finishes)
alongside a **Cancel** button for batch jobs in progress; and collapsible
sidebar sections (click a section header to expand/collapse; remembered across
launches).

Video playback (both the Convert/Extract Audio preview and any future video
work) is built on plain `AVFoundation` + `AVPlayerLayer`, not AVKit's SwiftUI
`VideoPlayer` — that view's private companion framework crashes at runtime in
this project's non-Xcode `swiftc` build (no proper framework embedding). If a
future macOS toolchain fixes that, it isn't necessary to fix here, so this is a
deliberate constraint, not an oversight.

## Ideas for later

Extract embedded images, Freeform snap/alignment guides, single-image text stamp in
Image Editor, ⌘S menu command, `CFBundleDocumentTypes` + codesigning for "Open With" /
Gatekeeper-friendly sharing.
