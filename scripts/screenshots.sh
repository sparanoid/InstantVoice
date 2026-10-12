#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH="$REPO_ROOT/InstantVoice.xcodeproj"
SCHEME="InstantVoice"
BUILD_DIR="$REPO_ROOT/.screenshots-build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/InstantVoice Dev.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/InstantVoice Dev"
SPARKLE_UPDATER_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
ENTITLEMENTS="$REPO_ROOT/InstantVoice/InstantVoice.local.entitlements"
CLOCK_SOURCE="$SCRIPT_DIR/screenshots-fixed-clock.c"
CLOCK_LIBRARY="$BUILD_DIR/libscreenshots-fixed-clock.dylib"
BUNDLE_ID="com.sparanoid.InstantVoice.screenshots"
DISPLAY_P3_PROFILE="/System/Library/ColorSync/Profiles/Display P3.icc"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Each name must match a ScreenshotScene case in InstantVoice/App/Screenshots/ScreenshotMode.swift.
# Files are numbered by position: main-window scenes in sidebar order, onboarding scenes in flow order.
MAIN_SCENES=(dashboard insights transcribe history history-info modes mode dictionary models provider audio settings)
ONBOARDING_SCENES=(onboarding-permissions onboarding-microphone onboarding-model onboarding-api onboarding-shortcut
    onboarding-dictation onboarding-enhance onboarding-email onboarding-context onboarding-trust)
ALL_SCENES=("${MAIN_SCENES[@]}" "${ONBOARDING_SCENES[@]}")

SCENES=()
APPEARANCES=(light dark)
WINDOW_SIZE="1280x800"
OUTPUT_DIR="$REPO_ROOT/screenshots"
CLOCK_DATE="2026-10-13 09:41:00"
TIME_ZONE="America/Los_Angeles"
LANGUAGE="en"
LOCALE="en_US"
SETTLE_SECONDS="2"
INACTIVE=0
SHADOW=0
SKIP_BUILD=0
CURRENT_PID=""
READY_FILE=""

usage() {
    cat <<'EOF'
Usage:
  scripts/screenshots.sh [options]

Captures InstantVoice's main window and every onboarding step with demo data, one launch per scene,
for review and marketing. Runs use a Debug build copy with its own bundle identifier, home folder, and
clock, so they never touch your data or your running app, and every run renders the same content.

The app stays in the background, so you can keep working while it runs (about 5 seconds per scene).
Windows still draw in their active style unless you pass --inactive.

Options:
  --scene <name>          Capture only this scene; repeat for more (default: all, see --list).
                          "main" and "onboarding" select every scene in that group.
  --appearance <mode>     light, dark, or both (default: both).
  --size <WxH>            Main window size in points (default: 1280x800, which captures 2560x1600 on
                          Retina). Onboarding keeps its own fixed-width window.
  --output-dir <dir>      Where to write <appearance>/<NN>-<scene>.png and onboarding-<NN>-<step>.png
                          (default: ./screenshots).
  --date <date>           Clock at launch, "YYYY-MM-DD HH:MM:SS" (default: 2026-10-13 09:41:00).
  --time-zone <zone>      Time zone for the clock and dates (default: America/Los_Angeles).
  --language <code>       App language (default: en).
  --locale <id>           Formatting locale (default: en_US).
  --settle <seconds>      Wait after opening a scene before capturing (default: 2).
  --inactive              Draw windows in their inactive style, as when another app is in front.
  --shadow                Keep the window shadow on a transparent margin.
  --skip-build            Reuse the last build in .screenshots-build.
  --list                  List the scenes and exit.
  -h, --help              Show this help.

Examples:
  make screenshots
  make screenshots SCREENSHOT_ARGS="--scene history --appearance dark"
  make screenshots SCREENSHOT_ARGS="--scene onboarding"
  scripts/screenshots.sh --skip-build --scene dashboard --scene settings
EOF
}

log() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# Prints a scene's file name, numbered within its group, or fails for an unknown scene.
output_name() {
    local index
    for index in "${!MAIN_SCENES[@]}"; do
        if [[ "${MAIN_SCENES[$index]}" == "$1" ]]; then
            printf '%02d-%s.png' $((index + 1)) "$1"
            return 0
        fi
    done
    for index in "${!ONBOARDING_SCENES[@]}"; do
        if [[ "${ONBOARDING_SCENES[$index]}" == "$1" ]]; then
            printf 'onboarding-%02d-%s.png' $((index + 1)) "${1#onboarding-}"
            return 0
        fi
    done
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scene)
            [[ $# -ge 2 ]] || fail "--scene requires a name"
            case "$2" in
                main) SCENES+=("${MAIN_SCENES[@]}") ;;
                onboarding) SCENES+=("${ONBOARDING_SCENES[@]}") ;;
                *) SCENES+=("$2") ;;
            esac
            shift 2
            ;;
        --appearance)
            [[ $# -ge 2 ]] || fail "--appearance requires light, dark, or both"
            case "$2" in
                light | dark) APPEARANCES=("$2") ;;
                both) APPEARANCES=(light dark) ;;
                *) fail "Unknown appearance: $2" ;;
            esac
            shift 2
            ;;
        --size)
            [[ $# -ge 2 ]] || fail "--size requires WIDTHxHEIGHT"
            WINDOW_SIZE="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || fail "--output-dir requires a path"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --date)
            [[ $# -ge 2 ]] || fail "--date requires \"YYYY-MM-DD HH:MM:SS\""
            CLOCK_DATE="$2"
            shift 2
            ;;
        --time-zone)
            [[ $# -ge 2 ]] || fail "--time-zone requires a zone name"
            TIME_ZONE="$2"
            shift 2
            ;;
        --language)
            [[ $# -ge 2 ]] || fail "--language requires a code"
            LANGUAGE="$2"
            shift 2
            ;;
        --locale)
            [[ $# -ge 2 ]] || fail "--locale requires an identifier"
            LOCALE="$2"
            shift 2
            ;;
        --settle)
            [[ $# -ge 2 ]] || fail "--settle requires seconds"
            SETTLE_SECONDS="$2"
            shift 2
            ;;
        --inactive)
            INACTIVE=1
            shift
            ;;
        --shadow)
            SHADOW=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --list)
            printf '%s\n' "${ALL_SCENES[@]}"
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

[[ ${#SCENES[@]} -gt 0 ]] || SCENES=("${ALL_SCENES[@]}")
for scene in "${SCENES[@]}"; do
    output_name "$scene" >/dev/null || fail "Unknown scene: $scene (see --list)"
done
[[ "$WINDOW_SIZE" =~ ^([0-9]+)x([0-9]+)$ ]] || fail "--size must look like 1280x800"
WINDOW_WIDTH="${BASH_REMATCH[1]}"
WINDOW_HEIGHT="${BASH_REMATCH[2]}"
[[ "$SETTLE_SECONDS" =~ ^[0-9]+(\.[0-9]+)?$ ]] || fail "--settle must be a number of seconds"
EPOCH="$(TZ="$TIME_ZONE" date -j -f '%Y-%m-%d %H:%M:%S' "$CLOCK_DATE" +%s 2>/dev/null)" \
    || fail "--date must look like \"2026-10-13 09:41:00\""

for command in xcodebuild clang codesign open screencapture sips plutil defaults pkill; do
    require_command "$command"
done
[[ -f "$DISPLAY_P3_PROFILE" ]] || fail "Display P3 color profile not found: $DISPLAY_P3_PROFILE"

stop_app() {
    local pid="$1"
    local deadline=$((SECONDS + 10))
    kill "$pid" 2>/dev/null || return 0
    while kill -0 "$pid" 2>/dev/null; do
        if ((SECONDS >= deadline)); then
            kill -9 "$pid" 2>/dev/null || true
            return 0
        fi
        sleep 0.1
    done
}

cleanup() {
    if [[ -n "$CURRENT_PID" ]]; then
        stop_app "$CURRENT_PID"
    fi
    # Matches only the copy in .screenshots-build, never an InstantVoice Dev launched from Xcode.
    pkill -f "$APP_EXECUTABLE" 2>/dev/null || true
    if [[ -d "$APP_PATH" ]]; then
        "$LSREGISTER" -u "$SPARKLE_UPDATER_PATH" >/dev/null 2>&1 || true
        "$LSREGISTER" -u "$APP_PATH" >/dev/null 2>&1 || true
    fi
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
}

build_app() {
    log "Building the Debug app (log: ${BUILD_DIR#"$REPO_ROOT"/}/build.log)"
    mkdir -p "$BUILD_DIR"
    # Ad-hoc signing with the local entitlements needs no provisioning profile and has no Keychain access group,
    # so the copy can't read saved API keys.
    if ! xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        CODE_SIGN_IDENTITY=- \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM= \
        PROVISIONING_PROFILE_SPECIFIER= \
        CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
        build >"$BUILD_DIR/build.log" 2>&1; then
        tail -n 30 "$BUILD_DIR/build.log" >&2
        fail "Build failed; see $BUILD_DIR/build.log"
    fi
}

prepare_app() {
    [[ -d "$APP_PATH" ]] || fail "No build at $APP_PATH; run once without --skip-build."
    # Its own bundle identifier gives the copy separate defaults, window state, and privacy settings.
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleIdentifier $BUNDLE_ID" \
        -c "Set :CFBundleName InstantVoice" \
        -c "Set :CFBundleDisplayName InstantVoice" \
        "$APP_PATH/Contents/Info.plist"
    # Signed without the hardened runtime, which would refuse the fixed-clock library.
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH" >/dev/null 2>&1 \
        || fail "Couldn't re-sign $APP_PATH"

    if [[ ! -f "$CLOCK_LIBRARY" || "$CLOCK_SOURCE" -nt "$CLOCK_LIBRARY" ]]; then
        clang -dynamiclib -O2 -Wall -o "$CLOCK_LIBRARY" "$CLOCK_SOURCE" \
            || fail "Couldn't build the fixed-clock library"
    fi
}

wait_for_ready() {
    local ready_file="$1"
    local deadline=$((SECONDS + 120))
    while [[ ! -s "$ready_file" ]]; do
        ((SECONDS < deadline)) || return 1
        sleep 0.2
    done
}

# Opens a scene in a fresh launch and waits until the app reports it ready. Sets READY_FILE and CURRENT_PID.
launch_scene() {
    local appearance="$1"
    local scene="$2"
    local work_dir="$RUN_DIR/$appearance-$scene"
    READY_FILE="$work_dir/ready.json"
    mkdir -p "$work_dir/home"

    # Every launch starts from empty defaults and an empty home folder.
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

    local active_appearance="YES"
    [[ "$INACTIVE" == 1 ]] && active_appearance="NO"
    # -g keeps the app in the background; screenshot mode draws the active style without taking focus.
    open -n -g -F \
        --env "CFFIXED_USER_HOME=$work_dir/home" \
        --env "TZ=$TIME_ZONE" \
        --env "DYLD_INSERT_LIBRARIES=$CLOCK_LIBRARY" \
        --env "SCREENSHOT_EPOCH=$EPOCH" \
        "$APP_PATH" --args \
        -ScreenshotScene "$scene" \
        -ScreenshotReadyFile "$READY_FILE" \
        -ScreenshotWindowSize "$WINDOW_SIZE" \
        -ScreenshotSettleDelay "$SETTLE_SECONDS" \
        -ScreenshotActiveAppearance "$active_appearance" \
        -AppAppearancePreference "$appearance" \
        -AppleLanguages "($LANGUAGE)" \
        -AppleLocale "$LOCALE" \
        -AppleAccentColor 4 \
        -AppleShowScrollBars WhenScrolling \
        -AppleReduceDesktopTinting YES \
        -ApplePersistenceIgnoreState YES

    wait_for_ready "$READY_FILE" || fail "The app didn't open $scene within 2 minutes (run files: $RUN_DIR)"
    local error
    error="$(plutil -extract error raw -o - "$READY_FILE" 2>/dev/null || true)"
    [[ -z "$error" ]] || fail "$error"
    CURRENT_PID="$(plutil -extract pid raw -o - "$READY_FILE")"
}

capture_scene() {
    local appearance="$1"
    local scene="$2"
    local output="$OUTPUT_DIR/$appearance/$(output_name "$scene")"
    mkdir -p "$OUTPUT_DIR/$appearance"

    launch_scene "$appearance" "$scene"

    local window_id scale window_width window_height
    window_id="$(plutil -extract windowID raw -o - "$READY_FILE")"
    scale="$(plutil -extract scale raw -o - "$READY_FILE")"
    window_width="$(plutil -extract width raw -o - "$READY_FILE")"
    window_height="$(plutil -extract height raw -o - "$READY_FILE")"

    # Main-window scenes open at the requested size; onboarding keeps its own.
    if [[ "$scene" != onboarding-* ]] \
        && ! awk -v w="$window_width" -v h="$window_height" -v rw="$WINDOW_WIDTH" -v rh="$WINDOW_HEIGHT" \
            'BEGIN { exit !(w == rw && h == rh) }'; then
        fail "$scene opened at ${window_width}x${window_height} points instead of $WINDOW_SIZE"
    fi

    local capture_flags=(-x "-l$window_id")
    [[ "$SHADOW" == 1 ]] || capture_flags+=(-o)
    screencapture "${capture_flags[@]}" "$output" || fail "Couldn't capture $scene"
    stop_app "$CURRENT_PID"
    CURRENT_PID=""

    # Screen captures carry the display's profile; one shared profile keeps colors consistent across Macs.
    sips --matchTo "$DISPLAY_P3_PROFILE" "$output" >/dev/null || fail "Couldn't convert $output to Display P3"

    if [[ "$SHADOW" == 0 ]]; then
        local expected actual
        expected="$(awk -v w="$window_width" -v h="$window_height" -v s="$scale" 'BEGIN { printf "%dx%d", w * s, h * s }')"
        actual="$(sips -g pixelWidth -g pixelHeight "$output" | awk '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { printf "%sx%s", w, h }')"
        [[ "$actual" == "$expected" ]] || fail "$output is $actual, expected $expected"
    fi
    if [[ "$scale" != "2" && "$scale" != "2.0" && -z "${WARNED_SCALE:-}" ]]; then
        printf 'warning: the window was on a %sx display; use a Retina display for 2x screenshots\n' "$scale" >&2
        WARNED_SCALE=1
    fi
    printf '  %s\n' "${output#"$REPO_ROOT"/}"
}

trap cleanup EXIT
pkill -f "$APP_EXECUTABLE" 2>/dev/null || true

if [[ "$SKIP_BUILD" == 0 ]]; then
    build_app
fi
prepare_app

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/instantvoice-screenshots.XXXXXX")"
log "Capturing ${#SCENES[@]} scene(s) in ${#APPEARANCES[@]} appearance(s) at $CLOCK_DATE ($TIME_ZONE)"
# Light Mode ignores the wallpaper with the launch argument, but Dark Mode follows the system setting.
if [[ "${APPEARANCES[*]}" == *dark* ]] \
    && [[ "$(defaults read -g AppleReduceDesktopTinting 2>/dev/null || echo 0)" != 1 ]]; then
    echo "  Dark Mode windows take a tint from your wallpaper; turn off wallpaper tinting in System Settings > Appearance for neutral ones."
fi
for appearance in "${APPEARANCES[@]}"; do
    for scene in "${SCENES[@]}"; do
        capture_scene "$appearance" "$scene"
    done
done

log "Saved $((${#SCENES[@]} * ${#APPEARANCES[@]})) screenshot(s) to ${OUTPUT_DIR#"$REPO_ROOT"/}"
