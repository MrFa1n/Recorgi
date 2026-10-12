# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Recorgi — a native (Swift/SwiftUI/AppKit, no Electron), fully open-source macOS screen recorder. Long-term goal: load real third-party OBS plugins via `libobs` (not implemented yet — see License below). Current functionality: record the full display, a specific display, a specific window, or a custom dragged area, with system audio and/or microphone as independent, simultaneous, no-virtual-device-needed tracks.

## Build & run

```sh
./Scripts/bootstrap.sh                 # first time: installs XcodeGen if missing, generates Recorgi.xcodeproj
xcodegen generate                      # regenerate after editing project.yml or adding/removing Swift files
swift build                            # from inside Packages/<Name>/ — fastest way to catch errors in one package
xcodebuild -project Recorgi.xcodeproj -scheme Recorgi -configuration Debug -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/Recorgi.app
```

No test suite exists yet (no `testTarget` in any `Package.swift`).

`Recorgi.xcodeproj` is **generated, not committed** (gitignored) — `project.yml` is the only source of truth for build settings. Regenerate after any file-list or build-setting change; a stale generated project silently builds against an old file list.

### Verifying a change actually works

This is a native app touching real system permissions (Screen Recording, Microphone) and the real screen/desktop — there's no simulator. The loop used throughout this project:

1. `swift build` in whichever package(s) changed.
2. If files were added/removed or `project.yml` changed: `xcodegen generate`, then the full `xcodebuild` build.
3. Fully quit any running instance before relaunching — a plain rebuild over an already-running process is not reliable for a code-signed macOS app:
   ```sh
   osascript -e 'tell application id "com.recorgi.app" to quit'
   pkill -f "Recorgi.app/Contents/MacOS/Recorgi"   # fallback if the above didn't catch it
   open .build/xcode/Build/Products/Debug/Recorgi.app
   ```
4. An agent working in this repo cannot see the screen or drive mouse/keyboard — anything needing visual confirmation (does the UI look right, does a cursor change, does a recorded file actually play) needs the human to check by hand.

### Code signing — don't touch without understanding why

