#!/bin/bash
# expo-release 공통 함수. 다른 스크립트가 `. scripts/expo-release/lib.sh`로 읽는다.
#
# 설정 파일: 저장소 루트의 `.expo-release.json` (EXPO_RELEASE_CONFIG로 바꿀 수 있다)

CONFIG="${EXPO_RELEASE_CONFIG:-.expo-release.json}"
[ -f "$CONFIG" ] || { echo "설정 파일이 없다: $CONFIG — expo-release 스킬의 설정 단계를 먼저 하라" >&2; exit 1; }

# 점으로 이은 키의 값을 읽는다. 없으면 빈 문자열. 목록·객체는 JSON으로.
#   cfg ios.bundle_id
cfg() {
  python3 - "$CONFIG" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
if isinstance(d, bool):
    print("true" if d else "false")
elif isinstance(d, (list, dict)):
    print(json.dumps(d, ensure_ascii=False))
else:
    print(d)
PY
}

# CI 전용: 워크플로가 넘긴 SECRETS_JSON(toJSON(secrets))에서 설정 ci.secrets에 적은 이름만
# 환경변수로 내보내고 나머지는 버린다. ci.setup 스크립트는 그 이름으로 비밀 파일을 복원한다.
export_secrets() {
  [ -n "${SECRETS_JSON:-}" ] || return 0
  eval "$(python3 - "$CONFIG" <<'PY'
import json, os, shlex, sys
want = json.load(open(sys.argv[1])).get("ci", {}).get("secrets", [])
have = json.loads(os.environ["SECRETS_JSON"])
for k in want:
    if k in have:
        print(f"export {k}={shlex.quote(have[k])}")
PY
)"
  unset SECRETS_JSON
}

# 설정의 env(예: APP_ENV=prod, NODE_ENV=production)를 내보낸다. 빌드·fingerprint·OTA가
# 모두 같은 환경으로 앱 설정을 읽어야 같은 runtime version이 나온다.
#
# env_files(예: .env.production)도 셸 환경으로 읽는다. eas-cli는 앱 설정을 dotenv 없이
# 평가하므로(EXPO_NO_DOTENV), .env에만 있는 값을 app.config가 요구하면 eas update가 실패한다.
# 먼저 내보내 두면 eas·expo-updates 빌드 단계·fingerprint가 모두 같은 설정을 본다.
export_env() {
  local f
  for f in $(python3 -c "import json,sys;print(' '.join(json.load(open(sys.argv[1])).get('env_files',[])))" "$CONFIG"); do
    [ -f "$f" ] || { echo "env_files의 $f가 없다" >&2; return 1; }
    set -a; . "./$f"; set +a
  done
  eval "$(python3 - "$CONFIG" <<'PY'
import json, shlex, sys
for k, v in json.load(open(sys.argv[1])).get("env", {}).items():
    print(f"export {k}={shlex.quote(str(v))}")
PY
)"
}
