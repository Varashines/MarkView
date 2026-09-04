#!/bin/bash

export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"

APP_NAME="MarkView"
DISPLAY_NAME="MarkView"
INSTALL_DIR="/Applications"
SCHEME="mdViewer"
PROJECT="mdViewer.xcodeproj"

DO_CLEAN=false
FORCE=false
BUILD_MODE="release"

for arg in "$@"; do
    case "$arg" in
        --clean)   DO_CLEAN=true; FORCE=true ;;
        --debug)   BUILD_MODE="debug" ;;
        --force|-f) FORCE=true ;;
        --help|-h)
            echo "Usage: ./install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --clean      Clean build"
            echo "  --debug      Debug build (skips icon/packaging)"
            echo "  --force,-f   Force rebuild"
            echo "  --help       Show this help"
            exit 0
            ;;
    esac
done

# --- Source hash check ---
HASH_FILE=".build/.source_hash_$BUILD_MODE"
mkdir -p .build
SOURCE_HASH=$(find . -name "*.swift" -o -name "*.css" | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | cut -d' ' -f1)

if [ "$FORCE" = false ] && [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" == "$SOURCE_HASH" ]; then
    EXISTING_APP="$INSTALL_DIR/$APP_NAME.app"
    if [ -d "$EXISTING_APP" ]; then
        echo "No changes detected. $APP_NAME is already installed."
        exit 0
    fi
fi

# --- Clean ---
if [ "$DO_CLEAN" = true ]; then
    echo "Cleaning..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" clean 2>/dev/null
fi

# --- Build ---
echo "Building $APP_NAME..."

BUILD_DIR=".build/Build/Products"
if [ "$BUILD_MODE" = "debug" ]; then
    CONFIG="Debug"
else
    CONFIG="Release"
fi

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -derivedDataPath .build/Build \
    SYMROOT="$(pwd)/.build/Build/Products" \
    clean build 2>&1 | tail -3

# Find the built app
APP_PATH=$(find "$BUILD_DIR" -name "*.app" -type d -maxdepth 3 | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Build failed — no .app found."
    exit 1
fi

echo "Built: $APP_PATH"

# --- Debug mode ---
if [ "$BUILD_MODE" = "debug" ]; then
    echo "Debug build complete."
    exit 0
fi

# --- Generate Icon ---
echo "Generating app icon..."
swift generate_icon.swift

if [ -d "AppIcon.iconset" ]; then
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

# --- Install to /Applications ---
FINAL_APP="$INSTALL_DIR/$APP_NAME.app"
echo "Installing to $INSTALL_DIR..."
rm -rf "$FINAL_APP"
cp -R "$APP_PATH" "$FINAL_APP"

# --- Apply Icon ---
if [ -f "AppIcon.icns" ]; then
    RESOURCES="$FINAL_APP/Contents/Resources"
    mkdir -p "$RESOURCES"
    cp AppIcon.icns "$RESOURCES/"
    rm -f AppIcon.icns

    PLIST="$FINAL_APP/Contents/Info.plist"
    if [ -f "$PLIST" ]; then
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$PLIST" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$PLIST" 2>/dev/null
    fi
    echo "Icon applied."
fi

# --- Codesign ---
codesign --force --sign - "$FINAL_APP"

# --- Save hash ---
echo "$SOURCE_HASH" > "$HASH_FILE"

echo "Done! $DISPLAY_NAME is in /Applications."
