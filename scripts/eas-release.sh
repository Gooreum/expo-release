#!/bin/bash
#
# GitHub Actions를 못 쓸 때(이번 달 무료 분 소진 등) 스토어 빌드를 EAS Build로 대신 만든다.
# 빌드는 Expo 서버에서 돈다 — 이 Mac은 소스를 올리고 결과를 받아 검사·업로드만 한다.
# 워크플로의 ios/android 잡과 같은 결과를 낸다: 같은 번호 규칙, 같은 fingerprint, 같은 검사, 같은 태그.
#
#   bash scripts/expo-release/eas-release.sh start  <ios|android> <release|auto> [--meta] [--screenshots]
#   bash scripts/expo-release/eas-release.sh finish <ios|android>     빌드를 기다려 검사 → 업로드 → 태그
#                                                    (DRY_RUN=1이면 검사까지만 — 올리지 않는다)
#   bash scripts/expo-release/eas-release.sh status <ios|android>
#   bash scripts/expo-release/eas-release.sh abort  <ios|android>     임시 worktree·상태를 지운다
#
#   release: app.json 번호 그대로 (릴리스 커밋)    auto: 번호를 태그에서 이어 받아 테스트 업로드
#
# start는 빌드를 큐에 넣고 바로 끝난다(무료 플랜은 대기가 길다). finish는 오래 걸리니 백그라운드로 돌린다.
# 커밋은 HEAD(또는 EAS_COMMIT) — origin에 올라가 있어야 한다(태그가 그 커밋을 가리킨다).
#
# 설정 eas.*:
#   asc_app_id, asc_key_path, asc_key_id, asc_issuer_id   iOS 업로드(EAS Submit)·버전 상태 확인
#   play_json_path                                          Android 업로드(fastlane supply)
#   android_keystore                                        Android 업로드 키(비밀번호는 ~/.gradle/gradle.properties)
#   ios_p12, ios_p12_password_file, ios_profile             iOS 배포 인증서·App Store 프로필(setup-ios-signing.sh가 만든다)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

CMD="${1:?start|finish|status|abort}"; P="${2:?ios|android}"; shift 2
[[ "$P" =~ ^(ios|android)$ ]] || { echo "플랫폼은 ios|android" >&2; exit 1; }
STATE_DIR="$ROOT/build/expo-release/eas/$P"; STATE="$STATE_DIR/state.env"
EAS=$(cfg update.eas_cli); EAS=${EAS:-eas-cli@latest}
expand() { python3 -c 'import os,sys;print(os.path.expanduser(sys.argv[1]))' "$1"; }
eas() { (cd "$WT" && EAS_NO_VCS=1 EAS_PROJECT_ROOT="$WT" npx -y "$EAS" "$@"); }
save() { printf '%s=%q\n' "$1" "$2" >> "$STATE"; }
asc_env() {
  export ASC_KEY_ID=$(cfg eas.asc_key_id) ASC_ISSUER_ID=$(cfg eas.asc_issuer_id)
  export ASC_KEY_PATH=$(expand "$(cfg eas.asc_key_path)")
  [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] && [ -f "$ASC_KEY_PATH" ] \
    || { echo "설정 eas.asc_key_id·asc_issuer_id·asc_key_path가 필요하다(키 파일이 있어야 한다)" >&2; exit 1; }
}
cleanup() {
  [ -f "$STATE" ] && . "$STATE"
  [ -n "${WT:-}" ] && git worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf "$STATE_DIR"; git worktree prune
}

