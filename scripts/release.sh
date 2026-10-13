#!/bin/bash
# Build Lively.app, zip it, upload to a GitHub Release, and print the Gatekeeper command.
#
# Usage:
#   ./scripts/release.sh v1.0.0
#
# Requires: full Xcode, gh CLI authenticated to harshabala/Lively

set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "Usage: ./scripts/release.sh <tag> [--dry-run]   e.g. v1.0.0"
  echo "  --dry-run  build and zip locally; never contact GitHub"
  exit 1
fi
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

VERSION="${TAG#v}"
ZIP="Lively-${VERSION}-macOS.zip"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./package.sh

echo "📦 Creating ${ZIP}..."
ditto -c -k --sequesterRsrc --keepParent \
  /private/tmp/LivelyOutput/Lively.app \
  "${ROOT}/${ZIP}"

SHA=$(shasum -a 256 "${ZIP}" | awk '{print $1}')
echo "SHA256: ${SHA}"

if [ "$DRY_RUN" = "1" ]; then
  echo "Dry run: skipping GitHub release upload."
elif command -v gh &>/dev/null; then
  if ! gh release view "$TAG" --repo harshabala/Lively &>/dev/null; then
    gh release create "$TAG" --repo harshabala/Lively --title "Lively ${TAG}" \
      --notes-file CHANGELOG.md
  fi
  gh release upload "$TAG" "${ZIP}" --repo harshabala/Lively --clobber
  echo "✅ Uploaded to https://github.com/harshabala/Lively/releases/tag/${TAG}"
fi

echo ""
echo "Update Casks/lively.rb with:"
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA}\""
echo ""
echo "Tell users to clear Gatekeeper quarantine after install:"
echo "  xattr -dr com.apple.quarantine /Applications/Lively.app"