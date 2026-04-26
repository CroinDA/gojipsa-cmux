# 꼬집사 (GOJIPSA) — Feature Roadmap

> 꼬집사 (GOJIPSA, "Pinch Butler") — 옛 이름 *Sentinel for cmux* — 의 다음 단계 기능 확장 계획.
> 작성: 2026-04-26 (CMUX × AIM Hackathon 당일).

## 컨셉 진화

| 단계 | 정체성 | 한 줄 |
|------|-------|------|
| v1.x | Sentinel (파수꾼) | 위험한 명령 감지하는 관찰자 |
| **v2.0.0** | **꼬집사 (GOJIPSA)** | 옆자리에 앉아 같이 일하는 동료. 위험할 땐 꼬집고, 약속 시간엔 챙겨주고, 심심하면 말 걸어옴. |

**브랜딩 결정 (v2.0.0)**:
- 프로젝트명/리포지토리/번들 ID/모듈명 모두 **GOJIPSA**로 통일
- 표시 이름: 한국어 **꼬집사**, 영문 표기 **GOJIPSA** ("꼬집다 + 집사" 합성어)
- 메뉴바 아이콘: 🤏 (pinch hand)

---

## Feature 1 — 고독한 앱 환경의 친구

### 핵심 변화
"이벤트 반응자" → "지속적 동반자". 단순 화면 분석에 **시간/감정/관계 컨텍스트** 추가.

### 구현 요소

| 컴포넌트 | 기능 | 신규/수정 |
|---------|-----|----------|
| `Companion.swift` | 페르소나 상태 (mood, energy, last interactions) | 신규 |
| `~/.gojipsa/memory.jsonl` | 최근 코멘트 + 사용자 반응 append-only 로그 | 신규 |
| `gemini_brain.systemPrompt` | 시간대/세션 길이/직전 상호작용 컨텍스트 주입 | 수정 |
| 새 트리거 | "오전 10시 첫 등장 → 인사", "3시간 연속 작업 → 휴식 권유" | 수정 |

### 새로 가능한 발화

- 09:15 — "어 일찍 시작했네. 커피 한 잔 ☕"
- 14:00 (점심 후) — "졸려보이는데... 산책 어때?"
- 자정 넘김 — "아직도 일해? 쉬엄쉬엄 ㅠㅠ"
- 같은 에러 3번 — "이거 어제도 봤던 에러야. 솔루션 정리할까?"

### 트레이드오프

