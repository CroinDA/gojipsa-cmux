# Notarization

GOJIPSA 배포 빌드는 `GOJIPSA.xcodeproj`를 기준으로 Xcode가 자동 signing과 Developer ID notarization을 관리한다. 별도 `notarytool` profile이나 수동 `SIGN_ID` 경로는 사용하지 않는다.

## 준비

1. Xcode → Settings → Accounts에서 Apple Developer 계정 로그인
2. `GOJIPSA.xcodeproj`의 `GOJIPSA` 타깃 signing이 Automatic으로 설정되어 있는지 확인
3. Team은 프로젝트 설정의 `DEVELOPMENT_TEAM` 값을 사용

## Release Artifact 생성

```bash
VERSION=2.0.4 BUILD_NUMBER=1 ./scripts/release.sh
```

이 명령은 다음 순서로 실행된다.

1. `xcodebuild archive -allowProvisioningUpdates`
2. `xcodebuild -exportArchive`로 Developer ID notarization 업로드
3. `xcodebuild -exportNotarizedApp`로 notarized app export
4. `dist/GOJIPSA.app` 복사
5. `dist/GOJIPSA-<VERSION>.dmg` 생성
6. 가능한 경우 DMG signing/stapling 및 Gatekeeper 검증

중간 산출물은 `.build/xcode/` 아래에 생성되고, 배포 결과물만 `dist/`에 남는다. 두 디렉터리는 git에 포함하지 않는다.

## Local Build

notarization 없이 앱 번들만 확인하려면:

```bash
CONFIGURATION=Debug ./scripts/build-app.sh
```

Release configuration으로 archive만 만들고 notarization은 생략하려면:

```bash
ACTION=archive VERSION=2.0.4 BUILD_NUMBER=1 ./scripts/build-app.sh
```

## 검증

```bash
codesign --verify --deep --strict --verbose=2 dist/GOJIPSA.app
xcrun stapler validate dist/GOJIPSA.app
spctl -a -vv -t exec dist/GOJIPSA.app
spctl -a -vv -t open --context context:primary-signature dist/GOJIPSA-2.0.4.dmg
```

Xcode automatic export는 앱 notarization을 책임진다. DMG signing은 로컬에 matching Developer ID private key가 있을 때만 수행한다. DMG가 unsigned여도 내부 앱은 notarized/stapled Developer ID 앱이어야 한다.
