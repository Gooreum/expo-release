#!/bin/bash
#
# 네이티브 레이어 fingerprint — OTA 업데이트를 보내도 되는지 판정한다.
#
#   bash scripts/expo-release/fingerprint.sh hash <ios|android>   지금 작업 트리의 hash
#   bash scripts/expo-release/fingerprint.sh last <ios|android>   마지막 스토어 빌드의 hash (태그에서)
#   bash scripts/expo-release/fingerprint.sh check [--clean]       ios=same|changed|none android=…
#
# 스토어 빌드를 올릴 때 CI가 태그 `<플랫폼>-v<버전>-<빌드>`를 annotated 태그로 찍고
# 메시지에 `fingerprint=<hash>`를 남긴다. 그 hash와 지금 hash가 같으면 네이티브가 그대로라
# OTA로 보낼 수 있다. expo-updates도 runtimeVersion policy "fingerprint"로 같은 값을 쓰므로,
# 다르면 OTA를 보내도 그 빌드에는 내려가지 않는다(조용히 무시된다).
#
# 같은 hash가 나오려면: node_modules가 lockfile대로 깔려 있고(npm ci), 설정의 env로 앱 설정을
# 읽고, 프로젝트 루트의 fingerprint.config.js(버전 번호 제외)를 쓴다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "$0")/lib.sh"
export_env

hash() {
  node -e "
require('@expo/fingerprint')
  .createFingerprintAsync(process.cwd(), { platforms: [process.argv[1]] })
  .then(f => console.log(f.hash))
  .catch(e => { console.error(e.message); process.exit(1) })
" "$1"
}

last() {
  git fetch -q --tags 2>/dev/null || true
  local tag
  tag=$(git tag -l "$1-v*" --sort=-creatordate | head -1)
  [ -n "$tag" ] || { echo none; return; }
  git tag -l --format='%(contents)' "$tag" | sed -n 's/^fingerprint=//p' | head -1 | grep . || echo none
}

case "${1:-}" in
  hash) hash "${2:?ios|android}" ;;
  last) last "${2:?ios|android}" ;;
  check)
    # --clean: 커밋된 HEAD만으로 잰다(임시 worktree + npm ci). 로컬 작업 트리의 커밋 안 한 수정·
    # lockfile과 어긋난 node_modules가 hash를 바꾸기 때문이다 — CI와 같은 값을 보려면 이걸 쓴다.
    # 앱 설정을 읽는 데 필요한 gitignore 파일(.env.production 등)은 설정 local_files로 복사한다.
    if [ "${2:-}" = --clean ]; then
      wt=$(mktemp -d)/wt
      git worktree add -q --detach "$wt" HEAD
      trap 'git worktree remove --force "$wt" >/dev/null 2>&1 || true' EXIT
      for f in $(python3 -c "import json;print(' '.join(json.load(open('$CONFIG')).get('local_files',[])))"); do
        [ -e "$f" ] && cp "$f" "$wt/$f"
      done
      cp "$CONFIG" "$wt/.expo-release.json"
      (cd "$wt" && npm ci --silent >/dev/null 2>&1) || { echo "npm ci 실패" >&2; exit 1; }
      (cd "$wt" && EXPO_RELEASE_CONFIG=.expo-release.json bash "$wt/scripts/expo-release/fingerprint.sh" check)
      exit
    fi
    out=()
    for p in ios android; do
      [ "$(cfg $p.enabled)" = true ] || continue
      l=$(last $p)
      if [ "$l" = none ]; then out+=("$p=none")
      elif [ "$(hash $p)" = "$l" ]; then out+=("$p=same")
      else out+=("$p=changed"); fi
    done
    echo "${out[*]}"
    ;;
  *) echo "사용법: fingerprint.sh hash|last <ios|android> | check" >&2; exit 1 ;;
esac
