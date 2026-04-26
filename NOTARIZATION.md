# Notarization Guide — 꼬집사 (GOJIPSA) for cmux

macOS Gatekeeper를 통과하는 Homebrew 배포 artifact를 만드는 흐름.

기본 경로는 **Xcode Accounts 기반 자동 Developer ID signing + Xcode notarization/export**다. `notarytool` 자격증명은 필요하지 않다.

## TL;DR

One-time setup:

1. Xcode → Settings → Accounts에서 Apple Developer Program 계정을 로그인한다.
2. Team `3BAL9BR86N`이 선택 가능해야 한다.
3. GitHub CLI로 release를 올릴 경우 `gh auth login -h github.com`을 완료한다.

Release:

```bash
VERSION=2.0.1 SIGNING_MODE=xcode-auto ./scripts/release.sh
```

성공하면:

- `dist/GOJIPSA.app`: Developer ID Application 서명 + Hardened Runtime + stapled notarization ticket
- `dist/GOJIPSA-2.0.1.dmg`: Homebrew cask 배포용 DMG

## Xcode Automatic Flow

`scripts/build-app.sh`는 `SIGNING_MODE=xcode-auto`에서 다음을 수행한다.

1. `xcodebuild archive -allowProvisioningUpdates`로 universal Release archive 생성
2. `scripts/ExportOptions-developer-id-upload.plist`로 Developer ID upload export 실행
3. `xcodebuild -exportNotarizedApp`을 notarization 완료까지 polling
4. notarized `GOJIPSA.app`을 `dist/`로 복사
5. `codesign`, `lipo`, `stapler`, `spctl` 검증

검증 명령:

```bash
lipo -archs dist/GOJIPSA.app/Contents/MacOS/GOJIPSA
codesign -dv --verbose=4 dist/GOJIPSA.app
xcrun stapler validate dist/GOJIPSA.app
spctl -a -vv -t exec dist/GOJIPSA.app
```

정상 결과는 `Developer ID Application`, `TeamIdentifier=3BAL9BR86N`, `flags=...runtime...`, `Notarization Ticket=stapled`, `source=Notarized Developer ID`가 보여야 한다.

## DMG Signing Note

Xcode automatic export는 `.app`을 Developer ID로 서명하고 notarize하지만, 새로 만든 DMG를 signing/stapling할 로컬 Developer ID private key를 항상 설치하지는 않는다.

- 로컬 `Developer ID Application` identity가 있으면 `scripts/build-dmg.sh`가 DMG도 Developer ID로 서명한다.
- 로컬 identity가 없으면 DMG는 unsigned로 생성하되, 내부 앱은 stapled notarized Developer ID 앱이다.
- Homebrew 설치 후 Gatekeeper가 최종 실행 대상으로 평가하는 것은 `/Applications/GOJIPSA.app`이므로, cask 배포의 핵심 검증은 app 기준으로 한다.

DMG 자체도 `spctl -t open`에서 `Notarized Developer ID`를 받아야 하는 배포 채널이 필요하면, Xcode automatic만으로는 부족하다. 이 경우 로컬 Developer ID Application private key를 Xcode Manage Certificates에서 생성/설치한 뒤 DMG 서명을 다시 수행하거나, 별도 notary workflow를 사용해야 한다.

## Manual Fallback

로컬 Developer ID Application identity와 `notarytool` profile을 쓰는 기존 수동 경로도 유지된다.

```bash
VERSION=2.0.1 \
SIGN_ID="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="AC_NOTARY" \
./scripts/release.sh
```

이 경로는 DMG 자체까지 notary service에 제출하고 staple한다.

## Homebrew Cask

release script가 출력한 SHA256을 tap repo의 `Casks/gojipsa.rb`에 반영한다.

```bash
brew style Casks/gojipsa.rb
brew audit --cask gojipsa
brew fetch --cask gojipsa --force
brew install --cask gojipsa
open -a gojipsa
brew uninstall --cask gojipsa
```

## Troubleshooting

### Homebrew 설치 후 "Apple은 악성 코드가 없음을 확인할 수 없습니다"

설치된 앱을 확인한다.

```bash
codesign -dv --verbose=4 /Applications/GOJIPSA.app 2>&1 | grep "Authority\\|TeamIdentifier\\|flags\\|Notarization"
spctl -a -vv -t exec /Applications/GOJIPSA.app
```

`source=Notarized Developer ID`가 아니면 `VERSION=2.0.1 SIGNING_MODE=xcode-auto ./scripts/release.sh`로 다시 만든 artifact만 GitHub Release와 Homebrew cask에 반영한다.

### Xcode account/session 문제

`xcodebuild -exportArchive`에서 Apple ID 또는 Team 권한 오류가 나면 Xcode → Settings → Accounts에서 로그인/MFA를 완료한 뒤 다시 실행한다.

### DMG signing이 skipped 됨

`security find-identity -v -p codesigning`에 `Developer ID Application: ...` identity가 없다는 뜻이다. Homebrew cask의 Gatekeeper 문제는 stapled app으로 해결되지만, DMG 자체 서명이 필요하면 Xcode Manage Certificates에서 로컬 Developer ID Application certificate/private key를 생성한다.
