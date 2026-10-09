# Building InstantVoice

## Requirements

- macOS 15.0 or later
- Xcode with Command Line Tools
- Git

## Local Build

```bash
git clone https://github.com/sparanoid/InstantVoice.git
cd InstantVoice
make local
open ~/Downloads/InstantVoice.app
```

`make local` prepares `whisper.xcframework` in `~/InstantVoice-Dependencies`, builds Release in `.local-build`, and copies `InstantVoice.app` to `~/Downloads`.

It uses `LocalBuild.xcconfig`, `VoiceInk.local.entitlements`, and the `LOCAL_BUILD` Swift flag. Without an override, it uses the only available Apple Development identity or falls back to ad-hoc signing when none or multiple are found.

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
- `make clean` — remove `~/InstantVoice-Dependencies`
- `make help` — list all commands

## Build with Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme. Run builds `InstantVoice Dev.app`; Archive uses Release. `LOCAL_BUILD` applies only through `make local`.

The Xcode project, scheme, targets, Swift module, and source folders keep their upstream `VoiceInk` names so changes from [VoiceInk](https://github.com/Beingpax/VoiceInk) keep merging cleanly. Everything that ships is named InstantVoice.

## Troubleshooting

- Run `make check` to verify the required tools.
- Run `make whisper` if the framework is missing.
- If several Apple Development identities exist, set `LOCAL_CODESIGN_IDENTITY` explicitly.
- For additional help, open a [GitHub issue](https://github.com/sparanoid/InstantVoice/issues).
