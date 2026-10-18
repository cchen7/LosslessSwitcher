#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

signing_identity="${SIGNING_IDENTITY:--}"
development_team="${DEVELOPMENT_TEAM:-}"
notary_profile="${NOTARY_PROFILE:-}"
if [ "$signing_identity" = "-" ]; then
    if [ -n "$notary_profile" ]; then
        echo "Notarization requires a Developer ID Application signing identity." >&2
        exit 2
    fi
    # Ad-hoc signatures have no Team ID for hardened library validation.
    hardened_runtime=NO
    signing_options=0
    timestamp_options=(--timestamp=none)
else
    if [ -z "$development_team" ]; then
        echo "Set DEVELOPMENT_TEAM to the Team ID of your signing certificate." >&2
        exit 2
    fi
    hardened_runtime=YES
    signing_options=runtime
    timestamp_options=(--timestamp)
fi

xcodebuild -project Quality.xcodeproj -scheme LosslessSwitcher \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build -onlyUsePackageVersionsFromResolvedFile \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="$signing_identity" \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$development_team" \
    ENABLE_HARDENED_RUNTIME="$hardened_runtime" \
    OTHER_CODE_SIGN_FLAGS="${timestamp_options[*]}" -quiet build

app="$repo_root/.build/Build/Products/Release/LosslessSwitcher.app"
licenses="$app/Contents/Resources/Licenses"
mkdir -p "$licenses" "$repo_root/dist"
install -m 644 LICENSE "$licenses/LosslessSwitcher.txt"
for package in MediaRemote mediaremote-adapter ProtocolBuffer SimplyCoreAudio Sweep swift-atomics; do
    package_dir="$repo_root/.build/SourcePackages/checkouts/$package"
    license="$(find "$package_dir" -maxdepth 1 -type f \
        \( -iname LICENSE -o -iname LICENSE.md -o -iname LICENSE.txt \) -print -quit)"
    if [ -z "$license" ]; then
        echo "Missing license for $package; refusing to package without its notice." >&2
        exit 1
    fi
    install -m 644 "$license" "$licenses/$package.txt"
done
printf 'Source: https://github.com/cchen7/LosslessSwitcher/tree/%s\n' \
    "$(git rev-parse HEAD)" > "$licenses/Source.txt"

chmod -R u=rwX,go=rX "$app"
codesign --force --sign "$signing_identity" --options "$signing_options" \
    "${timestamp_options[@]}" "$app/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign "$signing_identity" --options "$signing_options" "${timestamp_options[@]}" \
    --entitlements Quality/Quality.entitlements "$app"
codesign --verify --strict --verbose=2 "$app/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --verify --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="$repo_root/dist/LosslessSwitcher-$version-macos27-arm64.zip"
ditto -c -k --keepParent "$app" "$archive"
if [ -n "$notary_profile" ]; then
    report="$repo_root/dist/notarization.json"
    if ! xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" \
        --wait --timeout 30m --output-format json > "$report"; then
        echo "Notarization submission or wait failed. Check dist/notarization.json before retrying." >&2
        if submission_id="$(plutil -extract id raw -o - "$report" 2>/dev/null)"; then
            xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" \
                "$repo_root/dist/notarization-log.json"
        fi
        exit 1
    fi
    if [ "$(plutil -extract status raw -o - "$report")" != "Accepted" ]; then
        submission_id="$(plutil -extract id raw -o - "$report")"
        xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" \
            "$repo_root/dist/notarization-log.json"
        echo "Notarization was not accepted. See dist/notarization-log.json for details." >&2
        exit 1
    fi
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    codesign --verify --strict --verbose=2 "$app/Contents/Frameworks/MediaRemoteAdapter.framework"
    codesign --verify --strict --verbose=2 "$app"
    spctl --assess --type execute --verbose=2 "$app"
    ditto -c -k --keepParent "$app" "$archive"
fi
(cd "$repo_root/dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'Release archive: %s\n' "$archive"
