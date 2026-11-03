---
name: expo-release
description: Expo(React Native) 앱 배포를 자동화한다. main에 머지되면 GitHub Actions가 네이티브 fingerprint로 판정해 JS만 바뀌었으면 EAS Update(OTA)로 바로 내보내고, 네이티브가 바뀌었으면 TestFlight·Play 테스트 트랙에 빌드를 올린다. 이 스킬은 처음 한 번 파이프라인을 깔고(fastlane·GitHub Actions·expo-updates), 그 뒤로는 스토어 출시(업데이트 내용·버전·앱 정보·스크린샷)와 "이번 머지가 OTA로 나가는지" 판정·보고를 맡는다. 사용자가 "배포", "릴리스", "스토어에 올려", "출시", "OTA", "OTA 되는지 봐줘", "핫픽스", "플레이스토어 자동 배포", "Expo 배포 설정"이라고 하거나 main 머지 직후에 쓴다. 네이티브 iOS·macOS 프로젝트(Expo 아님)는 app-store-release를 쓴다.
---

# expo-release

사용자에게 보이는 말은 사용자의 언어로 쓴다.

두 가지 모드가 있다. 저장소 루트에 `.expo-release.json`이 없으면 **설정**, 있으면 **릴리스**.
`SKILL_DIR`은 이 파일이 있는 폴더다(보통 `~/.claude/skills/expo-release`).

Expo 프로젝트가 아니면(`package.json`에 `expo`가 없음) 멈추고, 네이티브 iOS·macOS면 `app-store-release`를 쓰라고 말한다.

## 전체 흐름

**main 머지 → 자동 (사람 개입 없음).** 워크플로가 플랫폼마다 판정한다(`auto-plan.sh`).

| 판정 | 조건 | 하는 일 |
|---|---|---|
| skip | 앱에 들어가는 파일 변경 없음(문서·테스트·fastlane·CI·스크립트만) 또는 커밋 메시지에 `[skip release]` | 없음 |
| ota | 네이티브 fingerprint = 마지막 스토어 빌드 태그 | EAS Update. 깔린 앱이 다음 실행 때 받는다 |
| build | 네이티브가 바뀜(패키지·config plugin·app.json 네이티브 설정·권한) 또는 태그가 없음 | 빌드 번호를 태그에서 이어 받아 iOS는 TestFlight, Android는 `auto.android_track`에 업로드. **심사 제출 안 함** |

자동 빌드는 app.json을 커밋하지 않는다. 빌드 번호 기록은 태그 `<플랫폼>-v<버전>-<빌드>`(메시지에 `fingerprint=`)다.
iOS는 그 버전이 이미 승인돼 트레인이 닫혔으면 패치 버전을 올려 빌드한다.

**스토어 출시 → 이 스킬 (사람이 정한다).** 업데이트 내용·버전·앱 정보를 정해 릴리스 커밋을 올리면
워크플로가 출시용으로 올린다(iOS 업로드 후 심사 제출은 사람이, Android는 `android.track`·`release_status`).

**OTA 판단은 내가 먼저 한다.** 사용자에게 "OTA로 할까요?"를 묻지 않는다. fingerprint로 판정하고 근거와 함께 알린다.
- fingerprint가 다르면 OTA는 **불가능**하다(보내도 그 빌드는 받지 못한다). 그렇게 말하고 스토어 빌드로 간다.
- fingerprint가 같아도 **스토어에 설명한 기능을 크게 바꾸는 변경**(새 화면·새 핵심 기능·결제 변경)은 OTA로 내보내기에 부적절하다(App Store 가이드라인 2.5.2·3.3.1).
  머지 전에 알 수 있으면 커밋 메시지에 `[skip release]`를 넣어 OTA를 막고 스토어 출시로 내보내라고 권한다.
  이미 OTA로 나갔으면 그다음 스토어 출시 때 업데이트 내용에 포함한다.

## 질문 규칙 (두 모드 공통)

