---
name: release
description: Cut a new versioned Recorgi release — bump MARKETING_VERSION in project.yml by the right amount, update CHANGELOG.md, commit, build the .dmg via Scripts/make-dmg.sh, and tag the release commit. Use this whenever the user asks to cut/make/ship a release or a new build, bump/raise the version, build a new dmg "for real" (as opposed to a quick local test build), or tag a version — including Russian phrasings like "собери новую версию", "подними версию", "сделай релиз", "затегай билд". Don't use it for a plain development rebuild (swift build / xcodebuild without wanting a tagged, versioned artifact) — only when the user wants the result to be a recorded, versioned release.
---

# Cutting a Recorgi release

This turns "ship what's on `main` right now" into a tagged, versioned `.dmg`:
bump the version the right amount, explain what changed in `CHANGELOG.md`,
commit both together, build, and tag the commit the build came from. Follow
this repo's own `CLAUDE.md` for commit-message conventions (English, no AI
co-author line) — it's already loaded automatically, so don't duplicate it
here.

## 0. Make sure there's clean ground to build on

Run `git status`. If there are uncommitted changes, stop and ask the user
whether to commit/stash them first or include them in the release commit —
never silently fold unrelated working-tree changes into a release, and
never discard them.

## 1. Read what actually changed, don't guess

Find the last release tag with `git tag --list 'v*' --sort=-v:refname | head -1`
(if there is none, this is the first release — treat every commit in the
log as in scope). Then read `git log <last-tag>..HEAD --oneline` and skim
the full messages of anything non-obvious (`git log <last-tag>..HEAD`). You
need this to do two things honestly: decide the version bump and write the
changelog entry. Skipping this and picking a bump number from vibes defeats
the point of the step.

## 2. Decide the version bump, then confirm it with the user

`project.yml` carries the version as `MARKETING_VERSION` under
`targets.Recorgi.settings.base`, as a two-part `major.minor` or three-part
`major.minor.patch` string (currently `"0.1.0"`). Use ordinary semver
judgment on what you read in step 1:

- **Patch** — bug fixes, internal cleanup, nothing a user would describe as
  a new feature.
- **Minor** — new user-facing capability (a new capture mode, a new
  settings card, a new hotkey — the kind of thing that belongs under
  "Added" in the changelog).
- **Major** — a breaking change. Be conservative here: this project is
  still pre-1.0 (`0.y.z`), and under semver's own convention for that range,
  even a breaking change normally just bumps the minor digit, not the
  major one — jumping to `1.0.0` is a deliberate statement ("this is
  stable/done now"), not just "something big changed." Only treat it as a
  major bump if the user clearly wants to declare that milestone.

Propose a specific new version number and a one-line reason, and get the
user's confirmation (an `AskUserQuestion` with the proposed bump as the
recommended option, plus the other plausible bump levels, works well) before
touching any files. This is a judgment call with a real consequence
(the tag is forever), so don't just proceed on your own guess.

## 3. Update the changelog

Add a new section at the top of `CHANGELOG.md`'s entries (right after the
intro paragraph, before the previous version's section), in the same
Keep-a-Changelog shape the existing entries use:

```markdown
## [X.Y.Z] - <today's date>

### Added
- ...

### Changed
- ...

### Fixed
- ...
```

Only include the subsections you actually have content for. Write it for
someone installing the app, not as a commit-log dump — translate "fix
TransportBar hit-testing" into what the user actually experienced, if it's
the kind of thing they'd notice at all. If a change is purely internal
(refactors, build-script tweaks) and genuinely has no user-visible effect,
it can be left out of the changelog even though it was in scope for the
version bump decision in step 2.

## 4. Bump the version and commit

Edit `project.yml`'s `MARKETING_VERSION` to the new version number, then
run `xcodegen generate` so the generated project and `Recorgi/Info.plist`
pick it up. Commit `project.yml` and `CHANGELOG.md` together:

```
git add project.yml CHANGELOG.md
git commit -m "Release vX.Y.Z"
```

(Plain message is enough — the changelog entry already has the detail.)

## 5. Build the dmg

```sh
./Scripts/make-dmg.sh
```

This builds the ad-hoc-signed Release configuration and packages it into
`dist/Recorgi-X.Y.Z.dmg`, with `CHANGELOG.md` bundled in alongside the app
automatically — nothing extra to do for that part. Confirm the script
printed `Done: dist/Recorgi-X.Y.Z.dmg` and that the version in the filename
matches what you just set; if it doesn't, something upstream (the
`project.yml` edit, or `xcodegen generate` not having been re-run) didn't
take, and you should find out why before tagging anything.

## 6. Tag the release commit

Tag the commit from step 4 — the one the dmg was actually built from, which
should also be `HEAD` at this point:

```sh
git tag -a vX.Y.Z -m "<short summary, can reuse the changelog entry text>"
```

## 7. Report back

Tell the user: the new version number and why (the bump level you chose),
the tag name, the `.dmg` path, and that nothing was pushed anywhere — this
repo currently has no git remote configured, and even if it did, pushing a
branch or a tag is a separate action that needs its own explicit go-ahead,
never bundled into cutting the release itself.
