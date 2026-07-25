# Toolbox

Native macOS PDF & image toolkit. Pure Swift + SwiftUI, no Xcode, zero third-party
dependencies. Offline and private — nothing leaves your Mac.

## Prerequisites

- **macOS 13+** and the **Swift toolchain** (`swift --version`) — required to build.
- **Ghostscript** (recommended) — for high-quality, text-preserving PDF compression:

  ```bash
  brew install ghostscript
  ```

  Without it the app still runs, but Compress PDF falls back to native
  rasterization (good for scans, not for text PDFs). The app auto-detects `gs`
  at `/opt/homebrew/bin`, `/usr/local/bin`, or on `PATH`.
- **logo.jpg** in the project root — the build turns it into the app icon
  (optional; skipped if absent).

## Build & run

```bash
./build.sh
```

`build.sh` compiles the sources, generates the app icon from `logo.jpg`, bundles
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
- **Merge PDF** — combine files; drag rows to reorder.
- **Split PDF** — one file per page, or by page ranges (`1-3, 5, 8-10`).
- **PDF Pages** — rotate, delete, extract pages; PDF → images; images → PDF.
- **PDF Security** — add/remove password, diagonal watermark.
- **Image Tools** — compress/convert PNG/JPEG/HEIC/TIFF (incl. HEIC → JPEG),
  resize, EXIF/GPS always stripped.
- **OCR / Text** — extract text from scanned PDFs/images on-device (Vision).

## Optional: stronger PDF compression

```bash
brew install ghostscript
```

The Compress PDF tool auto-detects it and shows a "Ghostscript detected" badge.

## Layout

```
Sources/
  App.swift, Tool.swift, Support.swift
  Components/  JobModel.swift, ToolScaffold.swift   (drop well, file list, output picker)
  Services/    PDFService, ImageService, OCRService, Ghostscript
  Views/       one per sidebar tool
```

## Ideas for later

Searchable-PDF output from OCR, QR generator, PDF metadata editor, favicon/ICO export.
