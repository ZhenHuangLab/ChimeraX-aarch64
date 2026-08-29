#!/usr/bin/env bash
# Build UCSF ChimeraX as an aarch64 flatpak from this fork's arm-flatpak.yml.
#
# See BUILD_NOTES.aarch64.md for what the manifest patch fixes and why upstream
# publishes no ARM64 binary.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-fp-build.tmp}"
RUNTIME_VER=24.08
APPNAME=edu.ucsf.rbvi.ChimeraX

cd "$REPO_DIR"

for tool in flatpak flatpak-builder; do
    command -v "$tool" > /dev/null || {
        echo "missing $tool — run: sudo apt install flatpak flatpak-builder" >&2
        exit 1
    }
done

echo "== installing the aarch64 runtime and SDK"
flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub \
    "org.freedesktop.Platform//${RUNTIME_VER}" "org.freedesktop.Sdk//${RUNTIME_VER}"

# --disable-rofiles-fuse: the build does not need FUSE, and requiring it fails
# in containers and on hosts without the module loaded.
echo "== building (hours: NO_PREBUILT=1 compiles CPython, Qt6, numpy from source)"
flatpak-builder --force-clean --user --disable-rofiles-fuse "$BUILD_DIR" arm-flatpak.yml

echo "== installing into the user flatpak repo"
flatpak-builder --export-only --user --install --force-clean "$BUILD_DIR" arm-flatpak.yml

VERSION=$(flatpak run --user "$APPNAME" --nogui --exit --cmd version 2>/dev/null |
          sed -n 's/.*ChimeraX version: \([^ ]*\).*/\1/p' | head -1)
echo "== built ChimeraX ${VERSION:-unknown}"

mkdir -p dist
BUNDLE="dist/ChimeraX-${VERSION:-unknown}-linux-aarch64.flatpak"
flatpak build-bundle ~/.local/share/flatpak/repo "$BUNDLE" "$APPNAME" master
(cd dist && sha256sum "$(basename "$BUNDLE")" > SHA256SUMS)
echo "== bundle: $BUNDLE"
