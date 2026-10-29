#!/usr/bin/env bash
# Developer ID signing + notarization of dist/Grove.app. Needs, once:
#   - a "Developer ID Application" certificate in the login keychain (paid Apple Developer account)
#   - xcrun notarytool store-credentials grove-notary --apple-id <id> --team-id <team> --password <app-specific>
# Usage: scripts/notarize.sh "Developer ID Application: Name (TEAMID)"
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
identity="${1:?usage: notarize.sh \"Developer ID Application: Name (TEAMID)\"}"
codesign --force --deep --options runtime --timestamp --sign "$identity" dist/Grove.app
ditto -c -k --keepParent dist/Grove.app dist/Grove.zip
xcrun notarytool submit dist/Grove.zip --keychain-profile grove-notary --wait
xcrun stapler staple dist/Grove.app
spctl --assess --type execute --verbose dist/Grove.app
echo "notarized dist/Grove.app"
