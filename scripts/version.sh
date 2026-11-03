#!/bin/bash
#
# Expo app.json의 버전을 읽고 쓴다.
#   expo.version            두 플랫폼 공통 마케팅 버전
#   expo.ios.buildNumber    iOS 빌드 번호 (문자열)
#   expo.android.versionCode  Android 빌드 번호 (정수)
#
#   bash scripts/expo-release/version.sh get [커밋]          → "1.0.11 5 2"
#   bash scripts/expo-release/version.sh set <버전> [--ios N] [--android N]
#
# 쓰기는 정규식으로 그 줄만 바꾼다(들여쓰기·키 순서 유지).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "$0")/lib.sh"

FILE=$(cfg app_config); FILE=${FILE:-app.json}

case "${1:-}" in
  get)
    if [ -n "${2:-}" ]; then content=$(git show "$2:$FILE"); else content=$(cat "$FILE"); fi
    printf '%s' "$content" | python3 -c '
import json, sys
e = json.load(sys.stdin)["expo"]
v = e.get("version"); b = e.get("ios", {}).get("buildNumber"); c = e.get("android", {}).get("versionCode")
if not v: sys.exit("expo.version이 없다")
print(v, b if b is not None else "-", c if c is not None else "-")
'
    ;;
  set)
    VERSION="${2:?버전}"; shift 2
    IOS=""; ANDROID=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --ios) IOS="${2:?}"; shift 2 ;;
        --android) ANDROID="${2:?}"; shift 2 ;;
        *) echo "알 수 없는 인자: $1" >&2; exit 1 ;;
      esac
    done
    [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "'$VERSION' — 정수 1~3개를 점으로 이은 형식이어야 한다" >&2; exit 1; }
    for n in $IOS $ANDROID; do [[ "$n" =~ ^[0-9]+$ ]] || { echo "'$n' — 빌드 번호는 정수다" >&2; exit 1; }; done
    python3 - "$FILE" "$VERSION" "$IOS" "$ANDROID" <<'PY'
import re, sys
path, version, ios, android = sys.argv[1:]
text = open(path).read()
text, n = re.subn(r'("version"\s*:\s*)"[^"]*"', r'\g<1>"%s"' % version, text, count=1)
if not n: sys.exit(f"expo.version을 찾지 못했다: {path}")
if ios:
    text, n = re.subn(r'("buildNumber"\s*:\s*)"[^"]*"', r'\g<1>"%s"' % ios, text, count=1)
    if not n: sys.exit(f"expo.ios.buildNumber를 찾지 못했다: {path}")
if android:
    text, n = re.subn(r'("versionCode"\s*:\s*)\d+', r'\g<1>%s' % android, text, count=1)
    if not n: sys.exit(f"expo.android.versionCode를 찾지 못했다: {path}")
open(path, "w").write(text)
PY
    bash "$0" get
    ;;
  *)
    echo "사용법: version.sh get [커밋] | set <버전> [--ios N] [--android N]" >&2; exit 1 ;;
esac
