# expo-release

Expo(React Native) 앱을 App Store·Google Play에 올리고, JS만 바뀌었으면 EAS Update(OTA)로 바로 내보내는 Claude Code 스킬.

- **처음 한 번 — 설정:** fastlane(두 스토어 앱 정보·Android 업로드), GitHub Actions(iOS·Android 빌드, OTA), expo-updates를 깐다.
- **main 머지 — 자동:** 네이티브 fingerprint를 마지막 스토어 빌드와 비교해, JS만 바뀌었으면 OTA로 바로 내보내고
  네이티브가 바뀌었으면 TestFlight·Play 테스트 트랙에 빌드를 올린다. 문서·테스트만 바뀌면 아무것도 안 한다.
- **스토어 출시 — 스킬:** 이번 머지가 어떻게 나갔는지 먼저 판정·보고하고, 출시할 스토어·버전·업데이트 내용·앱 정보를
  **탭 하나로 한 번에** 묻는다. 심사 제출(iOS)은 사람이 한다.
- 네이티브 iOS·macOS 프로젝트는 [app-store-release](https://github.com/Gooreum/app-store-release)를 쓴다.

## 무엇이 프로젝트에 깔리나

| 경로 | 하는 일 |
|---|---|
| `.expo-release.json` | 번들 ID·패키지·env·플랫폼·Play 트랙·서명 속성·OTA 채널 ([예시](templates/expo-release.example.json)) |
| `scripts/expo-release/version.sh` | app.json의 version·ios.buildNumber·android.versionCode 읽기/쓰기 |
| `scripts/expo-release/fingerprint.sh` | 네이티브 fingerprint와 마지막 스토어 빌드(태그) 비교 |
| `scripts/expo-release/release-diff.sh` | 릴리스 커밋인지(빌드 번호·앱 정보 변경) |
| `scripts/expo-release/auto-plan.sh` | main 머지 판정: skip / ota / build |
| `scripts/expo-release/ios-build-upload.sh` | prebuild → 서명 없는 아카이브 → API 키 클라우드 서명 업로드 |
| `scripts/expo-release/android-build.sh` | prebuild → 업로드 키 서명 AAB (debug 서명이면 멈춤) |
| `scripts/expo-release/update.sh` | fingerprint가 같은 플랫폼만 EAS Update |
| `scripts/expo-release/actions-quota.sh` | 이번 달 GitHub Actions 무료 분이 얼마나 남았는지 (macOS 10배) |
| `scripts/expo-release/eas-release.sh` | Actions를 못 쓸 때 스토어 빌드를 EAS Build로 — 같은 번호·검사·태그. 이 Mac에선 네이티브 빌드 안 함 |
| `scripts/expo-release/setup-ios-signing.sh` | EAS 대체 경로용 iOS 배포 인증서·App Store 프로필을 ASC API로 만든다 (대화형 단계 없음) |
| `fastlane/Fastfile` | `ios metadata`(심사 대기면 철회 옵션), `android upload`(supply) |
| `fingerprint.config.js` | 버전 번호·EAS 빌드 파일(`eas.json`·`.easignore`)을 fingerprint에서 뺀다 (expo-updates와 공유) |
| `.github/workflows/expo-release.yml` | main 머지 자동 배포 + 릴리스 커밋 출시. 태그 `<플랫폼>-v<버전>-<빌드>`(메시지에 fingerprint) |

## 판정 규칙 (main 머지마다, 플랫폼별)

| 판정 | 조건 | 결과 |
|---|---|---|
| skip | 앱에 들어가는 파일 변경 없음, 또는 커밋 메시지에 `[skip release]` | 없음 |
| ota | fingerprint = 마지막 스토어 빌드 태그 | EAS Update |
| build | 네이티브 변경 또는 태그 없음 | TestFlight / Play 테스트 트랙 업로드 (번호는 태그에서 이어 받음) |
| release | 커밋이 app.json 빌드 번호를 올림(스킬의 릴리스 커밋) | 그 플랫폼 출시용 업로드 |