- 질문은 **한 번에** 띄운다 — AskUserQuestion 한 호출에 탭 여러 개(최대 4개).
- 탭 하나의 보기는 최대 4개다. "없음"·"배포 안 함"처럼 고를 만한 답은 **반드시 보기로** 둔다. Other는 직접 입력에만.
- 질문에 넣을 초안(업데이트 내용 등)은 **묻기 전에 미리 써서** `preview`에 넣는다.
- 후속 질문이 필요하면 해당하는 것만 모아 다시 한 번에 묻는다.

## 보안 규칙

- App Store Connect API 키(.p8), Play 서비스 계정 JSON, 업로드 키스토어, EXPO_TOKEN의 **내용을 읽거나 복사하거나 출력하지 않는다.** 경로만 다룬다.
- GitHub 시크릿은 사용자가 직접 넣는다. 명령을 보여 주고 `! 명령`으로 실행하라고 안내한다.
- 공개 저장소에 심사 담당자 연락처(`fastlane/metadata/review_information/`)를 커밋하지 않는다.

---

## 설정 모드 — 파이프라인 깔기

### 1. 프로젝트 살피기 (읽기만)

```bash
git rev-parse --show-toplevel; git remote get-url origin; gh repo view --json visibility,defaultBranchRef
cat app.json; ls app.config.* eas.json 2>/dev/null
grep -E '"(expo|expo-updates|react-native)"' package.json
git check-ignore -q ios && echo "ios gitignored (CNG)"; git check-ignore -q android && echo "android gitignored (CNG)"
ls plugins 2>/dev/null; grep -rn "signingConfig" plugins 2>/dev/null | head
ls .app-store-release.json fastlane .github/workflows 2>/dev/null   # app-store-release가 깔려 있는지
```

추려 낼 값:
- 번들 ID·패키지 이름: `app.config.*`가 환경(APP_ENV 등)에 따라 바꾸면 **prod 값**과 그 환경변수를 `env`에 쓴다.
- 버전 위치: `app.json`의 `expo.version`·`expo.ios.buildNumber`·`expo.android.versionCode`. `app.config.*`가 덮어쓰면 멈추고 말한다(이 스킬은 app.json만 고친다).
- `ios/`·`android/`가 추적되면(bare) 이 스킬의 prebuild 단계와 맞지 않는다 — 멈추고 말한다.
- Android 서명 plugin: release 서명을 넣는 config plugin이 있으면 그 Gradle 속성 이름을 `android.signing_props`에 쓴다. 없으면 `templates/plugins/withReleaseSigning.js`를 깐다.
- CI에 필요한 비밀 파일(.env.production, GoogleService 파일 등): gitignore돼 있으면 base64 시크릿에서 복원하는 `ci.setup` 스크립트가 필요하다. 이름을 `ci.secrets`에 적는다.
- `app-store-release`가 이미 깔려 있으면 **옮겨 온다**: `fastlane/metadata`·`fastlane/screenshots`는 그대로 쓰고, 기존 워크플로·스크립트는 새 것과 겹치므로 지울지 묻는다(4번 탭). 기존 태그 `v<버전>-<빌드>`는 iOS 빌드 기록이다.

### 2. 한 번에 확인받기 — AskUserQuestion 1회

| header | 질문 | 보기 |
|---|---|---|
| 앱 | 이 앱이 맞나요? (iOS `…`, Android `…`, env `APP_ENV=prod`) | `맞다` / 다른 후보 |
| 플랫폼 | 어느 스토어를 자동화할까요? | `iOS + Android` / `iOS만` / `Android만` |
| Play 트랙 | 스토어 출시 때 Android를 어떻게 올릴까요? (main 머지 자동 빌드는 internal 테스트로 간다) | `production 검토 바로 제출` / `production 초안(사람이 출시)` / `internal 테스트` |
| OTA | EAS Update(OTA)도 켤까요? | `켠다 — expo-updates 설치(다음 스토어 빌드부터 적용)` / `나중에` |

