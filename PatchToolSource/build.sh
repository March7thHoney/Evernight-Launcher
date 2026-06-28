#!/bin/sh
# Rebuild the universal patch-cli binary into ../PatchTool/. Self-contained: needs only the Go toolchain.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
DST="$DIR/../PatchTool"
cd "$DIR"
mkdir -p build
GOTOOLCHAIN=auto GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o build/patch-cli-arm64 ./cmd/patch-cli
GOTOOLCHAIN=auto GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o build/patch-cli-amd64 ./cmd/patch-cli
lipo -create -output build/patch-cli build/patch-cli-arm64 build/patch-cli-amd64
cp build/patch-cli "$DST/patch-cli"
chmod +x "$DST/patch-cli"
# Strip Finder info / resource forks so app codesign won't reject the bundle.
xattr -cr "$DST/patch-cli"
echo "staged to $DST:"
file "$DST/patch-cli"
