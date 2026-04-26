# 꼬집사 (GOJIPSA) for cmux 🤏

> 꼬집다 (Pinch) + 집사 (Butler) — A Context-Aware Native Guardian for Shell Agents.
> One Swift binary. Zero Python. Zero JS. Zero shell glue.

cmux 터미널 옆에 떠다니는 **AI 집사**. 위험 명령은 즉시 막고, 빌드 실패에는 위로하고, 농땡이엔 잔소리. Gemini가 화면을 1초마다 보고 상황에 맞는 한국어 멘트와 표정을 만든다.

**Built at CMUX × AIM Intelligence Hackathon Seoul · 2026.04.26**

---

## Features

| 기능 | 동작 |
|------|------|
| **6 표정 캐릭터** | dotLottie 애니메이션 (idle / talking / celebrating / nagging / alarmed / sleeping) |
| **위험 명령 가드레일** | 12종 패턴 (rm -rf, force push, DROP TABLE, fork bomb, dd to disk 등) → 풀스크린 빨간 알람 + Gemini 자연어 설명 (1-3초) |
| **Gemini 라이브 코멘트** | cmux 화면 1초 폴링 → 변화 감지 → Gemini 2.5 Flash 분석 → 캐릭터 + 멘트 |
| **메뉴바 상태 아이콘** | 🟢🤏 connected / 🔒🤏 access denied / 🔴🤏 down / ⏱🤏 timeout — 클릭으로 Quit |
| **시크릿 자동 마스킹** | API 키, JWT, PEM, GitHub 토큰, AWS 키 등 외부 송신 전 자동 redact |
| **농땡이 잔소리** | 90초 이상 화면 변동 없으면 자연스러운 nag |
| **단일 Swift 바이너리** | Python/Node/Bash 의존성 0. `.app` 더블클릭으로 실행 |
| **자동 마이그레이션** | 구버전(Sentinel for cmux)의 `~/.sentinel/` 설정을 첫 실행 시 자동으로 `~/.gojipsa/`로 이전 |

---

## Tech Stack

### 런타임 (앱 자체)

