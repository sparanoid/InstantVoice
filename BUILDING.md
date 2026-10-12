# Building InstantVoice

## Requirements

- macOS 26.0 or later
- Xcode 26 or later with Command Line Tools
- Git

## Local Build

```bash
git clone https://github.com/sparanoid/InstantVoice.git
cd InstantVoice
make local
open ~/Downloads/InstantVoice.app
```

`make local` prepares `whisper.xcframework` in `~/InstantVoice-Dependencies`, builds Release in `.local-build`, and copies `InstantVoice.app` to `~/Downloads`.

It uses `LocalBuild.xcconfig`, `InstantVoice.local.entitlements`, and the `LOCAL_BUILD` Swift flag. Without an override, it uses the only available Apple Development identity or falls back to ad-hoc signing when none or multiple are found.

Choose an identity explicitly:

```bash
make local LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

Force ad-hoc signing:

```bash
make local LOCAL_CODESIGN_IDENTITY=-
```

Local builds do not include iCloud dictionary sync or automatic updates. Ad-hoc builds may require macOS permissions again after rebuilding.

## Other Commands

- `make check` — verify required tools
- `make whisper` — prepare `whisper.xcframework`
- `make build` — build the standard Debug configuration
- `make dev` — build and launch `InstantVoice Dev.app`
- `make run` — launch `~/Downloads/InstantVoice.app`, or the first app found in DerivedData
- `make release` — create the signed release package
- `make release-setup` — configure release notarization credentials
- `make screenshots` — capture app screenshots with demo data into `screenshots/`
- `make clean` — remove `~/InstantVoice-Dependencies`
- `make help` — list all commands

## Build with Xcode

```bash
make setup
open InstantVoice.xcodeproj
```

Select the `InstantVoice` scheme. Run builds `InstantVoice Dev.app`; Archive uses Release. `LOCAL_BUILD` applies only through `make local`.

## Screenshots

`make screenshots` captures the main window, one scene per launch, in Light and Dark Mode, as `screenshots/<appearance>/<NN>-<scene>.png`. At the default 1280×800 window size, captures come out at 2560×1600 on a Retina display. They're plain window captures with transparent rounded corners, converted to Display P3, ready for review or marketing.

The script runs a Debug build in `.screenshots-build` as `com.sparanoid.InstantVoice.screenshots`, with a scratch home folder and demo data, so it never touches your data, Keychain, or running app. Each launch pins the clock to Tuesday, October 13, 2026, 9:41 AM Pacific, along with language, locale, accent color, and scroll bars, so every run renders the same content. The app comes to the front for each capture; leave the keyboard and mouse alone until it finishes, or pass `--background` to keep the window inactive.

```bash
make screenshots SCREENSHOT_ARGS="--scene history --appearance dark"
scripts/screenshots.sh --list
scripts/screenshots.sh --help
```

Scenes are defined by `ScreenshotScene` in `InstantVoice/App/Screenshots/ScreenshotMode.swift`, and their content by `ScreenshotDemoData`. Add a new scene to both and to `ALL_SCENES` in `scripts/screenshots.sh`.

## Merging Upstream

[VoiceInk](https://github.com/Beingpax/VoiceInk) names its project, folders, and types `VoiceInk`. Git's rename detection applies most upstream edits to the renamed files.

- Run `git config merge.directoryRenames true` once so new upstream files in existing folders land under `InstantVoice/`.
- Files in new upstream folders, and edits to files Git can't match to their renamed copy (reported as modify/delete conflicts), stay under `VoiceInk/`. Move or port them into `InstantVoice/`; Xcode doesn't compile `VoiceInk/`.
- Rename any new `VoiceInk` identifiers to `InstantVoice`.

UserDefaults and keychain keys keep their `VoiceInk` names on purpose.

### LLMkit

[LLMkit](https://github.com/Beingpax/LLMkit), upstream's provider API library, is vendored in `Packages/LLMkit` with `git subtree`, and Xcode builds it as a local package. Edit it in place; `git log -- Packages/LLMkit` lists the local changes.

When an upstream merge changes the LLMkit pin in `project.pbxproj` or `Package.resolved`, keep this repo's side of those lines. Then pull the revision upstream pinned, and Git merges it with the local changes:

```bash
git subtree pull --prefix=Packages/LLMkit https://github.com/Beingpax/LLMkit.git <revision> --squash
```

## Troubleshooting

- Run `make check` to verify the required tools.
- Run `make whisper` if the framework is missing.
- If several Apple Development identities exist, set `LOCAL_CODESIGN_IDENTITY` explicitly.
- For additional help, open a [GitHub issue](https://github.com/sparanoid/InstantVoice/issues).
