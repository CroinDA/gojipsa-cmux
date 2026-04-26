# AGENTS.md — AI Agents Used to Build Sentinel

> CMUX × AIM Intelligence Hackathon Seoul · 2026.04.26 · Built 9am-onward

## Multi-Model Orchestration

| Agent | Model | Role |
|-------|-------|------|
| **Orchestrator** | Claude Opus 4.7 | 아키텍처 설계, 의사결정, 코드 작성 통제, 최종 통합 |
| **Design Reviewer** | Gemini 3.1 Pro | 심사 기준 분석, Swift-only 결정, 포지셔닝 (Sentinel 컨셉) |
| **Code Reviewer** | Codex (GPT-5.3) | Swift 코드 리뷰 (버그/아키텍처/개선점) |
| **Security Reviewer** | Qwen3-VL-32B (local MLX) | OWASP-기반 보안 리뷰, 키 노출/인젝션 검증 |
| **Task Classifier** | Qwen Router (local MLX) | 작업 분류 → 파이프라인 자동 라우팅 |

## Runtime Agent (앱 내부)

| Agent | Model | Role |
|-------|-------|------|
| **Sentinel Brain** | Gemini 2.5 Flash | 화면 텍스트 분석 → 상황 판단 + 한국어 참견 생성 |

REST API 직접 호출 (URLSession). SDK 의존성 없음.
`thinkingConfig.thinkingBudget=0` + `responseMimeType=application/json` 으로 토큰 효율 최적화.

## 빌드 흐름

```
Opus(설계) → Opus(직접 구현 — Swift 6.3)
           ↓
       빌드 검증 (swift build)
           ↓
   Gemini(디자인 리뷰) ∥ Codex(코드 리뷰) ∥ Qwen(보안 리뷰)
           ↓
       치명적 이슈 패치
           ↓
       GitHub 푸시
```

## 주요 의사결정 (모델별 기여)

1. **Swift-only 채택** — Gemini 3.1 Pro 디자인 리뷰가 결정적
   - "Python-Bash 하이브리드는 실험실 프로토타입, 정돈된 Swift 앱은 Product Hunt 향기"
2. **포지셔닝 업그레이드** — Gemini 3.1 Pro
   - Clippy → "**Sentinel: A Context-Aware Native Guardian for Shell Agents**"
3. **API 키 헤더 이전** — Qwen 보안 리뷰
   - URL 쿼리스트링 → `x-goog-api-key` 헤더 (로깅 노출 방지)
4. **SecretRedactor 추가** — Qwen 보안 리뷰
   - 외부 API 송신 전 토큰/JWT/PEM 자동 마스킹
5. **JSON 마크다운 fence 방어** — Codex/Gemini 리뷰
   - LLM이 가끔 ```json``` 래핑하는 케이스 방어

## Hackathon Tooling

- **Claude Code CLI** — Opus 4.7 (1M context) 메인 오케스트레이션
- **MCP Servers**:
  - `qwen_router.classify_task` — 작업 분류
  - `gemini_design.design_review` — UI/UX & 전략 판단
  - `codex_review.code_review` — 코드 리뷰
  - `qwen_security.security_review` — 보안 리뷰
- **GitHub CLI** — 레포 생성 & 푸시
