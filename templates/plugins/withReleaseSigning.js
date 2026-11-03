const { withAppBuildGradle } = require('expo/config-plugins');

/**
 * expo-release — Android 릴리스 서명(업로드 키) 주입 config plugin.
 *
 * `android/` 는 prebuild 산출물이라 build.gradle 을 직접 고치면 다음 `expo prebuild --clean` 에
 * 날아간다. prebuild 때마다 여기서 다시 넣는다.
 *
 * 키 값은 Gradle 속성에서 읽는다: 로컬은 ~/.gradle/gradle.properties, CI는
 * ORG_GRADLE_PROJECT_<이름> 환경변수(scripts/expo-release/android-build.sh가 넣는다).
 * 속성 이름은 .expo-release.json 의 android.signing_props 와 같아야 한다.
 * 속성이 없으면 debug 서명으로 폴백한다 — android-build.sh 가 debug 서명 AAB 를 거부한다.
 */
const P = {
  storeFile: 'UPLOAD_STORE_FILE',
  storePassword: 'UPLOAD_STORE_PASSWORD',
  keyAlias: 'UPLOAD_KEY_ALIAS',
  keyPassword: 'UPLOAD_KEY_PASSWORD',
};

const RELEASE_SIGNING_CONFIG = `        release {
            if (project.hasProperty('${P.storeFile}')) {
                storeFile file(project.property('${P.storeFile}'))
                storePassword project.property('${P.storePassword}')
                keyAlias project.property('${P.keyAlias}')
                keyPassword project.property('${P.keyPassword}')
            }
        }
`;
const RELEASE_SIGNING_REF = `signingConfig project.hasProperty('${P.storeFile}') ? signingConfigs.release : signingConfigs.debug`;

function assertReplaced(before, after, what) {
  if (before === after) {
    throw new Error(`[withReleaseSigning] ${what} 치환 실패 — android/app/build.gradle 템플릿이 바뀐 것으로 보인다.`);
  }
}

module.exports = function withReleaseSigning(config) {
  return withAppBuildGradle(config, (cfg) => {
    let src = cfg.modResults.contents;
    if (src.includes(P.storeFile)) return cfg;

    const withConfig = src.replace(/(signingConfigs \{[\s\S]*?\n)(    \})/, `$1${RELEASE_SIGNING_CONFIG}$2`);
    assertReplaced(src, withConfig, 'signingConfigs.release 추가');
    src = withConfig;

    const withRef = src.replace(
      /\/\/ Caution! In production[\s\S]*?\n(\s*)signingConfig signingConfigs\.debug/,
      `$1${RELEASE_SIGNING_REF}`,
    );
    assertReplaced(src, withRef, 'buildTypes.release 서명 참조 교체');
    cfg.modResults.contents = withRef;
    return cfg;
  });
};
