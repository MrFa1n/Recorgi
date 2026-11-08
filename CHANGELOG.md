# Changelog

All notable changes to Recorgi are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions match the
`MARKETING_VERSION` baked into each build and the git tag it ships under.

## [0.7.1] - 2026-11-08

### Added

- Recordings now have a ready-to-play audio mix for QuickTime while keeping
  microphone and system audio as separate sources for editing in Recorgi.
- Adjust microphone and app audio levels, or mute them, while recording.
- Prepare a playback copy when a recording finishes, alongside the editable
  source tracks.

### Fixed

- Display and window thumbnails now load reliably in the capture source picker.

## [0.7.0] - 2026-10-13

### Added

- Recorgi now runs on macOS 15 (Sequoia) and up, not just 26 — recording
  itself didn't need 26 in the first place. Below macOS 26 the interface
  automatically switches to a plain, non-Liquid-Glass look instead of
  refusing to launch.
- A new "Отладка" card in General settings, for checking the app itself
  rather than configuring it: a toggle to preview the older, non-Liquid-
  Glass interface without needing an actual older Mac, plus the button to
  replay the launch splash.

## [0.6.0] - 2026-10-13

### Added

- An animated launch splash — the corgi mascot pops in, ears perk up
  and wiggle, eyes blink, tongue flicks out, nose pulses, then the
  Recorgi wordmark fades in before handing off to the app. Replay it
  any time from General settings.

## [0.5.0] - 2026-10-13

### Added

- Pause and resume a recording in progress, from the transport bar,
  the menu bar, or a new global hotkey (⌘⇧P by default) — the same
  hotkey toggles pause and resume, just like start/stop already did.
  The paused time is cut out of the final file, not left in as a
  frozen frame or silence.

### Fixed

- The menu bar icon no longer flashes a "paused" look while a
  recording is simply starting or stopping.

## [0.4.0] - 2026-10-13

### Added

- Microphone noise suppression in the recording editor, with four
  selectable levels (Off/Light/Medium/Strong) — gates down background
  noise between words and in silence, with instant audible preview
  before saving. Only available when the recording has separate
  microphone and system-audio tracks.
- Preview noise-suppression levels on your own microphone live, from
  Audio Sources settings — works before recording starts, and while
  a recording is already in progress as long as that settings page
  stays open. The level you land on there becomes the recording
  editor's starting point too.

## [0.3.0] - 2026-10-12

### Added

- Microphone volume control in Audio Sources — adjustable live, whether
  or not a recording is in progress.
- The recording editor can now adjust microphone and system audio
  volume separately, including boosting or lowering just part of the
  recording, with instant audible preview before saving.

### Changed

- Selecting a custom area to record now works across every connected
  display at once — drag on whichever screen you want, no need to pick
  one first.
- The recording editor window can be resized, and its "Звук" section
  now starts expanded.
- Volume sliders and other new controls now follow the chosen accent
  color like the rest of the app.

### Fixed

- The area-selection overlay is easier to see: a darker dimmed
  background and a bigger, clearer instruction banner.

## [0.2.0] - 2026-10-12

### Added

- Select multiple recordings in the library — checkboxes, shift-click to
  select a range, or a floating button that follows you down the list —
  and delete them together. A single recording can still be deleted
  straight from its own row without selecting anything. Either way,
  deleted recordings move to the Trash, not gone for good.
- Export the current session's logs from General settings, to help
  track down a problem.

### Fixed

- Recordings made with the MPEG-4 (`.mp4`) container no longer silently
  disappear from the Recordings library — only `.mov` was ever being
  listed.
- On a multi-monitor setup, the display picker no longer shows the
  primary display twice (once as itself, once as a separate "Основной
  дисплей" card).
- The window picker now actually lists every open window, including
  ones on a different virtual desktop/Space or a second display — and
  no longer mixes in background system windows that aren't real apps.

## [0.1.0] - 2026-10-12

First tagged build.

### Added

- Capture the primary display, a chosen display, a specific window, or a
  custom dragged area, with a persistent on-screen border while an area is
  selected or being recorded.
- Independent, simultaneous audio tracks: system audio (all of it, or
  scoped to one running app) and microphone, each toggled on/off on its
  own, muxed as separate tracks into one `.mov`/`.mp4` file.
- Global, user-reassignable hotkeys for start/stop, toggle microphone, and
  toggle system audio — work even while Recorgi isn't the focused app,
  with a reset-to-defaults button.
- A menu bar status item with a branded icon per state (idle / recording /
  starting-stopping), so Recorgi keeps running and stays reachable after
  its window is closed.
- Recording format controls: video codec (H.264/HEVC), container
  (`.mov`/`.mp4`), and a resolution/frame-rate quality tier.
- A recordings library: search, sort, group by date, rename, reveal in
  Finder, and a built-in trim/export player.
- A native Liquid Glass UI that follows the system's own transparency and
  accent-color settings, with an optional custom accent and a light/dark/
  system appearance override.
- Permission priming for Screen Recording and Microphone access at launch.
- `Scripts/make-dmg.sh` to build an ad-hoc-signed Release and package it
  into a distributable `.dmg`.

### Known limitations

- No `libobs`-based OBS plugin loading yet — the long-term goal driving
  this project's GPL-3.0-or-later license, but not implemented.
- UI is Russian-only.
- Not notarized (no paid Apple Developer Program membership) — Gatekeeper
  flags builds as from an "unidentified developer" on first launch.