| 레이어 | 기술 |
|--------|------|
| 언어 | Swift 5.9, Swift Concurrency (async/await, actors, @MainActor) |
| GUI | AppKit — `NSPanel(.borderless, .nonactivatingPanel)`, `NSStatusBar` |
| 애니메이션 | [Airbnb lottie-ios](https://github.com/airbnb/lottie-ios) 4.5+, dotLottie 포맷 |
| 네트워킹 | `URLSession` 직접 사용 (Gemini SDK 의존성 없음) |
| AI | Google **Gemini 2.5 Flash** REST API (`thinkingBudget=0`, `responseMimeType=application/json`) |
| 터미널 통합 | `cmux` CLI subprocess (read-screen, tree, ping) — password auth 지원 |
| 코드 서명 | Developer ID Application + Hardened Runtime + notarization |

### 빌드 시스템

| 시스템 | 사용처 |
|--------|--------|
| **Swift Package Manager** | 빠른 dev loop, 로컬 빌드 |
| **Xcode project** | Release archive/signing, IDE 디버깅 |

### 테스트

테스트 스위트는 재작성 예정입니다. 기존 SPM 자체 러너와 XCTest UI 테스트 타깃은 제거되었습니다.

### 보안

| 레이어 | 처리 |
|--------|------|
| API 키 저장 | `~/.gojipsa/api-key.txt` (mode 0600) — env var 우선 |
| API 키 전송 | `x-goog-api-key` HTTP 헤더 (URL 쿼리 X) |
| Gemini 송신 데이터 | SecretRedactor가 sk-/AIza/AKIA/JWT/PEM/Bearer/password= 패턴 자동 마스킹 |
| 위험 명령 감지 | **로컬 정규식만** (외부 API 송신 X) |
| cmux password | 별도 파일 (mode 0600) + ENV 우선, loose perm 시 stderr 경고 |
| 마이그레이션 | `~/.sentinel/` → `~/.gojipsa/` 복사 시 0600 강제, 기존 파일 덮어쓰기 X |

---

## Architecture

```
┌──────────────────────── GOJIPSA.app ───────────────────────┐
│                                                             │
│   AppDelegate                                               │
│   ├── PathMigration (~/.sentinel → ~/.gojipsa, 첫 실행만)   │
│   ├── OverlayPanel (NSPanel)        ┌── Lottie 애니메이션  │
│   │   ├── LottieAnimationView ◀────┤   (6 emotion)         │
│   │   └── bubbleLabel (auto-resize) │                       │
│   │                                                         │
│   ├── AlarmPanel (full-screen)                              │
│   │   └── 위험 명령 풀스크린 빨간 카드 + Gemini 설명        │
│   │                                                         │
│   ├── StatusBarController                                   │
│   │   └── NSStatusBar item (🤏) — Quit / Show status        │
│   │                                                         │
│   └── ScreenWatcher (actor)                                 │
│       │  ┌──────────────────────────────────────────┐       │
│       │  │ 1. cmux read-screen (1초 폴링)           │       │
│       │  │ 2. DangerDetector regex (최근 2000자)    │       │
│       │  │    └→ 위험 시: AlarmPanel + Gemini       │       │
│       │  │       explainDanger 호출                 │       │
│       │  │ 3. SecretRedactor (송신 전 마스킹)       │       │
│       │  │ 4. GeminiClient.analyze (1초 throttle)  │       │
│       │  │    └→ Comment(text, emotion)             │       │
│       │  │       → OverlayPanel.speak               │       │
│       │  │           → Lottie + bubble 갱신         │       │
│       │  └──────────────────────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Install

### Prerequisites
- **macOS 13+ (Apple Silicon 또는 Intel)**
- **[cmux](https://cmux.dev)** (DMG 또는 `brew install cmux`)
- **Gemini API key** ([aistudio.google.com/apikey](https://aistudio.google.com/apikey))

### Option A — Homebrew tap (권장)

```bash
brew tap CroinDA/gojipsa-cmux
brew install --cask gojipsa

# API 키 설정
mkdir -p ~/.gojipsa
echo "YOUR_GEMINI_API_KEY" > ~/.gojipsa/api-key.txt
chmod 600 ~/.gojipsa/api-key.txt

# cmux Settings → Socket Control → Password 설정 후 (1-pane 워크플로 권장):
echo "YOUR_CMUX_PASSWORD" > ~/.gojipsa/cmux-password.txt
chmod 600 ~/.gojipsa/cmux-password.txt

# 실행
open -a gojipsa
```

### Option B — DMG

```bash
cd ~/Downloads
curl -LO https://github.com/CroinDA/gojipsa-cmux/releases/latest/download/GOJIPSA-2.0.4.dmg
hdiutil attach GOJIPSA-2.0.4.dmg -nobrowse
ditto "/Volumes/GOJIPSA 2.0.4/GOJIPSA.app" "/Applications/GOJIPSA.app"
hdiutil detach "/Volumes/GOJIPSA 2.0.4"
open -a gojipsa
```

> **구버전 사용자(Sentinel for cmux v1.x)**: `~/.sentinel/` 안의 키 파일은 GOJIPSA 첫 실행 시 자동으로 `~/.gojipsa/`로 복사된다. 0600 권한 유지, 기존 파일은 절대 덮어쓰지 않음.

### Option C — Build from source (개발자)

```bash
git clone https://github.com/CroinDA/gojipsa-cmux.git
cd gojipsa-cmux

# SPM 빌드 (가장 빠름)
swift build -c release
.build/release/GOJIPSA

# Xcode에서 열기
open GOJIPSA.xcodeproj

# 배포용 .app + .dmg 생성은 Xcode Apple ID 계정 필요
VERSION=2.0.4 SIGNING_MODE=xcode-auto ./scripts/release.sh
```

### 배포용 (Gatekeeper 통과)

Apple Developer Program 멤버는 [NOTARIZATION.md](NOTARIZATION.md) 참고:

```bash
VERSION=2.0.4 SIGNING_MODE=xcode-auto ./scripts/release.sh
```

---

## Privacy

- 화면 내용은 Gemini API로 전송됨 (참견 생성 위해)
- **전송 전 자동 마스킹**: API 키, JWT, PEM, GitHub/AWS 토큰, password 변수
- 위험 명령 감지(rm -rf 등)는 **로컬 정규식만** — 외부 송신 없음
- API 키 + cmux password 파일 권한: 0600
- 레거시 마이그레이션은 home dir 안에서만 동작 (외부 경로 접근 X)

---

## Workflows

| 모드 | cmux 탭 수 | GOJIPSA 실행 위치 | 설정 |
|------|----------|------------------|------|
| 기본 (PID-ancestry auth) | 2개 (작업 + GOJIPSA) | cmux 탭 안 (foreground) | API key만 |
| **Password auth (권장)** | **1개로 OK** | 아무데서나 (Spotlight 등) | API key + cmux password |

---

## License
MIT

---
🤏 꼬집사 — for the agentic era of shells.