case "$CMD" in
start)
  ACT="${1:?release|auto}"; shift
  [[ "$ACT" =~ ^(release|auto)$ ]] || { echo "모드는 release|auto" >&2; exit 1; }
  META=false; SHOTS=false
  for a in "$@"; do case "$a" in --meta) META=true ;; --screenshots) META=true; SHOTS=true ;; esac; done
  [ "$(cfg "$P.enabled")" = true ] || { echo "$P가 설정에서 꺼져 있다" >&2; exit 1; }
  [ ! -f "$STATE" ] || { echo "진행 중인 EAS 빌드가 있다 — finish 또는 abort 먼저: $STATE" >&2; exit 1; }

  COMMIT=$(git rev-parse "${EAS_COMMIT:-HEAD}")
  git fetch -q origin --tags
  [ -n "$(git branch -r --contains "$COMMIT" 2>/dev/null)" ] || { echo "$COMMIT가 origin에 없다 — 먼저 푸시하라" >&2; exit 1; }

  mkdir -p "$STATE_DIR"; WT="$STATE_DIR/wt"; : > "$STATE"
  save WT "$WT"; save COMMIT "$COMMIT"; save ACT "$ACT"; save META "$META"; save SHOTS "$SHOTS"
  git worktree add -q --detach "$WT" "$COMMIT"
  for f in $(python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('local_files',[])))" "$CONFIG"); do
    [ -e "$f" ] || { echo "local_files의 $f가 없다" >&2; cleanup; exit 1; }
    cp "$f" "$WT/$f"
  done
  cp "$CONFIG" "$WT/.expo-release.json"   # 커밋 안 한 설정(eas.* 등)도 쓴다
  CONFIG=.expo-release.json
  cd "$WT"
  echo "── npm ci (fingerprint·앱 설정용, 끝나면 지운다) ──"
  npm ci --silent >/dev/null 2>&1 || { echo "npm ci 실패" >&2; cd "$ROOT"; cleanup; exit 1; }
  export_env

  if [ "$ACT" = auto ]; then
    if [ "$P" = ios ]; then
      asc_env
      v=$(bash "$HERE/version.sh" latest ios); n=$(bash "$HERE/version.sh" next ios)
      out=$(mktemp); OUT="$out" fastlane ios version_state version:"$v" >/dev/null
      [ "$(cat "$out")" = open ] || v=$(bash "$HERE/version.sh" bump-patch "$v")
      bash "$HERE/version.sh" set "$v" --ios "$n" >/dev/null
    else
      bash "$HERE/version.sh" set "$(bash "$HERE/version.sh" latest android)" \
        --android "$(bash "$HERE/version.sh" next android)" >/dev/null
    fi
  fi
  # prebuild 전에 잰다 — 워크플로·OTA와 같은 조건
  FP=$(bash "$HERE/fingerprint.sh" hash "$P")
  read -r V B C < <(bash "$HERE/version.sh" get)
  TAG="$P-v$V-$([ "$P" = ios ] && echo "$B" || echo "$C")"
  git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "태그 $TAG가 이미 있다 — 같은 번호로 다시 올릴 수 없다" >&2; cd "$ROOT"; cleanup; exit 1; }
  save FP "$FP"; save TAG "$TAG"; save VERSION "$V"

  # eas.json(이 빌드 전용 프로필) — 저장소에 있던 것에 expo-release 프로필만 더한다. 커밋하지 않는다.
  python3 - "$FP" "$CONFIG" <<'PY'
import json, os, sys
fp, cfgp = sys.argv[1], sys.argv[2]
cfg = json.load(open(cfgp))
d = json.load(open("eas.json")) if os.path.exists("eas.json") else {}
d.setdefault("cli", {}).setdefault("appVersionSource", "local")
# NODE_ENV=production을 빌드 서버에 넘기면 devDependencies가 안 깔린다 — env_files는 .env로 복사해 읽힌다
env = {k: str(v) for k, v in cfg.get("env", {}).items() if k != "NODE_ENV"}
env["EXPO_UPDATES_FINGERPRINT_OVERRIDE"] = fp
d.setdefault("build", {})["expo-release"] = {
    "distribution": "store", "autoIncrement": False,
    "env": env,
    # android-build.sh와 같게: lintVital은 릴리스 판정에 안 쓰고(번역 누락 같은 경고로 멈춘다), 폰은 arm뿐이다
    "android": {"buildType": "app-bundle",
                "gradleCommand": ":app:bundleRelease -x lintVitalRelease -x lintVitalAnalyzeRelease -PreactNativeArchitectures=arm64-v8a,armeabi-v7a"},
}
e = cfg.get("eas", {})
d.setdefault("submit", {})["expo-release"] = {"ios": {
    "ascAppId": str(e.get("asc_app_id", "")),
    "ascApiKeyPath": os.path.expanduser(e.get("asc_key_path", "")),
    "ascApiKeyId": e.get("asc_key_id", ""), "ascApiKeyIssuerId": e.get("asc_issuer_id", ""),
}}
json.dump(d, open("eas.json", "w"), indent=2)
PY
  # 서명은 로컬 자격증명(credentials.json)으로 넘긴다 — EAS에 미리 넣어 둘 것도, 대화형 단계도 없다.
  #   Android: 워크플로와 같은 업로드 키. 설정 eas.android_keystore + ~/.gradle/gradle.properties의 android.signing_props 값
  #   iOS:     설정 eas.ios_p12(배포 인증서) + eas.ios_p12_password_file + eas.ios_profile(App Store 프로필)
  # 값은 파일로만 옮기고 출력하지 않는다.
  mkdir -p credentials; pwf=""
  if [ "$P" = android ]; then
    ks=$(expand "$(cfg eas.android_keystore)")
    [ -f "$ks" ] || { echo "설정 eas.android_keystore의 키스토어가 없다" >&2; cd "$ROOT"; cleanup; exit 1; }
    cp "$ks" credentials/upload.keystore
  else
    p12=$(expand "$(cfg eas.ios_p12)"); pwf=$(expand "$(cfg eas.ios_p12_password_file)"); prof=$(expand "$(cfg eas.ios_profile)")
    [ -f "$p12" ] && [ -f "$pwf" ] && [ -f "$prof" ] \
      || { echo "설정 eas.ios_p12·ios_p12_password_file·ios_profile 파일이 필요하다 — setup-ios-signing.sh" >&2; cd "$ROOT"; cleanup; exit 1; }
    cp "$p12" credentials/dist.p12; cp "$prof" credentials/appstore.mobileprovision
  fi
  python3 - "$CONFIG" "$P" "$pwf" <<'PY' || { echo "서명 값을 읽지 못했다(~/.gradle/gradle.properties 또는 p12 암호 파일)" >&2; cd "$ROOT"; cleanup; exit 1; }
