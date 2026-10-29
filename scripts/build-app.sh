#!/usr/bin/env bash
# Release build of Grove into dist/Grove.app, signed with the project's team (Apple Development for now).
# Usage: scripts/build-app.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
xcodegen generate --quiet
xcodebuild -scheme Grove -configuration Release -destination 'platform=macOS' -derivedDataPath build -quiet build
rm -rf dist && mkdir -p dist
cp -R build/Build/Products/Release/Grove.app dist/Grove.app
codesign --verify --strict --verbose=2 dist/Grove.app
codesign -dv dist/Grove.app 2>&1 | rg 'Authority|TeamIdentifier|flags' || true
echo "built dist/Grove.app"
