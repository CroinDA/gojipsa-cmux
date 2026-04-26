# XCTest UI Tests — Templates for Xcode users

이 디렉토리의 파일들은 **Xcode가 설치된 머신**에서 사용 가능한 XCUIApplication 기반 UI 테스트입니다.

현재 SPM 빌드(Command Line Tools만 있는 환경)에선 컴파일되지 않으므로 **`Package.swift`에서 의도적으로 제외**되어 있습니다.

## 왜 따로 분리?

XCTest와 XCUIApplication 프레임워크는 **full Xcode** 설치 시에만 제공됩니다. Command Line Tools에는 없어서, `swift test`로 실행 불가능. 그래서 SPM 빌드에서는:

- **AX/CGWindow 기반 UI 테스트** (`Sources/GOJIPSATests/UITests.swift`) — Xcode 없이 실행 가능, 우리 메인 러너에 통합됨
- **이 디렉토리** — Xcode 사용자가 별도로 활용

## Xcode 실행

이 테스트는 현재 `GOJIPSA.xcodeproj`의 `GOJIPSAUITests` 타깃에 이미 연결되어 있습니다.

```bash
xcodebuild -project GOJIPSA.xcodeproj \
    -scheme GOJIPSA \
    -destination 'platform=macOS' \
    -only-testing:GOJIPSAUITests test
```

## 두 트랙의 역할

| 항목 | AX/CGWindow (`UITests.swift`) | XCTest (이 디렉토리) |
|------|-------------------------------|---------------------|
| 실행 환경 | Command Line Tools만 | Xcode 필수 |
| 테스트 가능 항목 | 윈도우 존재/위치/크기, 프로세스 라이프사이클 | + 키 입력 시뮬레이션, 텍스트 매칭, 탭/클릭 |
| 우리 러너 통합 | ✅ `swift run GOJIPSATests` | ❌ (xcodebuild 별도) |
| 권한 필요 | ❌ (CGWindowListCopyWindowInfo는 무권한) | XCUITest용 Accessibility |

해커톤 시연 환경에서는 AX/CGWindow 트랙이면 충분. XCTest는 향후 production 시나리오 (e2e 흐름, 키 입력 검증)용 베이스라인.
