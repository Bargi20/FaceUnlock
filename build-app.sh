#!/bin/zsh
# Builds NotchUnlock.app (release) and installs it in /Applications.
#   ./build-app.sh          build for this Mac and install
#   ./build-app.sh --dist   build a universal app (Apple silicon + Intel) and
#                           zip it in dist/ for a GitHub release, without installing
set -e
cd "$(dirname "$0")"

DIST=0
[[ "$1" == "--dist" ]] && DIST=1

if (( DIST )); then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NotchUnlock"
else
    swift build -c release
    BIN=.build/release/NotchUnlock
fi

APP="build/NotchUnlock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchUnlock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/FaceEmbedding.mlmodelc "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --deep --sign - --entitlements Resources/NotchUnlock.entitlements "$APP"

if (( DIST )); then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    mkdir -p dist
    ZIP="dist/NotchUnlock-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    rm -rf "$APP"
    echo "packaged: $ZIP"
    exit 0
fi

# Install and drop the build copy, so Spotlight and Privacy settings show only one app.
rm -rf "/Applications/NotchUnlock.app"
rm -rf "/Applications/Face Unlock.app" # the app's old name, before 1.2
mv "$APP" /Applications/
echo "installed: /Applications/NotchUnlock.app"