import json, os, sys
cfg, plat, pwf = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
if plat == "android":
    props = cfg["android"]["signing_props"]; kv = {}
    for line in open(os.path.expanduser("~/.gradle/gradle.properties")):
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1); kv[k.strip()] = v.strip()
    c = {"android": {"keystore": {"keystorePath": "credentials/upload.keystore",
         "keystorePassword": kv[props["store_password"]], "keyAlias": kv[props["key_alias"]],
         "keyPassword": kv[props["key_password"]]}}}
else:
    c = {"ios": {"provisioningProfilePath": "credentials/appstore.mobileprovision",
         "distributionCertificate": {"path": "credentials/dist.p12", "password": open(pwf).read().strip()}}}
fd = os.open("credentials.json", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, json.dumps(c).encode()); os.close(fd)
d = json.load(open("eas.json")); d["build"]["expo-release"]["credentialsSource"] = "local"
json.dump(d, open("eas.json", "w"), indent=2)
PY

  # gitignore된 비밀 파일(local_files)도 빌드 서버로 올라가야 앱 설정이 읽힌다
  for f in $(python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('env_files',[])))" "$CONFIG"); do cp "$f" .env; done
  { cat .gitignore 2>/dev/null; echo; echo "build/"
    for f in $(python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('local_files',[])))" "$CONFIG") \
             .env eas.json credentials.json credentials/upload.keystore credentials/dist.p12 credentials/appstore.mobileprovision; do echo "!$f"; done
  } > .easignore

  # @expo/fingerprint는 eas.json·.easignore를 소스로 센다 — 워크플로(두 파일 없음)와 같은 값이 나오게 뺀다.
  # fingerprint.config.js 자체는 hash에 안 들어가므로 여기서 고쳐도 기존 값은 그대로다.
  python3 - <<'PY'
import os
p = "fingerprint.config.js"
line = "  ignorePaths: ['eas.json', '.easignore'],  // expo-release EAS 대체 경로가 빌드 때만 만드는 파일\n"
s = open(p).read() if os.path.exists(p) else "module.exports = {\n};\n"
if "'eas.json'" not in s:
    assert "module.exports = {" in s, "fingerprint.config.js 모양이 예상과 다르다"
    s = s.replace("module.exports = {\n", "module.exports = {\n" + line, 1)
    open(p, "w").write(s)
PY
  FP2=$(bash "$HERE/fingerprint.sh" hash "$P")
  [ "$FP2" = "$FP" ] || { echo "EAS 파일을 만든 뒤 fingerprint가 바뀌었다($FP → $FP2) — 빌드하지 않는다" >&2; cd "$ROOT"; cleanup; exit 1; }

  echo "── EAS Build $P $TAG ($ACT) fingerprint $FP ──"
  out=$(eas build -p "$P" --profile expo-release --non-interactive --no-wait --json 2>"$STATE_DIR/build.err") \
    || { tail -20 "$STATE_DIR/build.err" >&2; echo "EAS Build 시작 실패" >&2; cd "$ROOT"; cleanup; exit 1; }
  ID=$(python3 -c 'import json,sys;d=json.load(sys.stdin);print((d[0] if isinstance(d,list) else d)["id"])' <<<"$out")
  save ID "$ID"
  echo "build=$ID — 진행 상황: bash scripts/expo-release/eas-release.sh status $P"
  ;;

status)
  [ -f "$STATE" ] || { echo "진행 중인 EAS 빌드 없음"; exit 0; }
  . "$STATE"
  eas build:view "$ID" --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["status"], d.get("appVersion"), d.get("appBuildVersion"))'
  ;;

