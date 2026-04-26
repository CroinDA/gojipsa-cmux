# Sentinel for cmux 🛡️

> A Context-Aware Native Guardian for Shell Agents.
> One Swift binary. Zero Python. Zero dependencies.

cmux 터미널 위에 떠다니는 AI 파수꾼. 위험한 명령, 빌드 실패, 농땡이 — 실시간으로 감지하고 참견합니다.

**Built at CMUX × AIM Intelligence Hackathon Seoul · 2026.04.26**

## What it does

| Trigger | Reaction |
|---------|----------|
| `rm -rf /`, `git push -f`, `DROP TABLE`, fork bomb 등 12종 위험 패턴 | 즉시 빨간 경고 |
| 90초 이상 화면 변동 없음 | 농땡이 잔소리 |
| 빌드/테스트/에러 패턴 | Gemini 분석 후 상황별 코멘트 |
| 일반 작업 | 가끔씩 위트있는 한마디 |

## Architecture

```
Swift macOS app (.app bundle)
├── NSPanel overlay  ← 떠다니는 캐릭터 + 말풍선
├── ScreenWatcher    ← cmux subprocess (read-screen / tree)
├── DangerDetector   ← 12 regex fast-path
├── SecretRedactor   ← API 키/JWT/PEM 자동 마스킹
└── GeminiClient     ← URLSession → Gemini 2.5 Flash
```

전체 단일 바이너리. Python/Node/Bash 의존성 0개.

## Install

