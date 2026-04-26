# Notarization Guide — Sentinel for cmux

> macOS Gatekeeper 통과되는 배포용 빌드 만드는 흐름.
> Apple Developer Program 멤버십 보유자가 한 번만 셋업하면 됨.

## TL;DR — 한 번 셋업 후 매 릴리즈마다 실행

**One-time setup (5-15분):**
1. Developer ID Application 인증서 발급 + 키체인 설치
2. Apple ID에서 app-specific password 생성
3. `notarytool store-credentials`로 키체인에 자격증명 저장

**매 릴리즈마다 (자동, ~10분):**
```bash
SIGN_ID="Developer ID Application: 팀원이름 (TEAMID)" ./scripts/build-app.sh
SIGN_ID="Developer ID Application: 팀원이름 (TEAMID)" ./scripts/build-dmg.sh
NOTARY_PROFILE="AC_NOTARY" ./scripts/notarize.sh
```

끝. `dist/Sentinel-X.Y.Z.dmg`가 노타라이즈+staple된 배포용 빌드.

---

## Phase 1 — One-time Setup

### 1-1. Developer ID Application 인증서 발급

1. [https://developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) 접속
2. 우측 상단 **➕** → **Developer ID Application** 선택 → **Continue**
3. CSR(Certificate Signing Request) 파일 필요 → 별도 터미널에서 만들기:
   - **Keychain Access** 앱 실행
   - 메뉴: **Keychain Access** → **Certificate Assistant** → **Request a Certificate from a Certificate Authority...**
   - 이메일/이름 입력, **Saved to disk** 선택, **Continue**
   - `.certSigningRequest` 파일 데스크탑에 저장
4. Apple 사이트로 돌아가서 CSR 파일 업로드
5. 인증서(`.cer`) 다운로드 → 더블클릭 → 키체인에 자동 등록
6. 검증:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
   출력 예시:
   ```
   1) ABC1234567890ABCDEF "Developer ID Application: 홍길동 (XYZ987654)"
   ```
   따옴표 안의 전체 문자열이 `SIGN_ID`로 사용됨.

### 1-2. App-Specific Password 생성

1. [https://appleid.apple.com](https://appleid.apple.com) 로그인
2. **Sign-In and Security** → **App-Specific Passwords** → **Generate Password**
3. 라벨: `Sentinel notarization`
4. 16자리 비밀번호 표시됨 (예: `abcd-efgh-ijkl-mnop`) — 한 번만 보여주니 메모

### 1-3. Team ID 확인

1. [https://developer.apple.com/account](https://developer.apple.com/account) → **Membership details**
2. **Team ID** 필드 (10자 영숫자, 예: `XYZ987654`) 메모

### 1-4. notarytool 자격증명을 키체인에 저장 (한 번만)

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
    --apple-id "your-apple-id@example.com" \
    --team-id "XYZ987654" \
    --password "abcd-efgh-ijkl-mnop"
```

성공하면:
```
This process stores your credentials securely in the Keychain.
You reference these credentials using a profile name.
Profile name: AC_NOTARY
Credentials saved to Keychain.
```

이후 `--keychain-profile "AC_NOTARY"` 한 줄로 자격증명 불러옴. 비밀번호 코드/스크립트에 노출 없음.

---

## Phase 2 — Build & Sign

```bash
cd sentinel-cmux

# SIGN_ID는 1-1에서 확인한 정확한 cert 이름 (따옴표 안 전체)
export SIGN_ID="Developer ID Application: 홍길동 (XYZ987654)"

./scripts/build-app.sh   # → dist/Sentinel.app (Hardened Runtime + Developer ID 서명)
./scripts/build-dmg.sh   # → dist/Sentinel-1.0.0.dmg (서명됨)
```

검증:
```bash
codesign -dv --verbose=4 dist/Sentinel.app 2>&1 | grep "Authority\|Identifier\|Runtime"
```
**Authority=Developer ID Application** 가 보여야 함. 안 보이면 인증서 셋업 다시 확인.

---

## Phase 3 — Notarize

```bash
export NOTARY_PROFILE="AC_NOTARY"
./scripts/notarize.sh
```

스크립트 동작:
1. DMG를 Apple notary 서비스에 업로드
2. **--wait** 옵션으로 완료까지 대기 (보통 2-15분)
3. 결과 확인 (`Accepted` / `Invalid`)
4. `Accepted`면 `xcrun stapler staple`로 staple
5. `spctl` 검증

성공 시 끝에:
```
✅ Notarized & stapled: dist/Sentinel-1.0.0.dmg
   spctl: source=Notarized Developer ID
```

이 DMG는 어느 맥에서든 더블클릭으로 열리고, Gatekeeper 경고 없음.

---

## Phase 4 — 릴리즈 업로드

```bash
gh release create v1.0.1 \
    "dist/Sentinel-1.0.1.dmg" \
    --title "Sentinel for cmux v1.0.1" \
    --notes "Notarized release"
```

---

## 트러블슈팅

### `Invalid` notarization 결과
notary 서비스에서 거부함. 로그 확인:
```bash
xcrun notarytool log <SUBMISSION_ID> --keychain-profile "AC_NOTARY"
```

자주 보이는 원인:
- Hardened Runtime 미적용 → `build-app.sh`에 `--options=runtime` 있는지 확인
- 서명 안 된 임베디드 바이너리 → `--deep` 옵션으로 재서명
- `LSMinimumSystemVersion`이 너무 낮음 → 13.0 이상이어야 안전

### `errSecInternalComponent` (codesign)
키체인 잠김. 해제:
```bash
security unlock-keychain login.keychain-db
```

### 인증서가 안 보임
키체인 앱에서 인증서가 **My Certificates** 카테고리에 있어야 하고, **expand**(▶) 하면 **private key**가 같이 보여야 함. private key 없으면 다른 맥에서 발급한 거라 못 씀.

---

## 보안 주의

- **App-specific password**는 키체인에 `notarytool store-credentials`로만 저장. 평문 파일/git/Slack에 절대 보관 금지.
- **인증서 백업**: 키체인에서 우클릭 → Export → `.p12` 파일 + 강력한 비밀번호. 안전한 곳에 보관 (인증서 잃으면 재발급에 시간 걸림).
- **Team ID, Apple ID**는 민감하지 않음 (공개 정보).

---

## 참고

- [Apple — Customizing the Notarization Workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple — Signing a Daemon with a Restricted Entitlement](https://developer.apple.com/documentation/xcode/signing-a-daemon-with-a-restricted-entitlement)
- [Apple — Resolving Common Notarization Issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
