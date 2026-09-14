#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/Bar Cheat Sheets.app"

cd "$PROJECT_DIR"
swift build -c release --disable-sandbox

mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/release/BarCheatSheets" "$APP_DIR/Contents/MacOS/BarCheatSheets"
cp "Support/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"
