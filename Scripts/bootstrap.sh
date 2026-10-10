#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen not found — installing via Homebrew…"
    brew install xcodegen
fi

xcodegen generate
echo "Done. Open Recorgi.xcodeproj to build and run."