`app-store-release`가 깔려 있으면 마지막 탭 대신(또는 후속 질문으로) "기존 app-store 워크플로·스크립트를 지울까요?"를 묻는다.

### 3. 파일 깔기

```bash
mkdir -p scripts/expo-release fastlane/android/metadata .github/workflows
cp "$SKILL_DIR"/scripts/*.sh scripts/expo-release/
cp "$SKILL_DIR"/templates/fastlane/Fastfile fastlane/Fastfile        # 있으면 차이를 보이고 묻는다
sed -e "s|__BRANCH__|$BRANCH|g" -e "s|__RUNNER__|$RUNNER|g" \
  "$SKILL_DIR"/templates/workflows/expo-release.yml > .github/workflows/expo-release.yml
```

- `.expo-release.json`은 `templates/expo-release.example.json` 모양대로 쓴다. 쓰지 않는 플랫폼은 `enabled: false`.
  - `local_files`: 앱 설정을 읽는 데 필요한 gitignore 파일(.env.production 등). `fingerprint.sh check --clean`이 임시 worktree로 복사한다.
  - `auto.android_track`: main 머지 자동 빌드를 올릴 Play 트랙(기본 `internal`). `android.track`은 스토어 출시용이다.
  - `auto.ignore`(선택): 바뀌어도 배포하지 않을 경로 glob. 기본은 fastlane·문서·CI·scripts·테스트.
- **워크플로는 main의 모든 푸시에 돈다.** OTA를 끄면 앱 코드가 바뀐 머지마다 스토어 빌드가 올라간다(macOS 러너 시간) — 설정 때 말한다.
- `.gitignore`에 추가: `build/expo-release/`, `fastlane/report.xml`, `fastlane/metadata/review_information/`.
- 서명 plugin이 없으면 `templates/plugins/withReleaseSigning.js`를 `plugins/`에 두고 `app.json` plugins에 `"./plugins/withReleaseSigning"`을 넣는다.
- `ci.setup` 스크립트가 필요하면 쓴다: `ci.secrets`의 각 이름(base64)을 디코드해 파일로 복원하고 `npm ci`.

확인: `bash scripts/expo-release/version.sh get` → `버전 iOS빌드 Android코드`.

### 4. OTA 준비 (켰을 때만)

이 단계는 **앱의 네이티브를 바꾼다.** 프로젝트에 개발 워크플로 규칙(dev-bounce 등)이 있으면 그 안에서 한다.

1. `npx expo install expo-updates`
2. EAS 프로젝트 연결 — 사용자가 직접: `! npx eas-cli login` → `! npx eas-cli init`(app.json에 `extra.eas.projectId`가 생긴다)
3. app.json `expo`에 넣는다:
   ```json
   "runtimeVersion": { "policy": "fingerprint" },
   "updates": {
     "url": "https://u.expo.dev/<projectId>",
     "requestHeaders": { "expo-channel-name": "production" }
   }
   ```
   `requestHeaders`가 있어야 EAS Build를 안 쓰는 로컬·CI 빌드가 채널을 안다. 채널은 `update.channel`과 같게.
4. `templates/fingerprint.config.js`를 루트에 둔다(버전 번호를 fingerprint에서 뺀다).
5. `bash scripts/expo-release/fingerprint.sh hash ios` / `android`가 hash를 내는지 본다.

**OTA는 expo-updates가 든 스토어 빌드가 나간 뒤부터 된다.** 그 전에 깔린 앱은 받지 못한다고 말한다.

### 5. 시크릿 — 사용자가 직접

필요한 것만 안내한다. 사용자에게 `!`로 실행하라고 한다(값은 내가 보지 않는다).

- **iOS:** App Store Connect → 사용자 및 액세스 → 통합 → API에서 **Admin** 키
  ```
  ! gh secret set ASC_KEY_ID --body <키 ID>
  ! gh secret set ASC_ISSUER_ID --body <Issuer ID>
  ! base64 -i ~/.appstoreconnect/private_keys/AuthKey_<키 ID>.p8 | gh secret set ASC_KEY_P8
  ```
