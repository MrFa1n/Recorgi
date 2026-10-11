# Changelog

All notable changes to Recorgi are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions match the
`MARKETING_VERSION` baked into each build and the git tag it ships under.

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
