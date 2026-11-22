#!/bin/bash
# Builds ALVR's client core (alvr_client_core, Rust, MIT) for iPhone and iPad and for the Simulator, into
# Native/alvr/AlvrClientCore.xcframework: the same ALVR as Pocket XR for Android (21.0.0-dev14, commit e8ca92b, the
# streamer the Pocket XR PC helper installs) with Android's one patch (alvr-pocketxr.patch). ALVR connects only to its
# own version.
#
# Runs on a Mac with Rust (CI caches the result: the first build takes a while). Not kept in git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT=e8ca92b
WORK="${ALVR_WORK:-$ROOT/.build/alvr-src}"
OUT="$ROOT/Native/alvr/AlvrClientCore.xcframework"

if [ ! -d "$WORK/.git" ]; then
    git clone --filter=blob:none https://github.com/alvr-org/ALVR.git "$WORK"
fi
cd "$WORK"
git checkout -q --force "$COMMIT"
git apply "$ROOT/Native/alvr/alvr-pocketxr.patch"
echo "build-alvr: ALVR $(git log --oneline -1) with Pocket XR's patch"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim
export IPHONEOS_DEPLOYMENT_TARGET=17.0
for target in aarch64-apple-ios aarch64-apple-ios-sim; do
    # No default features: link-stdcpp-shared is Android's.
    cargo build --release -p alvr_client_core --no-default-features --lib --target "$target" 2>&1 | grep -vE "^\s+(Compiling|Downloaded|Downloading)" | tail -25
    ls -la "target/$target/release/libalvr_client_core.a"
done

HEADERS="$(mktemp -d)"
cp "$ROOT/Native/alvr/alvr_client_core.h" "$HEADERS/"
rm -rf "$OUT"
xcodebuild -create-xcframework \
    -library "target/aarch64-apple-ios/release/libalvr_client_core.a" -headers "$HEADERS" \
    -library "target/aarch64-apple-ios-sim/release/libalvr_client_core.a" -headers "$HEADERS" \
    -output "$OUT"
git checkout -q --force "$COMMIT"
du -sh "$OUT"
echo "build-alvr: made $OUT"
