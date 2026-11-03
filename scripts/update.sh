#!/bin/bash
#
# EAS Update(OTA)로 JS·에셋만 보낸다. 스토어 심사 없이 이미 깔린 앱이 다음 실행 때 받는다.
#
#   EXPO_TOKEN=… bash scripts/expo-release/update.sh "<메시지>" [ios] [android]
#   (플랫폼을 안 주면 설정에서 켜진 플랫폼 전부)
#
# 플랫폼마다 지금 fingerprint가 마지막 스토어 빌드(태그)와 같은지 먼저 본다. 다르면 네이티브가
# 바뀐 것이라 그 빌드는 이 업데이트를 받을 수 없다 — 보내지 않고 멈춘다. 스토어 빌드가 필요하다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
export_env

MESSAGE="${1:?업데이트 메시지}"; shift
PLATFORMS=("$@")
if [ ${#PLATFORMS[@]} -eq 0 ]; then
  for p in ios android; do [ "$(cfg $p.enabled)" = true ] && PLATFORMS+=("$p"); done
fi
CHANNEL=$(cfg update.channel); CHANNEL=${CHANNEL:-production}
EAS=$(cfg update.eas_cli); EAS=${EAS:-eas-cli@latest}
[ -d node_modules/expo-updates ] || { echo "expo-updates가 설치돼 있지 않다 — 설정 단계의 OTA 준비를 먼저 하라" >&2; exit 1; }

ok=()
for p in "${PLATFORMS[@]}"; do
  now=$(bash "$HERE/fingerprint.sh" hash "$p"); last=$(bash "$HERE/fingerprint.sh" last "$p")
  if [ "$last" = none ]; then
    echo "::error::$p — fingerprint가 기록된 스토어 빌드가 없다. expo-updates가 든 스토어 빌드를 먼저 올려야 한다" >&2; exit 1
  elif [ "$now" != "$last" ]; then
    echo "::error::$p — 네이티브가 마지막 스토어 빌드와 다르다($last → $now). OTA로는 내려가지 않는다. 스토어 빌드가 필요하다" >&2; exit 1
  fi
  echo "$p: fingerprint $now — 마지막 스토어 빌드와 같다"
  ok+=("$p")
done

for p in "${ok[@]}"; do
  echo "── EAS Update $p → $CHANNEL ──"
  npx -y "$EAS" update --channel "$CHANNEL" --platform "$p" --message "$MESSAGE" --non-interactive
done
