#!/bin/zsh
# Renders the README demo GIFs (docs/unlock.gif, docs/failure.gif) from the
# app's real animation. Needs ffmpeg (brew install ffmpeg).
set -e
cd "$(dirname "$0")/.."
swift build -c release
FRAMES=$(mktemp -d)
mkdir -p docs
for scenario in unlock failure; do
    .build/release/NotchUnlock --render-demo $scenario "$FRAMES/$scenario"
    ffmpeg -loglevel error -y -framerate 50 -i "$FRAMES/$scenario/frame%04d.png" \
        -vf "scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
        -loop 0 "docs/$scenario.gif"
    echo "docs/$scenario.gif"
done
rm -rf "$FRAMES"