- **Android:** Google Cloud에서 서비스 계정을 만들어 JSON 키를 받고, Play Console → 사용자 및 권한에서 그 계정에 앱 권한(출시 관리)을 준다.
  ```
  ! base64 -i <서비스계정>.json | gh secret set PLAY_SERVICE_ACCOUNT_JSON_B64
  ! base64 -i <업로드키>.keystore | gh secret set ANDROID_KEYSTORE_B64
  ! gh secret set ANDROID_KEYSTORE_PASSWORD
  ! gh secret set ANDROID_KEY_ALIAS --body <alias>
  ! gh secret set ANDROID_KEY_PASSWORD
  ```
  (비밀번호는 `--body` 없이 실행하면 입력 프롬프트로 받는다 — 셸 기록에 안 남는다)
- **OTA:** expo.dev → Access tokens에서 토큰 → `! gh secret set EXPO_TOKEN`
- **프로젝트 비밀 파일:** `ci.secrets`의 이름마다 `! base64 -i <파일> | gh secret set <이름>`

`gh secret list`로 들어갔는지 본다.

### 6. 앱 정보 가져오기

- iOS: `app-store-release`에서 옮겨 왔으면 그대로. 아니면 `fastlane deliver download_metadata`로 내려받는다.
- Android: `fastlane supply init --package_name <패키지> --json_key <경로> --metadata_path fastlane/android/metadata`
  (키 경로가 로컬에 없으면 건너뛰고, 첫 Play 메타데이터 반영 전에 사용자가 Play Console 값을 그대로 둘지 묻는다)

### 7. 커밋·확인

파일을 하나씩 `git add`하고 커밋·푸시한다(프로젝트의 커밋 규칙을 따른다). 그다음 서명까지 되는지 본다:

