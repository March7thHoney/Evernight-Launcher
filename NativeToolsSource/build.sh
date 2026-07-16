#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/NativeTools"
xcrun clang \
    -arch arm64 \
    -arch x86_64 \
    -dynamiclib \
    -mmacosx-version-min=12.0 \
    -O2 \
    "$ROOT/NativeToolsSource/evernight_host_blocker.c" \
    -lresolv \
    -o "$ROOT/NativeTools/evernight-host-blocker.bin"
codesign --force --sign - "$ROOT/NativeTools/evernight-host-blocker.bin"
