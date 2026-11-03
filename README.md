# expo-release

Expo(React Native) 앱을 App Store·Google Play에 올리고, JS만 바뀌었으면 EAS Update(OTA)로 바로 내보내는 Claude Code 스킬.

- **처음 한 번 — 설정:** fastlane(두 스토어 앱 정보·Android 업로드), GitHub Actions(iOS·Android 빌드, OTA), expo-updates를 깐다.
- **배포할 때마다 — 릴리스:** 네이티브 fingerprint를 마지막 스토어 빌드와 비교해 OTA가 되는지 판정하고,
  배포 방식·플랫폼·업데이트 내용·앱 정보를 **탭 하나로 한 번에** 묻는다.
- 네이티브 iOS·macOS 프로젝트는 [app-store-release](https://github.com/Gooreum/app-store-release)를 쓴다.

## 무엇이 프로젝트에 깔리나

| 경로 | 하는 일 |
|---|---|
| `.expo-release.json` | 번들 ID·패키지·env·플랫폼·Play 트랙·서명 속성·OTA 채널 ([예시](templates/expo-release.example.json)) |
| `scripts/expo-release/version.sh` | app.json의 version·ios.buildNumber·android.versionCode 읽기/쓰기 |
| `scripts/expo-release/fingerprint.sh` | 네이티브 fingerprint와 마지막 스토어 빌드(태그) 비교 |
| `scripts/expo-release/release-diff.sh` | 두 커밋 사이에 플랫폼별 빌드·앱 정보 중 무엇이 바뀌었는지 |
| `scripts/expo-release/ios-build-upload.sh` | prebuild → 서명 없는 아카이브 → API 키 클라우드 서명 업로드 |
| `scripts/expo-release/android-build.sh` | prebuild → 업로드 키 서명 AAB (debug 서명이면 멈춤) |
| `scripts/expo-release/update.sh` | fingerprint가 같은 플랫폼만 EAS Update |
| `fastlane/Fastfile` | `ios metadata`(심사 대기면 철회 옵션), `android upload`(supply) |
| `fingerprint.config.js` | 버전 번호를 fingerprint에서 뺀다 (expo-updates와 공유) |
| `.github/workflows/expo-release.yml` | 릴리스 커밋·수동 실행으로 바뀐 것만 올리고 태그 `<플랫폼>-v<버전>-<빌드>`(메시지에 fingerprint) |

## 판정 규칙

- `ios.buildNumber`가 바뀌면 iOS 빌드, `android.versionCode`가 바뀌면 Android 빌드.
- OTA는 플랫폼별로 지금 fingerprint가 마지막 스토어 빌드 태그의 fingerprint와 같을 때만 보낸다.