finish)
  [ -f "$STATE" ] || { echo "진행 중인 EAS 빌드가 없다 — start 먼저" >&2; exit 1; }
  . "$STATE"; cd "$WT"; export_env
  while :; do
    st=$(eas build:view "$ID" --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["status"], (d.get("artifacts") or {}).get("buildUrl") or "-")') || st="UNKNOWN -"
    read -r S URL <<<"$st"
    case "$S" in
      FINISHED) break ;;
      ERRORED|CANCELED) echo "EAS Build $S — 로그: https://expo.dev (빌드 $ID)" >&2; exit 1 ;;
      *) echo "$(date +%H:%M) $S"; sleep 60 ;;
    esac
  done

  if [ "$P" = android ]; then
    ART="$STATE_DIR/app-release.aab"; curl -sSL -o "$ART" "$URL"
    certs=$(keytool -printcert -jarfile "$ART" 2>/dev/null || true)
    { [ -n "$certs" ] && ! grep -q "CN=Android Debug" <<<"$certs"; } || { echo "AAB가 업로드 키로 서명되지 않았다 — EAS Android 자격증명 확인" >&2; exit 1; }
    grep -m1 "SHA1:" <<<"$certs" | sed 's/^\s*/업로드 키 /'
    rv=$(unzip -p "$ART" base/assets/fingerprint 2>/dev/null || true)
    verify=$(cfg android.verify); [ -z "$verify" ] || AAB_PATH="$ART" bash -c "$verify" || { echo "android.verify 실패 — 올리지 않는다" >&2; exit 1; }
  else
    ART="$STATE_DIR/app.ipa"; curl -sSL -o "$ART" "$URL"
    X="$STATE_DIR/ipa"; rm -rf "$X"; unzip -q "$ART" -d "$X"
    APP=$(ls -d "$X"/Payload/*.app | head -1)
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
    av=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
    ab=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
    echo "ipa: $bid $av ($ab)"
    [ "$bid" = "$(cfg ios.bundle_id)" ] || { echo "번들 ID $bid ≠ 설정 $(cfg ios.bundle_id)" >&2; exit 1; }
    [ "ios-v$av-$ab" = "$TAG" ] || { echo "IPA 버전 $av ($ab) ≠ $TAG" >&2; exit 1; }
    rv=$(cat "$APP/EXUpdates.bundle/fingerprint" 2>/dev/null || true)
    verify=$(cfg ios.verify); [ -z "$verify" ] || APP_PATH="$APP" BUNDLE_PATH="$APP/main.jsbundle" bash -c "$verify" || { echo "ios.verify 실패 — 올리지 않는다" >&2; exit 1; }
  fi
  echo "runtimeVersion ${rv:-없음}"
  [ "$rv" = "$FP" ] || { echo "빌드 runtimeVersion $rv ≠ fingerprint $FP — 올리지 않는다" >&2; exit 1; }
  if [ "${DRY_RUN:-}" = 1 ]; then
    echo "DRY_RUN — 검사까지만 했다. 올리지 않고 태그도 안 찍는다. 결과물: $ART"; cd "$ROOT"
    [ -f "$STATE" ] && . "$STATE"; git worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -f "$STATE"; exit 0
  fi

  if [ "$P" = android ]; then
    export PLAY_JSON_KEY_PATH=$(expand "$(cfg eas.play_json_path)")
    [ -f "$PLAY_JSON_KEY_PATH" ] || { echo "설정 eas.play_json_path의 파일이 없다" >&2; exit 1; }
    extra=(); [ "$ACT" = auto ] && { t=$(cfg auto.android_track); extra=(track:"${t:-internal}" release_status:completed); }
    fastlane android upload aab:"$ART" metadata:"$META" ${extra[@]+"${extra[@]}"}
  else
    asc_env
    echo "── EAS Submit → App Store Connect ──"
    eas submit -p ios --id "$ID" --profile expo-release --non-interactive
    [ "$META" = true ] && fastlane ios metadata screenshots:"$SHOTS" version:"$VERSION"
  fi

  git -C "$ROOT" tag -a "$TAG" "$COMMIT" -m "fingerprint=$FP"
  git -C "$ROOT" push -q origin "$TAG"
  echo "✅ $TAG 업로드 ($ACT, EAS Build $ID)"
  cd "$ROOT"; cleanup
  ;;

abort) cleanup; echo "지웠다: $STATE_DIR" ;;
*) echo "사용법: eas-release.sh start|finish|status|abort <ios|android> …" >&2; exit 1 ;;
esac
