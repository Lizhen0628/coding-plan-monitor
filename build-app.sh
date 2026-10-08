#!/bin/bash
# 构建 macOS 菜单栏应用 Coding Plan Monitor.app（经 Xcode 工程，ad-hoc 签名）
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "❌ 需要 xcodegen：brew install xcodegen"; exit 1; }

(cd Apple && xcodegen generate)

xcodebuild -project Apple/CodingPlanMonitor.xcodeproj \
  -scheme CodingPlanMonitor-macOS \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  build -quiet

APP="Coding Plan Monitor.app"
rm -rf "$APP"
cp -R "build/DerivedData/Build/Products/Release/Coding Plan Monitor.app" "$APP"

echo "✅ 构建完成: $APP"
echo "运行: open \"$APP\""
