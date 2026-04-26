# AGENTS.md — AI Agents Used to Build 꼬집사 (GOJIPSA)

> CMUX × AIM Intelligence Hackathon Seoul · 2026.04.26

이 프로젝트는 **여러 AI 에이전트가 역할 분담**해서 만들었음. 사람 1명 + Claude Code CLI를 중심으로, 각 작업마다 가장 적합한 모델을 라우팅해서 사용.

> v1.x 시절 이름은 *Sentinel for cmux* — v2.0.0부터 **꼬집사 (GOJIPSA)**: "꼬집다 + 집사" 합성어.

---

## 빌드 타임 (개발 시 협업 모델)

| Agent | Model | 역할 |
|-------|-------|------|
| **Orchestrator** | Claude Opus 4.7 (1M context) | 아키텍처 설계, 의사결정, Swift 코드 작성, 최종 통합, git 관리 |
| **Design Reviewer** | Gemini 3.1 Pro | UI/UX 결정 (Swift-only 채택, 'Sentinel/꼬집사' 포지셔닝, 단순화 결정) |
| **Code Reviewer** | Codex (GPT-5.3, reasoning=high) | Swift 코드 리뷰 — 버그/아키텍처/엣지케이스 |
| **Security Reviewer** | Qwen3-VL-32B (local MLX) | OWASP-기반 보안 리뷰 — 키 노출, 인젝션, race condition |
| **Task Classifier** | Qwen Router (local MLX) | 모든 사용자 요청을 분류 → 적합한 파이프라인 자동 라우팅 |

## 런타임 (앱 안에서 동작)

| Agent | Model | 역할 |
|-------|-------|------|
| **꼬집사 Brain** | **Gemini 2.5 Flash** | cmux 화면 텍스트 1초마다 분석 → 한국어 멘트 + emotion(state) 생성 |
| **Danger Explainer** | Gemini 2.5 Flash (다른 prompt) | 위험 명령 감지 시 "왜 위험한가 + 안전한 대안" 자연어 생성 |

REST 직접 호출 (URLSession). SDK 의존성 없음.
- `thinkingConfig.thinkingBudget=0` (응답 속도 ↑)
- `responseMimeType=application/json` (analyze에서 구조화된 응답)
- 1초 throttle + 화면 변화 감지로 60 RPM 무료 티어 안에 유지

---

## 빌드 흐름

```
Opus(설계) → Opus(직접 구현 — Swift 5.9 + AppKit + Lottie)
           ↓
       빌드 검증 (swift build / xcodebuild)
           ↓
   Gemini(디자인) ∥ Codex(코드) ∥ Qwen(보안) — 병렬 리뷰
           ↓
       치명적 이슈 패치 (Opus 적용)
           ↓
       SPM 107개 + XCTest 12개 자동 테스트
           ↓
       GitHub commit/push + DMG release
```

---

## 주요 의사결정 (모델별 기여)

| 결정 | 주도 모델 | 영향 |
|------|----------|------|
| **Swift-only 채택** | Gemini 3.1 Pro | 단일 Swift 바이너리가 hybrid 스택보다 시연 임팩트 + DevEx + Tech Depth 모두 우수 |
| **'Sentinel' 포지셔닝** (Clippy → Guardian) | Gemini 3.1 Pro | "A Context-Aware Native Guardian for Shell Agents" — Manaflow 창립자(cmux 제작자)에게 어필되는 framing |
| **'꼬집사 (GOJIPSA)' 리브랜딩** | 사용자 직접 지시 | "꼬집다 + 집사" 합성어, 한국어권 친근감 + 영문 SEO 양립 (v2.0.0) |
| **API 키 헤더 이전** | Qwen Security | URL 쿼리 → `x-goog-api-key` 헤더 (로깅 노출 방지) |
| **SecretRedactor 추가** | Qwen Security | 외부 API 송신 전 토큰/JWT/PEM 자동 마스킹 |
| **JSON 마크다운 fence 방어** | Codex | LLM이 ```json``` 래핑하는 케이스 방어 코드 |
| **Lottie character 채택** | Opus + 사용자 협의 | 이모지 → 진짜 캐릭터 애니메이션 (UX 격상) |
| **이모지 fallback 제거** | 사용자 직접 지시 | "집사는 항상 집사" — 단순 + 일관성 |
| **bobAnimation 제거** | Opus 디버그 | LottieAnimationView 내부 layer 렌더링과 충돌 → 캐릭터 깜빡임 → 제거 |
| **Gemini throttle 12s → 1s** | 사용자 피드백 | 더 빠른 반응 cadence 요구 |
| **메뉴바 status item** | 사용자 직접 지시 | 항상 보이는 상태 + 안전한 종료 |
| **PathMigration 자동 마이그레이션** | Opus | v1.x 사용자가 ~/.sentinel/ 설정을 잃지 않도록 첫 실행 시 ~/.gojipsa/로 복사 |

---

## Hackathon Tooling

```
Claude Code CLI (Opus 4.7, 1M context)
  └─ Custom MCP Servers (모두 stdio, 로컬 또는 OAuth)
      ├─ qwen_router.classify_task   ← 모든 사용자 메시지 자동 분류
      ├─ qwen_security.security_review
      ├─ codex_review.code_review     ← Codex CLI (GPT-5.3) wrapper
      ├─ gemini_design.design_review  ← Gemini Pro CLI wrapper
      └─ kimi_research.web_research   (이번엔 미사용)
  └─ Hooks
      └─ PreToolUse[Bash] → security-gate.sh (commit/push 전 리뷰 강제)
GitHub CLI (gh)
  └─ 레포 생성, push, releases (v1.0.0 ~ v1.4.4 = pre-release, v2.0.0 = stable rebrand)
Xcode
  └─ GOJIPSA.xcodeproj → canonical app archive/signing/UI-test project
```

---

## 결과물

- 5개 dotLottie 캐릭터 (note_taking / Checking / dancing / nodding_sighingly / frightening)
- 119/119 테스트 통과 (SPM 107 + XCTest 12)
- 9개 GitHub Release (v1.0.0 → v1.4.4 = pre-release, v2.0.0 = 꼬집사 리브랜딩 stable)
- 단일 Swift 바이너리 (.app 약 9MB)
- 이 모두를 **AI 에이전트 5종 + 사람 1명**이 협업으로 완성
