#!/usr/bin/env bash
set -euo pipefail

app_path="${APP_PATH:-}"
output_ipa="${OUTPUT_IPA:-unsigned.ipa}"

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "APP_PATH must point to a built .app directory." >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Info.plist" 2>/dev/null || true)" != "Miaopu" ]]; then
  echo "App Info.plist is missing or has an unexpected executable name." >&2
  exit 1
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist" 2>/dev/null || true)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Info.plist" 2>/dev/null || true)"
[[ "$bundle_id" == "com.liansishen.miaopu" && -n "$version" ]] || {
  echo "App bundle identifier or version is invalid." >&2
  exit 1
}

binary="$app_path/Miaopu"
if [[ ! -f "$binary" ]] || ! /usr/bin/lipo "$binary" -verify_arch arm64 >/dev/null; then
  echo "App executable is missing arm64 architecture." >&2
  exit 1
fi

if [[ -e "$app_path/_CodeSignature" ]] || /usr/bin/codesign -dv "$app_path" >/dev/null 2>&1; then
  echo "App must not be code signed." >&2
  exit 1
fi
validate_widget() {
  local widget="$1"
  [[ -f "$widget/Info.plist" && -f "$widget/MiaopuWidgets" ]] || {
    echo "Widget extension is missing from the app." >&2
    exit 1
  }
  /usr/bin/lipo "$widget/MiaopuWidgets" -verify_arch arm64 >/dev/null
  [[ ! -e "$widget/_CodeSignature" ]] && ! /usr/bin/codesign -dv "$widget" >/dev/null 2>&1 || {
    echo "Widget extension must not be code signed." >&2
    exit 1
  }
}
validate_widget "$app_path/PlugIns/MiaopuWidgets.appex"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload"
/usr/bin/ditto "$app_path" "$stage/Payload/Miaopu.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$stage/Payload" "$output_ipa"
/usr/bin/unzip -tq "$output_ipa" >/dev/null

# Validate the packaged copy as well as the source app.
/usr/bin/unzip -q "$output_ipa" -d "$stage/verify"
packaged_app="$stage/verify/Payload/Miaopu.app"
[[ -d "$packaged_app" && -f "$packaged_app/Info.plist" ]] || {
  echo "IPA does not contain Payload/Miaopu.app with Info.plist." >&2
  exit 1
}
/usr/bin/lipo "$packaged_app/Miaopu" -verify_arch arm64 >/dev/null
[[ ! -e "$packaged_app/_CodeSignature" ]] || {
  echo "Packaged app unexpectedly contains a code signature." >&2
  exit 1
}
if /usr/bin/codesign -dv "$packaged_app" >/dev/null 2>&1; then
  echo "Packaged app is signed." >&2
  exit 1
fi
validate_widget "$packaged_app/PlugIns/MiaopuWidgets.appex"

(cd "$(dirname "$output_ipa")" && /usr/bin/shasum -a 256 "$(basename "$output_ipa")") > "${output_ipa}.sha256"
echo "Created and validated unsigned IPA: $output_ipa"
