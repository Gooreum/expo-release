#!/bin/bash
#
# GitHub Actions 이번 달 무료 분이 얼마나 남았는지 (Linux 기준 분 — macOS는 10배로 센다).
#
#   bash scripts/expo-release/actions-quota.sh
#   → remaining=1234 used=766 included=2000      남은 분
#   → remaining=unlimited                         공개 저장소 (호스티드 러너 무료)
#   → remaining=unknown reason=…                  알 수 없음 — 막혔는지는 실행 결과로 판단한다
#
# 개인 계정 저장소만 센다. gh 토큰에 user 스코프가 있어야 한다(gh auth refresh -h github.com -s user).
# 포함 분은 설정 actions.included_minutes(기본 2000 — Free 플랜). 무료 할인을 넘어 과금이 시작됐으면
# (결제 수단이 없으면 그때부터 잡이 시작되지 않는다) remaining=0으로 본다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "$0")/lib.sh"

INCLUDED=$(cfg actions.included_minutes); INCLUDED=${INCLUDED:-2000}

info=$(gh repo view --json owner,visibility -q '"\(.owner.login) \(.visibility)"' 2>/dev/null) \
  || { echo "remaining=unknown reason=gh-repo-view"; exit 0; }
read -r OWNER VIS <<<"$info"
[ "$VIS" = PUBLIC ] && { echo "remaining=unlimited"; exit 0; }

Y=$(date -u +%Y); M=$(date -u +%-m)
json=$(gh api "/users/$OWNER/settings/billing/usage/summary?year=$Y&month=$M" 2>/dev/null) \
  || { echo "remaining=unknown reason=billing-api(user 스코프·개인 계정 필요)"; exit 0; }

BILLING_JSON="$json" python3 - "$INCLUDED" <<'PY'
import json, math, os, sys
included = int(sys.argv[1])
d = json.loads(os.environ["BILLING_JSON"])
mult = {"actions_linux": 1, "actions_macos": 10, "actions_windows": 2}
used = 0.0; billed = 0.0
for it in d.get("usageItems", []):
    if it.get("product", "").lower() != "actions" or it.get("unitType") != "minutes":
        continue
    sku = it.get("sku", "")
    m = next((v for k, v in mult.items() if sku.startswith(k)), 1)
    used += it.get("grossQuantity", 0) * m
    billed += it.get("netAmount", 0)
used = math.ceil(used)
remaining = 0 if billed > 0.0001 else max(0, included - used)
print(f"remaining={remaining} used={used} included={included}")
PY
