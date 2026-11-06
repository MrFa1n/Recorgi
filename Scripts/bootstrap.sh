#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

# The deployment target is macOS 15, but compiling the current sources
# requires the macOS 27 SDK (including mixesAudioWithMicrophone).
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: full Xcode is required; Command Line Tools alone are not enough." >&2
    echo "Install Xcode 27 or later, then select it in Xcode > Settings > Locations > Command Line Tools." >&2
    exit 1
fi

if ! SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version); then
    echo "error: could not find the selected Xcode's macOS SDK." >&2
    exit 1
fi
SDK_MAJOR=${SDK_VERSION%%.*}
case "$SDK_MAJOR" in
    ''|*[!0-9]*)
        echo "error: could not recognize macOS SDK version: $SDK_VERSION" >&2
        exit 1
        ;;
esac
if [ "$SDK_MAJOR" -lt 27 ]; then
    echo "error: macOS SDK 27 or later is required; selected SDK is $SDK_VERSION." >&2
    echo "Select Xcode 27 or later in Xcode > Settings > Locations > Command Line Tools." >&2
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "error: XcodeGen is missing and Homebrew is not installed." >&2
        echo "Install Homebrew from https://brew.sh, then run: brew install xcodegen" >&2
        echo "Or install XcodeGen directly: https://github.com/yonaskolb/XcodeGen" >&2
        exit 1
    fi
    echo "XcodeGen not found — installing via Homebrew…"
    brew install xcodegen
fi

xcodegen generate
echo "Done (macOS SDK $SDK_VERSION). No-certificate build:"
echo "  xcodebuild -project Recorgi.xcodeproj -scheme Recorgi -configuration Release -derivedDataPath .build/release build"
echo "For Debug builds, first create the local signing identity described in README.md."
