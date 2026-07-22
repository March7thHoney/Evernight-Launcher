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

xcrun clang \
    -arch arm64 \
    -arch x86_64 \
    -dynamiclib \
    -mmacosx-version-min=12.0 \
    -O2 \
    -fblocks \
    "$ROOT/NativeToolsSource/evernight_cursor_release.m" \
    -framework AppKit \
    -framework CoreGraphics \
    -o "$ROOT/NativeTools/evernight-cursor-release.bin"
codesign --force --sign - "$ROOT/NativeTools/evernight-cursor-release.bin"