### Prerequisites
- **macOS 13+ (Apple Silicon)**
- **[cmux](https://cmux.dev)** (DMG 또는 `brew install cmux`)
- **Gemini API key** ([aistudio.google.com/apikey](https://aistudio.google.com/apikey))

### Option A — DMG (권장, 일반 사용자)

1. **[Latest Release](https://github.com/CroinDA/sentinel-cmux/releases/latest)** 에서 `Sentinel-X.Y.Z.dmg` 다운로드
2. 더블클릭 → Sentinel.app을 Applications 폴더로 드래그
   - **자체서명 빌드인 경우** (v1.0.0 등): Gatekeeper 차단 시
     ```bash
     xattr -dr com.apple.quarantine ~/Downloads/Sentinel-*.dmg
     ```
   - **노타라이즈된 빌드인 경우** (v1.0.1+): 그냥 더블클릭으로 OK
3. **Gemini API 키 설정**:
   ```bash
   mkdir -p ~/.sentinel
   echo "YOUR_GEMINI_API_KEY" > ~/.sentinel/api-key.txt
   chmod 600 ~/.sentinel/api-key.txt
   ```
4. **cmux Socket Password 설정** (v1.2.0+ 권장 — 1-pane workflow)
   - cmux 메뉴 → **Settings** → Socket Control → Password 설정
   - 그 다음 password를 Sentinel에 알려주기:
     ```bash
     echo "YOUR_CMUX_PASSWORD" > ~/.sentinel/cmux-password.txt
     chmod 600 ~/.sentinel/cmux-password.txt
     ```
   - 이걸 안 하면 Sentinel을 cmux 탭 **안**에서만 실행 가능 (foreground)
   - 설정하면 어디서든 실행 가능 (Spotlight, Applications, etc.)
5. 실행:
   ```bash
   # password 설정한 경우 — 어디서든
   open -a Sentinel
   # 또는 cmux 탭 안에서
   /Applications/Sentinel.app/Contents/MacOS/Sentinel
   ```

### Option B — Build from source (개발자)

두 빌드 시스템 동시 지원:
- **SPM** (`Package.swift`) — 빠른 dev loop, XCTest-free 자체 테스트 러너 (Xcode 없이도 OK)
- **Xcode** (`project.yml` → XcodeGen → `Sentinel.xcodeproj`) — XCTest UI 테스트, IDE 디버깅

```bash
git clone https://github.com/CroinDA/sentinel-cmux.git
cd sentinel-cmux

# API 키 설정 (위와 동일)

# 빌드 (.app + .dmg 한 번에)
./scripts/build-app.sh
./scripts/build-dmg.sh

# 또는 바이너리만:
swift build -c release
.build/release/Sentinel
```

### 테스트 실행

XCTest-free 테스트 러너 (Xcode 미설치 머신에서도 동작):
- **Smoke**: 앱 바이너리/cmux/API 키 점검
- **Unit**: DangerDetector(20+), SecretRedactor(15+), ScreenWatcher 상수
- **Integration**: Gemini 라이브 호출 (analyze + explainDanger)
- **UI 자동화**: Sentinel 바이너리 launch → CGWindowListCopyWindowInfo로 NSPanel 윈도우 검증 → cleanup

```bash
# 전체 (라이브 통합 + UI 자동화 포함)
GEMINI_TEST_KEY=$(cat ~/.sentinel/api-key.txt) swift run SentinelTests

# Gemini 통합만 스킵
swift run SentinelTests
```

#### UI 자동화 테스트 (`Sources/SentinelTests/UITests.swift`)

`--demo-overlay` / `--demo-alarm` 플래그로 Sentinel 바이너리를 직접 launch한 뒤 시스템 윈도우 메타데이터를 검사. **CGWindowListCopyWindowInfo는 권한 불필요** — 화면 녹화/Accessibility 권한 안 받아도 됨.

기능 추가 시 UI 테스트 추가 패턴:
1. `main.swift`에 `--demo-<feature>` 플래그 추가 (기능을 즉시 띄우고 dwell 후 exit)
2. `UITests.swift`에 `runSuite("UI — <feature> ...")` 블록 추가
3. `swift run SentinelTests` — 자동 포함됨

#### XCTest UI 테스트 (Xcode 사용자용)

`Tests/SentinelUITests/` 정식 testTarget — XCUIApplication 기반. Xcode 설치 + 첫 실행 시 Accessibility 권한 다이얼로그 한 번만 허용하면 자동화 가능.

```bash
# 1. xcodegen으로 .xcodeproj 생성 (한 번만)
brew install xcodegen
xcodegen generate

# 2. Xcode에서 열기
open Sentinel.xcodeproj

# 3. 또는 CLI로 빌드/테스트
xcodebuild -project Sentinel.xcodeproj -scheme Sentinel build
xcodebuild -project Sentinel.xcodeproj -scheme Sentinel test
```

UI 테스트 첫 실행 시:
1. SentinelUITests-Runner.app이 Accessibility 권한 요청
2. **System Settings → Privacy & Security → Accessibility** 에서 허용
3. 이후 자동 실행

### 배포용 빌드 (노타라이즈)

Apple Developer Program 멤버는 [NOTARIZATION.md](NOTARIZATION.md) 따라하면 Gatekeeper 통과되는 배포 빌드 만들 수 있음:

```bash
SIGN_ID="Developer ID Application: NAME (TEAMID)" ./scripts/build-app.sh
SIGN_ID="Developer ID Application: NAME (TEAMID)" ./scripts/build-dmg.sh
NOTARY_PROFILE="AC_NOTARY" ./scripts/notarize.sh
```

cmux 다른 탭을 열고 평소처럼 작업하면 됨. Sentinel은 우측 하단에 떠다니며 참견.

## Privacy

- 화면 내용은 Gemini API로 전송됩니다 (참견 생성 위해)
- **전송 전 자동 마스킹**: API 키, 토큰, JWT, PEM 키, password/secret 변수
- 위험 명령 감지(rm -rf 등)는 **로컬 정규식만** 사용 — 외부 송신 없음
- API 키 파일 권한: 600 (소유자만 읽기)
- **cmux socket password도 600 권한으로 저장** (`~/.sentinel/cmux-password.txt`)

## Workflows

| 모드 | cmux 탭 수 | Sentinel 실행 위치 | 설정 필요 |
|------|----------|--------------------|----------|
| **기본 (PID-ancestry auth)** | 2개 (작업 + Sentinel) | cmux 탭 안 (foreground) | API key만 |
| **Password auth (권장, v1.2.0+)** | **1개로 OK** | 아무데서나 (Spotlight, `open -a` 등) | API key + cmux password |

password 모드를 강력히 추천 — cmux Settings에서 한 번 설정하고 `~/.sentinel/cmux-password.txt`에 저장하면 끝.

## Why Sentinel?

기존 Backseat Driver (yesterday's prototype)는 Python brain + Swift overlay + bash CLI 하이브리드 — 실험실 프로토타입 냄새.

**Sentinel은 단일 Swift 바이너리.** 더블클릭 한 번으로 실행. 9시간 안에 처음부터 새로 짠 hackathon 결과물.

## License
MIT

---
🛡️ Sentinel — for the agentic era of shells.
