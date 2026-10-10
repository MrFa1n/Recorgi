# Recorgi

Native, open-source screen recorder for macOS with full OBS plugin support.

## Goals

- **Native macOS** — built with Swift/SwiftUI/AppKit, no Electron, no cross-platform shims.
- **OBS plugin compatible** — loads existing OBS plugins (`.plugin`/`.so`/`.dylib` built against `libobs`) without forcing authors to port anything.
- **Independent audio/video routing** — record system audio, microphone, and any combination of capture sources simultaneously, each selectable and mixable independently, without routing hacks (e.g. BlackHole-style virtual devices) unless the user explicitly wants them.
- **Modern UI** — a clean, native SwiftUI interface for picking sources, scenes, and outputs.
- **Fully open source.**

## License

Recorgi is licensed under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later). See [LICENSE](LICENSE).

This choice is not incidental: Recorgi links against `libobs` to load real OBS plugins, and `libobs`/OBS Studio are themselves distributed under GPL-2.0-or-later. Combining with that code binds the whole resulting program under GPL-compatible terms — GPL-3.0-or-later was chosen because it stays compatible with OBS's GPL-2+ codebase while adding GPLv3's explicit patent grant and anti-tivoization terms.

## Project layout

```
Recorgi/              App target sources (SwiftUI @main entry point)
Packages/
  RecorgiCore/         Settings, permission, and recording-state models
  RecorgiCapture/      ScreenCaptureKit (video + system audio) + AVCaptureSession (mic) + AVAssetWriter muxing
  RecorgiUI/           SwiftUI views
project.yml            XcodeGen spec — the source of truth for Recorgi.xcodeproj
Scripts/bootstrap.sh   Installs XcodeGen if needed and generates the Xcode project
```

Run `Scripts/bootstrap.sh` (or `xcodegen generate`) to produce `Recorgi.xcodeproj`, which is generated and not committed.

## Status

**Working:** permission priming at launch (microphone + screen recording), a record button, independent toggles for system audio and microphone (both on by default), device picker, recording to `.mov` with separate tracks per audio source.

**Not yet implemented:** OBS plugin loading (`libobs` integration — the GPL-driving feature), window/app-specific capture (currently records the whole main display), scenes.
