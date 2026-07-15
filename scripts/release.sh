#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="$ROOT_DIR/build/TokenMeter.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/export"
NOTARIZED_PATH="$ROOT_DIR/build/notarized"
SPARKLE_KEY_ACCOUNT="com.tokenmeter.app"
RELEASES_URL="https://github.com/TakeruF/token_meter/releases"

cd "$ROOT_DIR"

prepare_release() {
    xcodegen generate
    swift test --package-path TokenMeterCore

    rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ROOT_DIR/build/notarize-upload"
    xcodebuild archive \
        -project TokenMeter.xcodeproj \
        -scheme TokenMeter \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        -allowProvisioningUpdates

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist Config/ExportOptions-DeveloperID.plist \
        -allowProvisioningUpdates

    codesign --verify --deep --strict --verbose=2 "$EXPORT_PATH/TokenMeter.app"

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$ROOT_DIR/build/notarize-upload" \
        -exportOptionsPlist Config/ExportOptions-Notarize.plist \
        -allowProvisioningUpdates

    echo "Notarization was submitted. Run '$0 finish' after Apple accepts it."
}

find_sparkle_tool() {
    local tool_name="$1"
    local tool

    if [[ -n "${SPARKLE_BIN_DIR:-}" && -x "$SPARKLE_BIN_DIR/$tool_name" ]]; then
        echo "$SPARKLE_BIN_DIR/$tool_name"
        return
    fi

    tool="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" \
        -type f -print -quit 2>/dev/null)"
    if [[ -z "$tool" ]]; then
        echo "Sparkle tool '$tool_name' was not found. Resolve Swift packages first or set SPARKLE_BIN_DIR." >&2
        return 1
    fi
    echo "$tool"
}

generate_update_feed() {
    local zip_path="$1"
    local version="$2"
    local updates_dir="$ROOT_DIR/build/updates"
    local generate_appcast
    local generate_keys
    local key_dir
    local key_file
    generate_appcast="$(find_sparkle_tool generate_appcast)"
    generate_keys="$(find_sparkle_tool generate_keys)"
    key_dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenmeter-sparkle-key.XXXXXX")"
    key_file="$key_dir/private-key"

    mkdir -p "$updates_dir"
    cp "$zip_path" "$updates_dir/"
    cp "$ROOT_DIR/appcast.xml" "$updates_dir/appcast.xml"

    # generate_appcast may wait for a Keychain UI prompt when invoked directly.
    # Export the key with Sparkle's own tool, use it only for this signing step,
    # and remove the permission-restricted temporary directory even on failure.
    {
        umask 077
        "$generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -x "$key_file" >/dev/null
        "$generate_appcast" \
            --ed-key-file "$key_file" \
            --download-url-prefix "$RELEASES_URL/download/v$version/" \
            --link "$RELEASES_URL/tag/v$version" \
            --maximum-versions 5 \
            "$updates_dir"

        # generate_appcast applies the newest download prefix to every retained
        # archive. Point each full ZIP back to the release matching its version.
        sed -E -i '' \
            's#(releases/download/)v[^/]+/(TokenMeter-([0-9]+\.[0-9]+\.[0-9]+)\.zip)#\1v\3/\2#g' \
            "$updates_dir/appcast.xml"
    } always {
        rm -rf "$key_dir"
    }

    cp "$updates_dir/appcast.xml" "$ROOT_DIR/appcast.xml"
    echo "Updated feed: $ROOT_DIR/appcast.xml"
}

finish_release() {
    rm -rf "$NOTARIZED_PATH"
    xcodebuild -exportNotarizedApp \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$NOTARIZED_PATH"

    local app="$NOTARIZED_PATH/TokenMeter.app"
    local version
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    local zip_path="$ROOT_DIR/build/TokenMeter-$version.zip"

    codesign --verify --deep --strict --verbose=2 "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=4 "$app"

    rm -f "$zip_path"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
    generate_update_feed "$zip_path" "$version"
    shasum -a 256 "$zip_path"
    echo "Release artifact: $zip_path"
    echo "Next: publish GitHub tag v$version with this ZIP, then commit and push appcast.xml."
}

case "${1:-}" in
    prepare)
        prepare_release
        ;;
    finish)
        finish_release
        ;;
    *)
        echo "Usage: $0 prepare|finish" >&2
        exit 64
        ;;
esac
