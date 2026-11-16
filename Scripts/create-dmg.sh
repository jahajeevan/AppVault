#!/bin/zsh
set -euo pipefail

# Run only after a signed Universal archive has been exported to the supplied path.
if [[ $# -ne 2 ]]; then
  print -u2 'Usage: create-dmg.sh /absolute/path/AppVault.app /absolute/path/AppVault.dmg'
  exit 64
fi
app_path="$1"
dmg_path="$2"
[[ -d "$app_path" ]] || { print -u2 'App bundle not found.'; exit 66; }
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
staging="$(mktemp -d /private/tmp/appvault-dmg.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app_path" "$staging/AppVault.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname 'AppVault' -srcfolder "$staging" -ov -format UDZO "$dmg_path"
