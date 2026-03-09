#!/usr/bin/env bash
# Build and install the development Flatpak locally, then run it.
# Usage: ./build-devel-flatpak.sh [--no-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building Flutter release bundle..."
flutter build linux --release

echo "==> Building Devel Flatpak..."
flatpak-builder \
  --user \
  --force-clean \
  --install \
  /tmp/lanis-flatpak-devel-build \
  packaging/flatpak/io.github.alessioc42.lanis.Devel.yml

if [[ "${1:-}" != "--no-run" ]]; then
  echo "==> Running Devel Flatpak (output below)..."
  flatpak run io.github.alessioc42.lanis.Devel
fi
