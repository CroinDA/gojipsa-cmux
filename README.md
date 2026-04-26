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
3. API 키 설정:
   ```bash
   mkdir -p ~/.sentinel
   echo "YOUR_GEMINI_API_KEY" > ~/.sentinel/api-key.txt
   chmod 600 ~/.sentinel/api-key.txt
   ```
4. cmux 탭 안에서 실행:
   ```bash
   open -a Sentinel
   ```

### Option B — Build from source (개발자)

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

cmux 다른 탭을 열고 평소처럼 작업하면 됨. Sentinel은 우측 하단에 떠다니며 참견.

## Privacy

- 화면 내용은 Gemini API로 전송됩니다 (참견 생성 위해)
- **전송 전 자동 마스킹**: API 키, 토큰, JWT, PEM 키, password/secret 변수
- 위험 명령 감지(rm -rf 등)는 **로컬 정규식만** 사용 — 외부 송신 없음
- API 키 파일 권한: 600 (소유자만 읽기)

## Why Sentinel?

기존 Backseat Driver (yesterday's prototype)는 Python brain + Swift overlay + bash CLI 하이브리드 — 실험실 프로토타입 냄새.

**Sentinel은 단일 Swift 바이너리.** 더블클릭 한 번으로 실행. 9시간 안에 처음부터 새로 짠 hackathon 결과물.

## License
MIT

---
🛡️ Sentinel — for the agentic era of shells.
