#!/bin/bash
# 构建 Coding Plan Monitor.app 菜单栏应用
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="Coding Plan Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CodingPlanMonitor "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CodingPlanMonitor</string>
    <key>CFBundleDisplayName</key>
    <string>Coding Plan Monitor</string>
    <key>CFBundleIdentifier</key>
    <string>local.codingplanmonitor</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>CodingPlanMonitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ 构建完成: $APP"
echo "运行: open \"$APP\""
