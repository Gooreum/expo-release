#!/bin/bash
#
# 두 커밋 사이에 스토어로 올릴 것이 바뀌었는지 판정한다. GitHub Actions가 출력을
# 그대로 `$GITHUB_OUTPUT`에 붙인다.
#
#   bash scripts/expo-release/release-diff.sh <이전 커밋> <새 커밋>
#
#   ios_build=true|false          iOS 빌드 번호가 바뀌었다 → 아카이브·업로드
#   android_build=true|false      Android versionCode가 바뀌었다 → AAB 빌드·업로드
#   ios_metadata=true|false       fastlane/metadata가 바뀌었다
#   ios_screenshots=true|false    fastlane/screenshots가 바뀌었다
#   android_metadata=true|false   fastlane/android가 바뀌었다 (설명·업데이트 내용·스크린샷)
#   version=, ios_build_number=, android_version_code=
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${1:?이전 커밋}"
HEAD="${2:?새 커밋}"
HERE="$(dirname "$0")"

read -r _ old_ios old_android < <(bash "$HERE/version.sh" get "$BASE" 2>/dev/null || echo "? ? ?")
read -r version new_ios new_android < <(bash "$HERE/version.sh" get "$HEAD")

changed() { git diff --quiet "$BASE" "$HEAD" -- "$1" && echo false || echo true; }
differs() { [ "$1" != "$2" ] && echo true || echo false; }

echo "ios_build=$(differs "$old_ios" "$new_ios")"
echo "android_build=$(differs "$old_android" "$new_android")"
echo "ios_metadata=$(changed fastlane/metadata)"
echo "ios_screenshots=$(changed fastlane/screenshots)"
echo "android_metadata=$(changed fastlane/android)"
echo "version=$version"
echo "ios_build_number=$new_ios"
echo "android_version_code=$new_android"
