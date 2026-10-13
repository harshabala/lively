#!/bin/bash

set -euo pipefail

# Prefer full Xcode when present (best SDK/tooling). Otherwise fall back to
# Command Line Tools — UI uses ViewState instead of the SwiftUI @State macro
# so CLT builds succeed without SwiftUIMacros.
# Respect an explicitly chosen toolchain first: CI selects a specific Xcode via
# xcode-select, and /Applications/Xcode.app on runners is an older default.
selected_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -n "${DEVELOPER_DIR:-}" && -d "${DEVELOPER_DIR}" ]]; then
    :
elif [[ "${selected_dir}" == *.app/Contents/Developer && -d "${selected_dir}" ]]; then
    export DEVELOPER_DIR="${selected_dir}"
elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -d "/Library/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
    echo "ℹ️  Building with Command Line Tools (full Xcode not found)."
else
    echo "❌ No Xcode or Command Line Tools found."
    echo "   Install Xcode from the App Store, or: xcode-select --install"
    exit 1
fi

# Configuration
# Single source of truth for the version: Info.plist in the repo root.
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
APP_BUILD="$(plutil -extract CFBundleVersion raw Info.plist)"
APP_NAME="Lively"
OUTPUT_DIR="${LIVELY_OUTPUT_DIR:-/private/tmp/LivelyOutput}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
EXECUTABLE_NAME="LivelyApp"
WORKSPACE_CACHE=".build/package-cache"
BUILD_PATH="${WORKSPACE_CACHE}/swift-build"
BUILD_DIR="${BUILD_PATH}/release"

mkdir -p "${WORKSPACE_CACHE}/swiftpm" "${WORKSPACE_CACHE}/swiftpm-security" "${WORKSPACE_CACHE}/clang" "${BUILD_PATH}"

export SWIFTPM_CACHE_PATH="${PWD}/${WORKSPACE_CACHE}/swiftpm"
export SWIFTPM_CONFIG_PATH="${PWD}/${WORKSPACE_CACHE}/swiftpm-security"
export CLANG_MODULE_CACHE_PATH="${PWD}/${WORKSPACE_CACHE}/clang"
export SWIFT_BUILD_PATH="${PWD}/${BUILD_PATH}"

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Build with Swift Package Manager
echo "🔨 Building Release configuration..."
swift build -c release --build-path "${BUILD_PATH}"

# New SwiftPM layouts put products under out/Products/Release (with a
# "release" symlink). Older layouts used release/ directly. Prefer the
# known product path, then fall back to a broad search.
if [[ -x "${BUILD_PATH}/release/${EXECUTABLE_NAME}" ]]; then
    EXECUTABLE_PATH="${BUILD_PATH}/release/${EXECUTABLE_NAME}"
elif [[ -x "${BUILD_PATH}/out/Products/Release/${EXECUTABLE_NAME}" ]]; then
    EXECUTABLE_PATH="${BUILD_PATH}/out/Products/Release/${EXECUTABLE_NAME}"
else
    EXECUTABLE_PATH="$(find -L "${BUILD_PATH}" -name "${EXECUTABLE_NAME}" -type f -perm +111 2>/dev/null | head -n 1)"
fi
if [ -z "${EXECUTABLE_PATH}" ]; then
    echo "❌ Could not find built executable ${EXECUTABLE_NAME} under ${BUILD_PATH}"
    exit 1
fi
echo "   Found executable: ${EXECUTABLE_PATH}"

# Create App Bundle Structure
echo "📦 Creating App Bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy Executable
echo "📋 Copying executable..."
cp "${EXECUTABLE_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

if [ -f "AppIcon.icns" ]; then
    echo "🖼️ Copying App Icon..."
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.lively.app</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/> <!-- This hides the app from the Dock -->
</dict>
</plist>
EOF

# Code Signing (Ad-hoc)
# Required for SMAppService to work locally
echo "🔏 Signing application..."
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
codesign --force --deep --options runtime --sign - --entitlements entitlements.plist "${APP_BUNDLE}"
xattr -d com.apple.FinderInfo "${APP_BUNDLE}" 2>/dev/null || true

echo "✅ Packaging complete!"
echo "🚀 App located at: ${APP_BUNDLE}"
echo "   You can run it with: open ${APP_BUNDLE}"