```bash
gh workflow run expo-release.yml -f ios=true -f android=true -f dry_run=true
sleep 5; gh run watch "$(gh run list --workflow expo-release.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

실패하면 `gh run view <id> --log-failed | tail -60`을 읽고 고친다. 흔한 원인: ASC 키 권한이 Admin이 아님,
러너 Xcode가 낮음, 서명 plugin 속성 이름이 `signing_props`와 다름(→ debug 서명 거부), ci.secrets 누락.

---

## 릴리스 모드

### 0. 판정·준비 — 묻기 전에 읽기만 한다

파일을 하나도 바꾸지 않는다. 하나라도 어긋나면 묻지 말고 멈춰 무엇이 문제인지 말한다.

```bash
. scripts/expo-release/lib.sh; BRANCH=$(cfg branch); BRANCH=${BRANCH:-main}
git switch "$BRANCH" && git pull --ff-only --tags
git status --short -- app.json fastlane scripts/expo-release .github   # 비어 있어야 한다
bash scripts/expo-release/version.sh get                     # app.json 값
git tag -l 'ios-v*' 'android-v*' --sort=-creatordate | head -6   # 실제로 올라간 빌드
gh run list --workflow expo-release.yml --limit 5 --json databaseId,headSha,conclusion,displayTitle
```

**최근 머지가 어떻게 나갔는지 먼저 본다.** 마지막 run의 판정을 읽는다:
`gh run view <id> --log | grep -E "notice|ios=|android=|ota="` → 플랫폼별 `ota / auto / none`과 이유.
실패한 run이 있으면 원인을 먼저 보고한다.

**지금 HEAD 기준 판정**이 필요하면(머지 전 브랜치, 또는 run이 아직 없음):
`bash scripts/expo-release/fingerprint.sh check --clean` — 임시 worktree에서 npm ci 후 잰다(몇 분 걸린다).
로컬 작업 트리에서 바로 재면 커밋 안 한 수정·lockfile과 어긋난 node_modules 때문에 CI와 값이 달라진다.

판정 결과를 사용자에게 **한두 줄로 먼저 말한다**. 예:
- "이번 머지는 iOS·Android 둘 다 OTA로 나갔어요(네이티브 그대로). 스토어 출시는 필요 없어요."
- "Android는 네이티브가 바뀌어(react-native-xxx 추가) OTA가 안 돼요. 내부 테스트에 4번 빌드가 올라가 있어요. 출시하려면 업데이트 내용을 정하면 돼요."

사용자가 판정만 물었으면 여기서 끝낸다. 출시를 원하면 1로 간다.

**출시할 빌드:** 플랫폼별 최신 태그. 그 태그 이후 커밋 중 네이티브가 바뀐 게 있으면 새로 빌드해야 한다(판정 `build`).

**업데이트 내용 초안을 여기서 미리 쓴다.** 기준점은 그 플랫폼이 마지막으로 **출시된**(심사 통과) 버전 —
`fastlane/metadata/<언어>/release_notes.txt`를 마지막으로 바꾼 릴리스 커밋. 그 뒤 OTA로 나간 변경도 포함한다.

```bash
git log --no-merges --format='%h %s' <마지막 릴리스 커밋>..HEAD
```

사용자에게 보이는 변화만 고른다 — 리팩터·테스트·문서·CI·버전 커밋은 뺀다.
iOS `release_notes.txt`, Android `changelogs/<새 versionCode>.txt`(500자)의 이전 문체를 따라 **있는 언어 전부**.

**이름이 바뀌었는지도 본다.** 메뉴·기능 이름을 바꿨거나 새 기능이 생겼으면 `description.txt`·`keywords.txt`(iOS),
`full_description.txt`·`short_description.txt`(Android)에 옛 이름이 남았는지 `grep`으로 확인하고 앱 정보 탭에 적는다.

**App Store 심사 상태:** 심사 대기 중인 버전이 있으면 첫 탭에 "심사 중인 X를 철회하고 올릴까요?(심사 순서를 잃어요)"를 보기로 둔다.

### 1. 한 번에 묻기 — AskUserQuestion 1회

OTA 여부는 묻지 않는다(0에서 판정했다).

| header | 질문 | 보기 (최대 4개) |
|---|---|---|
| 출시 | 어느 스토어에 출시할까요? (판정: iOS OTA로 나감, Android 네이티브 변경 …) | `iOS + Android` / `iOS만` / `Android만` / `이번엔 출시 안 함` |
| 버전 | 버전은? (지금 X.Y.Z) | `패치 X.Y.(Z+1)` / `마이너 X.(Y+1).0` / `X.Y.Z 그대로` |
| 업데이트 | 업데이트 내용을 이대로 쓸까요? | `확정` / `고쳐 줘` — 두 보기 모두 `preview`에 언어별 초안 전문 |
| 앱 정보 | 앱 정보·스크린샷도 바꿀까요? (multiSelect) | `없음` / `설명·키워드` / `스크린샷` / `URL·카테고리` |

- `(Recommended)`: 출시는 판정이 `build`인 플랫폼(OTA로 다 나간 플랫폼은 출시할 게 없다). 버전은 iOS 트레인이 닫혔으면(승인된 버전) `패치`, 열려 있으면 `그대로`.
- 메이저는 Other로 받는다.

### 2. 답 처리

- `이번엔 출시 안 함` → 아무 파일도 바꾸지 않고 한 줄로 끝낸다.
- 후속 질문(해당하는 것만 한 번에): 업데이트 `고쳐 줘` → 무엇을, 앱 정보 항목마다 → 무엇으로, 스크린샷 → 어느 화면·어느 스토어.
- **업데이트 내용이 `확정`되기 전에는 파일을 바꾸거나 커밋하지 않는다.**

### 3. 파일 반영

**버전** — 고른 플랫폼의 빌드 번호는 `version.sh next <플랫폼>`(app.json과 태그 중 큰 값 + 1). 묻지 않는다.

```bash
bash scripts/expo-release/version.sh set <버전> [--ios $(bash scripts/expo-release/version.sh next ios)] [--android $(bash scripts/expo-release/version.sh next android)]
```

릴리스 커밋은 고른 플랫폼만 빌드 번호를 바꾼다. 바뀐 플랫폼만 출시되고, 같은 커밋에서는 자동 빌드·OTA가 돌지 않는다.

**업데이트 내용·앱 정보** — 확정된 초안을 언어마다 쓴다.

| 스토어 | 파일 | 제한 |
|---|---|---:|
| iOS | `fastlane/metadata/<언어>/release_notes.txt` | 4000자 |
| iOS | `name.txt` / `subtitle.txt` / `keywords.txt` / `description.txt` / `promotional_text.txt` | 30 / 30 / 100 / 4000 / 170 |
| Android | `fastlane/android/metadata/<언어>/changelogs/<versionCode>.txt` | 500자 |
| Android | `title.txt` / `short_description.txt` / `full_description.txt` | 30 / 80 / 4000 |

- Android 언어 폴더 이름은 Play 형식(`ko-KR`, `en-US`)이다. iOS(`ko`, `en-US`)와 다르다.
- 스크린샷: iOS `fastlane/screenshots/<언어>/`, Android `fastlane/android/metadata/<언어>/images/phoneScreenshots/`(파일 이름 순서대로 올라간다 — `01-…png`처럼 번호를 붙인다).
- 스크린샷을 새로 만들면 설정의 `screenshots.capture`·`compose`를 쓰고, 결과를 한 장씩 열어 확인한 뒤 사용자에게 보여 주고 `확정` / `다시`를 묻는다.

### 4. 릴리스 커밋 → 워크플로 확인

바뀐 파일만 하나씩 `git add`한다(`git add .` 금지). 프로젝트의 커밋 규칙을 따른다. 예:
`chore: X.Y.Z 출시 — iOS (B)·Android (C), 업데이트 내용 반영`. main에 직접 푸시할 수 없으면 PR로 올리고, 머지되면 워크플로가 돈다.

```bash
sleep 5; RUN=$(gh run list --workflow expo-release.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

- 성공: 플랫폼별로 무엇이 올라갔는지(빌드/앱 정보/스크린샷), 태그를 보고한다.
  - iOS: **심사 제출은 사람이 App Store Connect에서 한다**(철회 후 재제출한 경우만 워크플로가 다시 제출). 빌드 처리에 몇 분~수십 분.
  - Android: `release_status`가 `completed`면 그 트랙에 출시(production이면 검토 제출)됐고, `draft`면 Play Console에서 사람이 출시한다.
- 실패: `gh run view "$RUN" --log-failed | tail -60`을 읽고 원인을 요약한다. 고칠 수 있으면 고치고,
  **이미 업로드된 빌드 번호로 다시 올리지 않는지** 확인한 뒤 `gh workflow run expo-release.yml -f ios=true`처럼 수동 실행한다.
- 태그가 안 생겼는데 빌드가 올라가 있으면(태그 단계 전에 실패) 직접 찍는다 — fingerprint를 꼭 넣는다(릴리스 커밋 기준 `fingerprint.sh check --clean`과 같은 조건으로 잰 hash):
  `git tag -a ios-v<버전>-<빌드> <릴리스 커밋> -m "fingerprint=<hash>" && git push origin ios-v<버전>-<빌드>`
  태그가 없으면 그 플랫폼은 다음 머지 때 OTA 대신 다시 빌드된다.

## 참고

- 서명만 확인: `gh workflow run expo-release.yml -f ios=true -f android=true -f dry_run=true`
- 앱 정보만 반영: `gh workflow run expo-release.yml -f metadata=true [-f screenshots=true]`
- 수동 OTA: `gh workflow run expo-release.yml -f update=true -f message="…"`
- 자동 배포 끄기(이번 머지만): 커밋 메시지에 `[skip release]`
- OTA 되돌리기: `npx eas-cli update:republish --group <이전 그룹 ID>` 또는 `npx eas-cli update:rollback` — 사용자 확인 후.
- 스크립트를 고치면 이 스킬의 `scripts/`를 고치고, 각 프로젝트의 `scripts/expo-release/`로 다시 복사한다.
