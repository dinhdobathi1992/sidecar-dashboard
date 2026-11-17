#!/bin/bash
# Build Sidecar Dash, install it to ~/Applications and start it at login (restarts if it crashes).
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Sidecar Dash.app"
LABEL="com.thi.sidecardash"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x SidecarDash 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SidecarDash "$APP/Contents/MacOS/SidecarDash"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sidecar Dash</string>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleExecutable</key><string>SidecarDash</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Sidecar Dash shows your upcoming events on the iPad dashboard.</string>
</dict></plist>
PLIST
# A fixed requirement keeps privacy permissions (Calendar) across rebuilds.
codesign --force --sign - -r='designated => identifier "'"$LABEL"'"' "$APP"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/SidecarDash</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $APP and started it."