`project.yml` pins `CODE_SIGN_STYLE: Manual` + `CODE_SIGN_IDENTITY: "Recorgi Local Dev"`, a **local self-signed certificate** (no Apple Developer account needed), created once via Keychain Access (steps are in `project.yml`'s comment). This exists because ad-hoc signing gives every rebuild a new code identity, which makes macOS treat each rebuild as a "new app" and silently reset TCC grants (mic, screen recording) on every single build — a real, repeatedly-hit problem during development. If this identity doesn't exist on a machine, the build fails signing.

`ENABLE_HARDENED_RUNTIME` is explicitly `false`. Turning it on breaks Xcode's Debug-configuration "debug dylib" launch trick (app crashes on launch: "cannot be opened because of a problem") — that trick's stub executable is signed by Xcode's own toolchain, not by our identity, and Hardened Runtime's Library Validation rejects the mismatch. Only relevant for a future Release/notarized distribution path, not local Debug builds.

## Architecture

Three local Swift packages plus one Xcode app target, dependencies flowing one direction only:

```
RecorgiCore  →  RecorgiCapture  →  RecorgiUI  →  Recorgi/ (app target, RecorgiApp.swift)
```

- **RecorgiCore** — pure model layer, no AppKit/AVFoundation/ScreenCaptureKit imports. `RecordingSettings` (an `ObservableObject` threaded through the whole app) plus the enums that describe *choices* (`CaptureRegion`, `SystemAudioScope`, `PermissionStatus`, `RecordingState`) and plain value-type device descriptors (`DisplayInfo`, `WindowInfo`, `AudioInputDevice`, `AudioOutputDevice`, `AudioApplication`). Also `Log` (per-area `os.Logger` instances) and `LogExporter` (reads them back) — see Logging below.
- **RecorgiCapture** — all AppKit/AVFoundation/ScreenCaptureKit integration. `ScreenRecordingEngine` is the center of gravity: owns the whole capture-and-mux pipeline (ScreenCaptureKit for video + optional system audio, `AVCaptureSession` for mic, `AVAssetWriter` muxing both into one `.mov`). Everything else here is a focused helper the engine or UI calls into — `PermissionsManager`, `CaptureSourceProvider` (lists displays/windows), `AudioDeviceProvider`/`CoreAudioOutputDeviceLister` (mic/output device enumeration — AVFoundation has no API for output devices, hence the CoreAudio-level lister), `RunningApplicationProvider` (apps, for per-app system-audio capture), `RecordingLibrary` (lists past `.mov` files), `AreaSelectionWindow`/`AreaSelector` (the drag-to-select overlay), `AreaHighlightWindow` (the persistent on-screen border shown while an area is selected or being recorded, excluded from the capture itself by `CGWindowID`).
- **RecorgiUI** — SwiftUI only. `ContentView` is the `NavigationSplitView` root (sidebar + detail + `TransportBar` pinned via `safeAreaInset`). Sidebar pages: `RecordPageView` (quick overview + source cards, each with an "Изменить →" link that jumps straight to the owning page via a `Binding<SidebarSection?>` passed down from `ContentView`), `CaptureRegionView`, `AudioSourcesView`, `GeneralSettingsView`, `RecordingsLibraryView`. `GlassCard`/`GlassToggleButton` are the two shared Liquid Glass building blocks — every button/toggle in the app goes through one of these two (or an explicit `.buttonStyle(.glass/.glassProminent)` + `.buttonBorderShape(.capsule)`, circle reserved for the record button) for a deliberately unified look; don't introduce a third style.
- **Composition root** is `RecorgiApp.swift`: the three `@StateObject`s (`PermissionsManager`, `RecordingSettings`, `ScreenRecordingEngine`) are created once there and threaded down by parameter. No DI container, no singletons.

SwiftUI gotcha that bit this codebase once already: a helper that owns a persistent AppKit resource (a window, in `AreaHighlighter`'s case) must be `@State`, never a plain `let`, inside a `View` struct — SwiftUI recreates the struct on every re-render, and a `let` silently spawns a fresh instance each time, orphaning whatever the previous instance actually put on screen.

## Recording pipeline — hard-won fixes, don't regress these

`ScreenRecordingEngine` went through an extended investigation (see git log from `bc58bd2` through `8325200`) to get from "produces unplayable files with no `moov` atom" to reliable. The load-bearing fixes:

- **State is claimed synchronously before any `await`** in `start()` (`.starting` immediately, `.idle` again on any thrown error, via a `performStart()` + `do/catch` split). Without this, a second tap on Record while the first `start()` is still awaiting silently re-enters and overwrites `assetWriter`/`videoInput`/`stream` out from under the first call, orphaning a writer nothing ever finalizes.
- **The `AVAssetWriter` session starts explicitly**, anchored to `CMClockGetHostTimeClock()`, *before* any capture begins — not lazily on whichever sample happens to arrive first. Video (ScreenCaptureKit) and microphone (`AVCaptureSession`) are independent pipelines with their own clocks and jitter.
- **Every sample's presentation timestamp is checked for strict monotonicity, per track**, before appending (`lastVideoPTS`/`lastSystemAudioPTS`/`lastMicrophonePTS`). `AVAssetWriter`'s real-time multiplexer fails the *entire* writer on a single out-of-order sample on any one track — a documented failure mode for this exact ScreenCaptureKit + AVAssetWriter combination (see commit `8325200`'s message for the reference).
- **Output pixel width/height are always rounded to even numbers** (`evenified`) — H.264 needs this for 4:2:0 chroma subsampling, and a dragged area or arbitrary window size essentially never lands on one naturally.
- **`config.minimumFrameInterval` caps capture at 30fps, and `AVVideoCompressionPropertiesKey` sets an explicit bitrate** — left to AVFoundation's automatic defaults, a high-refresh-rate display can hand the real-time H.264 encoder more data than it can sustain.
- **`writer.status` is checked on every `stop()`, not only when it's still `.writing`** — the writer can fail asynchronously *during* capture (an `append()` call returning `false`), and only checking the `.writing` branch silently skips surfacing that failure entirely.
- `AreaSelector`'s coordinate conversion matters: AppKit view coordinates are bottom-left origin, `SCStreamConfiguration.sourceRect` is top-left origin — the Y-flip in `AreaSelector`/`AreaHighlighter` is not optional boilerplate.

## Logging

This project logs liberally, on purpose: `Packages/RecorgiCore/Sources/RecorgiCore/Log.swift` defines one `os.Logger` per functional area (`Log.capture`, `.permissions`, `.hotkeys`, `.menuBar`, `.library`, `.devices`, `.ui`), all under the `com.recorgi.app` subsystem. **When adding or changing behavior anywhere in the app, add logging at the same time** — every operation's start/stop, every error or unexpected branch, every externally-triggered state change (permission results, hotkey registration, device enumeration, writer/stream failures). Skip anything that fires on every SwiftUI body re-evaluation or every frame; that's noise, not signal.

Mark interpolated values `privacy: .public` explicitly — `os.Logger` redacts `String` interpolations by default, and a log nobody can actually read defeats the point. This is a local troubleshooting tool for whoever's debugging the app on their own Mac, not telemetry sent anywhere, so there's no privacy reason to hide the values.

`LogExporter.swift` (also RecorgiCore) reads them back via `OSLogStore(scope: .currentProcessIdentifier)` — deliberately *not* `.system`, which needs the calling process to run as an admin per `OSLogStore`'s own documentation. This means the in-app "Экспортировать логи…" button (General settings) only ever covers the current run, not previous launches; that's an accepted tradeoff for never needing to ask for elevated privileges.

Inspect logs live during development with `/usr/bin/log stream --predicate 'subsystem == "com.recorgi.app"'` (the full path, not bare `log` — some shells here have it shadowed by something else that silently misbehaves) or in Console.app filtered the same way.

## License

GPL-3.0-or-later, chosen deliberately: the stated goal is to load real third-party OBS plugins by linking `libobs`, which is itself GPL-2.0-or-later — combining with it binds the whole program under GPL-compatible terms. **The `libobs` integration itself is not implemented yet** — don't assume plugin-loading code exists anywhere in this repo.

## Conventions

- Commit after every meaningful change, not batched at the end. English commit messages. No AI co-author attribution line — this repo's own preference, overriding the harness default.
- Log generously (see Logging above) — this project's explicit preference is to be able to diagnose a problem from the log rather than having to reproduce it. New code without any logging in it is the exception to justify, not the default.
- Minimum deployment target is macOS 26 — required for the Liquid Glass SwiftUI APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) the whole UI is built on, not an oversight to "fix" downward.
- **Every new UI element must support both transparency and the accent-color theme — never a hardcoded opaque background or a hardcoded color on something that should follow the user's choice.** Caught missing on a volume slider that stayed plain system blue regardless of the chosen accent color. Transparency: use `GlassCard`/`GlassToggleButton` or `.buttonStyle(.glass/.glassProminent)` (see Architecture above) — don't introduce a new opaque style. Color: read `settings.accentColor?.color ?? Color.accentColor` directly (simplest, used by pages that already hold `settings`, e.g. `CaptureRegionView`), or `.themedTint()`/`@Environment(\.accentTint)` (`AccentTint.swift`) for a control that's already blue by default and sits where threading `settings` through isn't natural (e.g. `RecordingEditorView`, `TrimScrubber`) — never `.tint(.blue)` or another fixed color. When two sibling controls need to stay visually distinguishable from each other (e.g. the recording editor's separate microphone/system-audio volume tracks), derive both from the same theme color via `.mix(with:by:)` rather than picking two unrelated fixed colors.
