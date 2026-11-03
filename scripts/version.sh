#!/bin/bash
#
# Expo app.json의 버전을 읽고 쓴다.
#   expo.version            두 플랫폼 공통 마케팅 버전
#   expo.ios.buildNumber    iOS 빌드 번호 (문자열)
#   expo.android.versionCode  Android 빌드 번호 (정수)
#
#   bash scripts/expo-release/version.sh get [커밋]          → "1.0.11 5 2"
#   bash scripts/expo-release/version.sh set <버전> [--ios N] [--android N]
#   bash scripts/expo-release/version.sh next <ios|android>      → 다음 빌드 번호 (태그까지 본다)
#   bash scripts/expo-release/version.sh latest <ios|android>    → app.json·태그 중 큰 버전
#   bash scripts/expo-release/version.sh bump-patch 1.0.11       → 1.0.12
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
  next)
    # 다음 빌드 번호 = max(app.json, 그 플랫폼 마지막 태그) + 1.
    # main 머지 자동 빌드는 app.json을 커밋하지 않고 태그만 남기므로 태그가 더 클 수 있다.
    P="${2:?ios|android}"
    read -r _ ib ac < <(bash "$0" get)
    cur=$([ "$P" = ios ] && echo "$ib" || echo "$ac"); [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
    git fetch -q --tags 2>/dev/null || true
    tag=$(git tag -l "$P-v*" | sed -E 's/.*-([0-9]+)$/\1/' | sort -n | tail -1)
    echo $(( (${tag:-0} > cur ? ${tag:-0} : cur) + 1 ))
    ;;
  latest)
    # 지금 쓸 버전 = app.json과 그 플랫폼 마지막 태그 중 큰 쪽
    P="${2:?ios|android}"
    read -r v _ _ < <(bash "$0" get)
    git fetch -q --tags 2>/dev/null || true
    tv=$(git tag -l "$P-v*" | sed -E "s/^$P-v(.*)-[0-9]+$/\1/" | sort -V | tail -1)
    printf '%s\n%s\n' "$v" "${tv:-0}" | sort -V | tail -1
    ;;
  bump-patch)
    IFS=. read -r a b c <<<"${2:?버전}"; echo "${a}.${b:-0}.$(( ${c:-0} + 1 ))"
    ;;
  *)
    echo "사용법: version.sh get [커밋] | set <버전> [--ios N] [--android N] | next <플랫폼> | latest <플랫폼> | bump-patch <버전>" >&2; exit 1 ;;
esac
