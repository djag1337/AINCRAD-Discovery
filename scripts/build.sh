#!/bin/zsh
# Builds AINCRAD Discovery (Release) outside iCloud-synced ~/Documents and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
DERIVED="$HOME/Library/Caches/AINCRAD-Discovery-build"
xcodebuild -project AINCRADDiscovery.xcodeproj -scheme AINCRADDiscovery -configuration Release -derivedDataPath "$DERIVED" -skipPackagePluginValidation build -quiet
rm -rf "/Applications/AINCRAD Discovery.app"
ditto "$DERIVED/Build/Products/Release/AINCRAD Discovery.app" "/Applications/AINCRAD Discovery.app"
codesign --verify "/Applications/AINCRAD Discovery.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/AINCRAD Discovery.app"
echo "Installed /Applications/AINCRAD Discovery.app"
