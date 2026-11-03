#!/bin/bash
#
# main에 머지될 때 플랫폼마다 무엇을 할지 정한다. GitHub Actions가 출력을 `$GITHUB_OUTPUT`에 붙인다.
#
#   bash scripts/expo-release/auto-plan.sh <이전 커밋> <새 커밋>
#
#   ios=ota|build|skip  android=ota|build|skip
#     skip   앱에 들어가는 파일이 안 바뀌었다(문서·테스트·fastlane·CI만) 또는 플랫폼이 꺼져 있다
#     ota    네이티브 fingerprint가 마지막 스토어 빌드와 같다 → EAS Update
#     build  네이티브가 바뀌었거나 아직 스토어 빌드 기록이 없다 → 스토어용 빌드 업로드
#            (iOS는 TestFlight, Android는 auto.android_track. 심사 제출은 하지 않는다)
#   ios_reason=, android_reason=   판정 근거 한 줄
#   message=                        OTA 메시지(새 커밋 제목)
#
# OTA가 꺼져 있으면(update.enabled false) ota 대신 build다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(dirname "$0")"
. "$HERE/lib.sh"

BASE="${1:?이전 커밋}"
HEAD="${2:?새 커밋}"

# 앱 번들에 안 들어가는 경로. 이것만 바뀌었으면 아무것도 안 올린다.
IGNORE=$(python3 - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
default = ["fastlane/**", "**/*.md", "docs/**", ".github/**", "scripts/**", "**/__tests__/**",
           "**/*.test.*", ".claude/**", ".design-bounce/**", ".expo-release.json"]
print("\n".join(c.get("auto", {}).get("ignore", default)))
PY
)
specs=(); while IFS= read -r g; do [ -n "$g" ] && specs+=(":(exclude,glob)$g"); done <<<"$IGNORE"
app_changed=$(git diff --name-only "$BASE" "$HEAD" -- . "${specs[@]}" | head -50)

ota_on=$(cfg update.enabled)
echo "message=$(git log -1 --format=%s "$HEAD")"

for p in ios android; do
  if [ "$(cfg $p.enabled)" != true ]; then
    echo "$p=skip"; echo "${p}_reason=꺼져 있다"; continue
  fi
  if [ -z "$app_changed" ]; then
    echo "$p=skip"; echo "${p}_reason=앱에 들어가는 파일 변경 없음"; continue
  fi
  last=$(bash "$HERE/fingerprint.sh" last "$p")
  if [ "$last" = none ]; then
    echo "$p=build"; echo "${p}_reason=스토어 빌드 기록(태그)이 없다 — 첫 빌드"; continue
  fi
  now=$(bash "$HERE/fingerprint.sh" hash "$p")
  if [ "$now" != "$last" ]; then
    echo "$p=build"; echo "${p}_reason=네이티브 변경 (fingerprint $last → $now)"; continue
  fi
  if [ "$ota_on" != true ]; then
    echo "$p=build"; echo "${p}_reason=JS만 바뀌었지만 OTA가 꺼져 있다"; continue
  fi
  echo "$p=ota"; echo "${p}_reason=JS만 바뀜 (fingerprint $now 그대로)"
done
