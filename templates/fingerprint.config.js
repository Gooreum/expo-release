// expo-release — 네이티브 fingerprint 설정. expo-updates(runtimeVersion policy "fingerprint")와
// scripts/expo-release/fingerprint.sh가 둘 다 이 파일을 읽어 같은 값을 낸다.
//
// 버전 번호(version·buildNumber·versionCode)는 뺀다. 빼지 않으면 Android만 versionCode를 올려도
// iOS fingerprint가 바뀌어 iOS OTA가 막힌다. 버전은 네이티브 호환성과 무관하다.
const { SourceSkips } = require('@expo/fingerprint');

/** @type {import('@expo/fingerprint').Config} */
module.exports = {
  // eas-release.sh(EAS 대체 경로)가 빌드 때만 만드는 파일 — 없을 때와 같은 값이 나오게 뺀다
  ignorePaths: ['eas.json', '.easignore'],
  sourceSkips:
    SourceSkips.ExpoConfigVersions |
    SourceSkips.ExpoConfigRuntimeVersionIfString |
    SourceSkips.PackageJsonAndroidAndIosScriptsIfNotContainRun,
};
