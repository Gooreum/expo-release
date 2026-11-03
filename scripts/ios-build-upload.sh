#!/bin/bash
#
# Expo 프로젝트 iOS: prebuild → 서명 없이 아카이브 → API 키 클라우드 서명으로 내보내며 업로드.
#
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=…/AuthKey_….p8 bash scripts/expo-release/ios-build-upload.sh
#
# DESTINATION=export면 올리지 않고 서명된 IPA만 만든다 — 서명이 되는지만 볼 때.
#
# 서명 없이 아카이브하는 이유: 서명하며 아카이브하면 일회용 러너마다 개발 인증서를 새로 만들어
# 계정 인증서 한도에 걸린다("Choose a certificate to revoke"). 배포 서명은 내보내기에서 한 번만 한다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
export_env
# 빌드 중 expo-updates가 fingerprint를 다시 계산하면 네이티브 디렉터리·빌드 환경 때문에 값이 달라진다.
# EAS Build처럼 계획 단계에서 잰 hash(= eas update가 쓰는 값)를 그대로 박는다.
[ -n "${FINGERPRINT:-}" ] && export EXPO_UPDATES_FINGERPRINT_OVERRIDE="$FINGERPRINT"

BUNDLE_ID=$(cfg ios.bundle_id); TEAM_ID=$(cfg ios.team_id)
ARCHIVE=build/expo-release/ios/App.xcarchive
EXPORT=build/expo-release/ios/export
LOG=build/expo-release/ios/archive.log
mkdir -p build/expo-release/ios

read -r VERSION BUILD _ < <(bash "$HERE/version.sh" get)
echo "── iOS $VERSION ($BUILD) ──"

npx expo prebuild -p ios --clean --no-install
(cd ios && pod install)

WS=$(ls -d ios/*.xcworkspace | head -1)
SCHEME=$(basename "$WS" .xcworkspace)
rm -rf "$ARCHIVE"
if ! xcodebuild archive -workspace "$WS" -scheme "$SCHEME" -configuration Release \
     -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
     PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" DEVELOPMENT_TEAM="$TEAM_ID" \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" > "$LOG" 2>&1; then
  grep -E "error:|^Error" "$LOG" | head -10 >&2 || true
  tail -30 "$LOG" >&2
  echo "아카이브 실패 — 전체 로그: $LOG" >&2; exit 1
fi

APP=$(ls -d "$ARCHIVE"/Products/Applications/*.app | head -1)
bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
av=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
ab=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
echo "archive: $bid $av ($ab)"
[ "$bid" = "$BUNDLE_ID" ] || { echo "번들 ID $bid ≠ 설정 $BUNDLE_ID" >&2; exit 1; }
[ "$av" = "$VERSION" ] && [ "$ab" = "$BUILD" ] || { echo "아카이브 버전 $av ($ab) ≠ app.json $VERSION ($BUILD)" >&2; exit 1; }

# 빌드에 박힌 runtimeVersion이 태그에 남길 fingerprint와 같은지. 다르면 OTA가 이 빌드에 조용히 안 내려간다.
# policy "fingerprint"면 expo-updates가 EXUpdates.bundle/fingerprint 파일에 hash를 넣는다(app.manifest엔 runtimeVersion이 없다).
if [ -n "${FINGERPRINT:-}" ]; then
  rv=$(cat "$APP/EXUpdates.bundle/fingerprint" 2>/dev/null || true)
  echo "runtimeVersion ${rv:-없음}"
  [ "$rv" = "$FINGERPRINT" ] || { echo "빌드 runtimeVersion $rv ≠ fingerprint $FINGERPRINT — 올리지 않는다" >&2; exit 1; }
fi

# 프로젝트별 검사 (예: JS 번들에 인라인된 백엔드가 prod인지). APP_PATH·BUNDLE_PATH를 넘긴다.
verify=$(cfg ios.verify)
if [ -n "$verify" ]; then
  APP_PATH="$APP" BUNDLE_PATH="$APP/main.jsbundle" bash -c "$verify" || { echo "ios.verify 실패 — 올리지 않는다" >&2; exit 1; }
fi

AUTH=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "${ASC_KEY_ID:?}" -authenticationKeyIssuerID "${ASC_ISSUER_ID:?}")
fi
OPTIONS="$(mktemp -d)/ExportOptions.plist"
# manageAppVersionAndBuildNumber를 켜 두면 번호가 겹칠 때 조용히 올려서 소스와 어긋난다
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>${DESTINATION:-upload}</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
rm -rf "$EXPORT"; mkdir -p "$EXPORT"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
     -exportPath "$EXPORT" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} > "$EXPORT.log" 2>&1; then
  tail -30 "$EXPORT.log" >&2
  echo "내보내기 실패 — 전체 로그: $EXPORT.log" >&2; exit 1
fi
grep -E "Upload succeeded|EXPORT SUCCEEDED" "$EXPORT.log"
