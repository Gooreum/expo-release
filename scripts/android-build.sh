#!/bin/bash
#
# Expo 프로젝트 Android: prebuild → 업로드 키로 서명한 AAB. 업로드는 fastlane `android upload`가 한다.
#
#   ANDROID_KEYSTORE_PATH=… ANDROID_KEYSTORE_PASSWORD=… ANDROID_KEY_ALIAS=… ANDROID_KEY_PASSWORD=… \
#     bash scripts/expo-release/android-build.sh
#
# 서명 값은 Gradle 속성으로 넘긴다. 속성 이름은 설정 android.signing_props가 정한다 —
# 프로젝트의 서명 config plugin(app/build.gradle에 release 서명을 넣는 것)이 읽는 이름과 같아야 한다.
# 결과 AAB가 debug 키로 서명돼 있으면 멈춘다(플러그인이 속성을 못 읽고 debug로 폴백한 경우).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
export_env

PACKAGE=$(cfg android.package)
OUT=build/expo-release/android
AAB=android/app/build/outputs/bundle/release/app-release.aab
LOG=$OUT/gradle.log
mkdir -p "$OUT"

read -r VERSION _ CODE < <(bash "$HERE/version.sh" get)
echo "── Android $VERSION ($CODE) ──"

: "${ANDROID_KEYSTORE_PATH:?업로드 키스토어 경로}" "${ANDROID_KEYSTORE_PASSWORD:?}" "${ANDROID_KEY_ALIAS:?}" "${ANDROID_KEY_PASSWORD:?}"
# -P 대신 ORG_GRADLE_PROJECT_<이름> 환경변수로 넘긴다 — 명령줄(프로세스 목록)에 비밀번호가 안 남는다
prop() { cfg "android.signing_props.$1"; }
export "ORG_GRADLE_PROJECT_$(prop store_file)=$(cd "$(dirname "$ANDROID_KEYSTORE_PATH")" && pwd)/$(basename "$ANDROID_KEYSTORE_PATH")"
export "ORG_GRADLE_PROJECT_$(prop store_password)=$ANDROID_KEYSTORE_PASSWORD"
export "ORG_GRADLE_PROJECT_$(prop key_alias)=$ANDROID_KEY_ALIAS"
export "ORG_GRADLE_PROJECT_$(prop key_password)=$ANDROID_KEY_PASSWORD"

npx expo prebuild -p android --clean --no-install
grep -q "applicationId '$PACKAGE'\|applicationId \"$PACKAGE\"" android/app/build.gradle \
  || { echo "android/app/build.gradle의 applicationId가 $PACKAGE가 아니다 — env 확인" >&2; exit 1; }

# lintVital은 CI 메모리에서 자주 죽고 릴리스 판정에 쓰지 않는다
if ! (cd android && ./gradlew bundleRelease -x lintVitalRelease -x lintVitalAnalyzeRelease > "../$LOG" 2>&1); then
  grep -E "error:|FAILURE|What went wrong" -A3 "$LOG" | head -20 >&2 || true
  echo "Gradle 실패 — 전체 로그: $LOG" >&2; exit 1
fi
[ -f "$AAB" ] || { echo "AAB가 없다: $AAB" >&2; exit 1; }

certs=$(keytool -printcert -jarfile "$AAB" 2>/dev/null || true)
if [ -z "$certs" ] || grep -q "CN=Android Debug" <<<"$certs"; then
  echo "AAB가 업로드 키로 서명되지 않았다(debug 키이거나 서명 없음) — 서명 plugin·속성 이름 확인" >&2; exit 1
fi
grep -m1 "SHA1:" <<<"$certs" | sed 's/^\s*/업로드 키 /'

# 빌드에 박힌 runtimeVersion이 태그에 남길 fingerprint와 같은지. 다르면 OTA가 이 빌드에 조용히 안 내려간다.
# policy "fingerprint"면 expo-updates가 assets/fingerprint 파일에 hash를 넣는다(app.manifest엔 runtimeVersion이 없다).
if [ -n "${FINGERPRINT:-}" ]; then
  rv=$(unzip -p "$AAB" base/assets/fingerprint 2>/dev/null || true)
  echo "runtimeVersion ${rv:-없음}"
  [ "$rv" = "$FINGERPRINT" ] || { echo "빌드 runtimeVersion $rv ≠ fingerprint $FINGERPRINT — 올리지 않는다" >&2; exit 1; }
fi

verify=$(cfg android.verify)
if [ -n "$verify" ]; then
  AAB_PATH="$AAB" bash -c "$verify" || { echo "android.verify 실패 — 올리지 않는다" >&2; exit 1; }
fi

cp "$AAB" "$OUT/app-release.aab"
echo "AAB: $OUT/app-release.aab"