- ✅ "Friend" USP가 단순 참견에서 격상 (Judge's Personal Rating ⬆️)
- ⚠️ 너무 잦은 발화 = 산만함 (현재도 throttle 있지만 더 정교화 필요)
- ⚠️ 메모리 누적되면 프롬프트 비대화 (요약 전략 필요)

### 시간 추정

**3시간** — Companion 클래스 + 메모리 로깅 + 시간 기반 트리거 + 시스템 프롬프트 진화

---

## Feature 2 — 위험 명령 가드레일 강화

### ⚠️ 결정적 기술 제약

cmux는 **읽기 전용 API**(`read-screen`, `tree`)만 공개. 사용자 키 입력을 가로채거나 명령 실행을 차단하는 직접 권한은 없음. 진짜 "Guardrail"은 아래 세 방법으로만 가능:

#### Path A — Pre-Enter 감지 (실현 가능, 권장)

사용자가 명령 입력 후 **Enter 누르기 전** 화면 상태 분석. 프롬프트 줄에 위험 패턴 보이면:

- 즉시 빨간 풀스크린 오버레이 + 캐릭터 알람
- "이 명령 진짜 실행할 거야? 5초 동안 멈춰" 체크 권유
- 사용자가 그래도 Enter 치면 본인 책임

**기술적 변경**: 폴링 주기 5초 → 1초로 단축. 마지막 줄(prompt line)이 변경된 경우만 체크 (Gemini 호출 안 하고 정규식만).

#### Path B — cmux write API 활용 (cmux 문서 확인 필요)

cmux가 AI 에이전트 대상 서버이므로, 키 입력 주입 API 가능성 큼 (`cmux send-keys`, `cmux write` 등). 있다면:

- 위험 패턴 감지 → `cmux send-keys ^U` (현재 줄 클리어) 자동 전송
- 캐릭터: "방금 그거 위험해서 내가 지웠어 ㅋㅋ"

**리스크**: 개발자 입장에서 본인 키스트로크가 갑자기 사라지는 건 매우 invasive. 옵트인 필수.

#### Path C — Accessibility API (비추천)

macOS Accessibility로 글로벌 키스트로크 감시 → 권한 요청 + 보안 의심. **하지 말 것.**

### 추천: **Path A 메인, Path B 옵션** (`config: aggressive_block: true`)

### 추가: 자연어 설명

- 현재: `🛑 rm -rf!` (이모지+짧은 문구)
- 업그레이드: Gemini로 **왜 위험한지 + 안전한 대안** 1문장 생성
  - "rm -rf /tmp/* 대신 `trash` CLI 써봐. 복구 가능함."
  - "git push -f 직전이야. 팀원이 이미 받았으면 사고날 수 있어. `--force-with-lease`가 더 안전."

### 시간 추정

**2-3시간** — 폴링 주기 단축 + prompt-line diff 감지 + 자연어 설명 통합 + 풀스크린 알람 UI

---

## Feature 3 — 이벤트 알리미

### 구현 요소

| 컴포넌트 | 기능 |
|---------|-----|
| `EventManager.swift` | 이벤트 CRUD, persistent storage |
| `~/.gojipsa/events.json` | 등록된 이벤트 (id, timestamp, label, fired) |
| `Scheduler.swift` | 30초마다 due 이벤트 체크, 타임아웃 시 onFire 콜백 |
| CLI 인터페이스 | `GOJIPSA remind "5분 후" "점심 먹기"` |
| 자연어 인터페이스 (보너스) | cmux 화면에 `# remind: 14시 미팅` 주석 → 꼬집사가 자동 등록 |
| 알림 UI | NSPanel 큰 알림 + macOS `UNUserNotificationCenter` 네이티브 알림 |
| 캐릭터 발화 | "야 14시 미팅 5분 전이야!" |

### 자연어 등록 예시 (보너스)

사용자가 작업 탭에서:
```
# remind: 14:00 standup 미팅
```
꼬집사가 화면에서 `# remind:` 패턴 발견 → 파싱 → 등록 → "OK 14시 standup 챙겨줄게 👍"

### 시간 추정

**2-3시간** — EventManager + Scheduler + CLI + native notification + 캐릭터 통합

---

## 6시간 안에 구현 우선순위

해커톤 18:00 마감 기준. 현재 약 8시간 남음 = 6시간 코딩 + 2시간 데모/발표.

| 순위 | 기능 | 시간 | 이유 |
|-----|-----|-----|------|
| 🥇 | **Feature 2 (가드레일) Path A** | 2.5h | 가장 demo-impactful. 위험 명령 입력 → 풀스크린 빨간 알람 = 3분 발표 강력한 임팩트 |
| 🥈 | **Feature 3 (알리미) 기본 CLI** | 2h | "터미널에 사는 비서" 컨셉 완성. CLI/자연어 등록 + 시간 도래 알림 |
| 🥉 | **Feature 1 (친구) 시간 기반만** | 1h | "Good morning"/"쉬어" 1-2개만 추가. 시간 부족하면 systemPrompt 한 단락으로 끝 |

**버려도 되는 것**: Feature 2 Path B (cmux write API), Feature 3 자연어 등록(보너스), Feature 1 메모리 로깅. 시간 남으면.

---

## 트랙별 어필 매핑 (Developer Tooling)

| 기능 | Tech Depth 30% | DevEx 25% | Real-World 25% | Demo 10% | Personal 10% |
|-----|---|---|---|---|---|
| Feature 1 친구 | 중 | 중 | 약 | 강 | **강** ⭐ |
| Feature 2 가드레일 | **강** | 중 | **강** | **강** ⭐ | 중 |
| Feature 3 알리미 | 중 | **강** | **강** | 중 | 중 |

→ Feature 2가 5개 항목 중 4개에서 강점 → **최우선**

---

## Open Questions

1. **꼬집사 v2.x 추가 페르소나**: 시간대별로 말투 변형 (오전 = 정중, 새벽 = 걱정)?
2. **Path B (cmux write API)**: 위험 명령 자동 차단 시도 여부 — invasive vs powerful 트레이드오프
3. **알리미 자연어 등록**: 보너스 기능으로 시도? 시간 빠듯하면 CLI만으로 충분
