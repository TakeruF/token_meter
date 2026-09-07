# Token Meter

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · **한국어**

Claude Code, Codex, Copilot CLI 사용량을 확인하는 macOS 네이티브 앱.

> [!IMPORTANT]
> **Windows 버전 개발은 동결되었습니다.** Windows 소스는 참고용으로만 이 저장소에 남아 있습니다. 새 릴리스, 업데이트, 유지보수, 지원, Microsoft Store 제출 및 직접 배포는 하지 않습니다. Windows 코드와 과거 문서를 지원되는 제품으로 받아들이지 마세요. 현재 Token Meter는 macOS만 지원합니다.

[<img src="https://raw.githubusercontent.com/machiav3lli/oandbackupx/main/badge_github.png" alt="GitHub에서 받기" height="60">](https://github.com/TakeruF/token_meter/releases/latest)

[공식 사이트 · 다운로드](https://takeruf.com/projects/token-meter) · [GitHub Releases](https://github.com/TakeruF/token_meter/releases/latest)

## 스크린샷

**메뉴 막대와 위젯으로 잔여량을 한눈에.**

![Token Meter 메뉴 막대 팝오버와 위젯에 Claude와 Codex 잔여량이 표시된 Mac](docs/screenshots/promo-at-a-glance.jpg)

**대시보드에서 날짜별·모델별 내역까지.**

![일별 추이, 토큰 내역, 모델별 사용량을 보여 주는 Token Meter 대시보드](docs/screenshots/promo-dashboard.jpg)

**English / 日本語 / 中文 / 한국어를 지원합니다.**

![영어, 일본어, 중국어, 한국어를 선택할 수 있는 Token Meter 설정 화면](docs/screenshots/promo-languages.jpg)

macOS 버전은 Swift / SwiftUI / WidgetKit으로 만들었습니다. WebView도 Electron도 사용하지 않습니다. 토큰 기록은 로컬에서 집계합니다.
사용자가 명시적으로 활성화한 경우에만 Claude Pro / Max 사용량 확인을 위해
Anthropic의 OAuth 사용량 엔드포인트와 통신합니다.

---

## ⚠️ 먼저 읽어 주세요 — 이 앱이 가져올 수 있는 것과 없는 것

실제 로그를 조사한 결과입니다(자세한 내용은 [docs/data-sources.md](docs/data-sources.md)):

| | Claude Code | Codex | Copilot CLI |
|---|---|---|---|
| 토큰 사용량(입력 / 캐시 / 출력) | ✅ | ✅ | ✅ 세션 종료 시 |
| 추론 토큰 | ❌ 분리되지 않음 | ✅ | ❌ 보고되지 않음 |
| 사용 모델 | ✅ | ✅ | ✅ |
| 기록·일별 집계 | ✅ | ✅ | ✅ |
| **5시간 한도의 토큰 수** | ⚠️ 실측(한도 구간은 추정) | ✅ Codex가 5시간 한도를 보고한 경우에만 | ❌ 한도 개념이 없음 |
| **주간 한도의 토큰 수** | ⚠️ 실측(최근 7일 롤링) | ✅ 실제 주간 한도 | ❌ |
| **사용률(%)** | ✅ OAuth 연동 활성화 시 | ✅ | ❌ 로컬에 없음 |
| **남은 사용 가능량** | ✅ OAuth 연동 활성화 시 | ✅ | ❌ |
| **한도 초기화 시각** | ✅ OAuth 연동 활성화 시(로컬 값은 추정) | ✅ 보고값 | ❌ |
| 컨텍스트 창 크기 | ❌ 가져올 수 없음 | ✅ | ❌ |

**Claude Code는 사용률·잔여량·초기화 시각을 로컬 로그에 기록하지 않습니다.**
`claude` CLI에 `usage` 서브커맨드는 존재하지 않으며(`--help`의 모든 커맨드를 확인),
`/usage`는 대화형 세션 안의 슬래시 커맨드일 뿐입니다. 설정 파일에도 해당 값은 없습니다.

설정에서 Claude OAuth 사용량 확인을 활성화하면, Security 프레임워크로 macOS 키체인의
`Claude Code-credentials`를 읽고 `GET https://api.anthropic.com/api/oauth/usage`를 호출해
5시간·7일 및 선택적인 Sonnet 7일 한도를 가져옵니다. 연동이 꺼져 있거나 가져올 수 없을 때는
추정 비율을 표시하지 않습니다.

### "요금제를 고르면 %를 보여 준다"가 불가능한 이유

Anthropic은 **요금제별 토큰 상한을 공개하지 않습니다.**
한도는 대화 길이·복잡도·사용 모델·effort에 따라 달라진다고 설명되어 있어 고정된 수치가 없습니다.
게다가 (1) Opus는 Sonnet의 몇 배 비용으로 계산되고(배율은 비공개),
(2) 한도는 claude.ai(웹/데스크톱/모바일)와 공유되어 다른 기기에서의 사용도 같은 한도를 소비합니다.

분모가 존재하지 않고 분자(이 Mac의 Claude Code 로그)도 불완전하므로,
로컬 값으로 비율을 계산하지 않습니다. 표시하는 비율은 Anthropic의 사용량 응답에 포함된 값뿐입니다.

### 대신 표시하는 것(모두 실측값)

| | 내용 | 초기화 시각 |
|---|---|---|
| Claude Code · 5시간 한도 | 현재 세션 블록의 토큰 수 | ⚠️ **추정**(아래 참조) |
| Claude Code · 최근 7일 | 7일 롤링 합계 | 없음(주간 기준점을 알 수 없음) |
| Codex · 5시간 / 주간 한도 | 해당 한도 안에서 소비한 토큰 수 | ✅ Codex의 보고값 |
| Copilot CLI · 오늘 / 기록 | 세션 종료 시 확정된 모델별 토큰 수 | 없음(한도를 공개하지 않음) |

Anthropic은 "5시간 세션 한도는 첫 메시지에서 시작해 5시간 지속된다"고 설명합니다.
여기서 Claude Code의 5시간 초기화 시각은 **그 규칙을 로컬 로그에 적용해 재현한 값**이며,
Anthropic이 내보낸 값이 아닙니다. UI에는 항상 *estimated*로 표기되며,
"이 Mac의 Claude 로그만 집계"라는 주석이 붙습니다.

Codex는 `rate_limits`(`used_percent` / `resets_at` / `window_minutes`)를 로그에 기록하므로
사용률·잔여량·초기화 시각을 모두 실제 데이터로 표시할 수 있습니다.
한도의 시작 시각도 `resets_at - window_minutes`로 확정되므로 한도 내 토큰 수도 실측값이 됩니다.

Copilot CLI는 한도를 로컬에 기록하지 않으므로 비율·잔여량·초기화 시각을 모두 표시하지 않습니다.
토큰 수는 `session.shutdown` 이벤트의 모델별 누적값에서 구하므로 **세션을 종료한 시점에 반영됩니다**
(실행 중인 세션은 아직 집계되지 않습니다).

이 표시들은 **설정 > Time windows**에서 개별적으로 끌 수 있습니다.

---

## 지원 환경

| | |
|---|---|
| macOS | 14.0 이상(개발·검증 환경은 macOS 26.5) |
| Xcode | 15 이상(검증 환경은 Xcode 26.2) |
| Swift | 5.9 이상(검증 환경은 6.2.3) |
| 프로젝트 생성 도구 | [XcodeGen](https://github.com/yonaskolb/XcodeGen)(`brew install xcodegen`) |

`Windows/` 아래에는 동결된 구현을 참고용으로 남겨 두었지만, 지원하거나 배포하지 않습니다.
그 안의 과거 빌드, 서명 및 설치 문서는 릴리스 안내로 취급하지 마세요.

## 빌드

```bash
# 1. Xcode 프로젝트 생성(project.yml에서)
xcodegen generate

# 2. 빌드
open TokenMeter.xcodeproj    # Xcode에서 ⌘R

# 또는 커맨드라인으로
xcodebuild -project TokenMeter.xcodeproj -scheme TokenMeter \
  -configuration Debug -destination 'platform=macOS' build
```

### 서명에 대하여(위젯을 사용하려면 필수)

`project.yml`에 Developer Team `B97M43J5TT`와 자동 서명을 설정해 두었습니다.
두 타깃 모두 App Group `group.com.tokenmeter.b97m43j5tt.shared`를 사용합니다.

첫 빌드에서는 Xcode에 Apple 계정을 추가한 뒤 프로비저닝 프로파일 생성을 허용하세요:

```bash
xcodebuild -project TokenMeter.xcodeproj -scheme TokenMeter \
  -configuration Debug -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

서명을 끈 로컬 빌드에서는 App Group을 사용할 수 없어 앱 본체만 로컬 디렉터리로 폴백합니다.
현재 상태는 **설정 > Diagnostics**의 `App Group: Active` / `Unavailable`에서 확인할 수 있습니다.

### Developer ID 배포

Release Archive, Developer ID 서명, 공증, 배포용 ZIP 생성을 스크립트로 만들어 두었습니다.

```bash
# 테스트, Archive, Developer ID 서명, Notary Service 업로드
./scripts/release.sh prepare

# Apple의 공증 승인 후, 티켓이 첨부된 앱과 ZIP을 내보내기
./scripts/release.sh finish
```

출력은 `build/TokenMeter-<version>.zip`입니다. ZIP을 풀고 `TokenMeter.app`을 `/Applications`로
옮기세요. DMG로 배포하는 경우, 앱뿐 아니라 최종 DMG 컨테이너에도 Developer ID 서명과 공증을
수행해야 합니다. 개인정보 처리방침은 [docs/privacy.md](docs/privacy.md)를 참조하세요.

### 앱 내 업데이트

Sparkle 2를 사용해 실행 중에 업데이트를 자동으로 확인합니다. 업데이트가 있으면 표준 업데이트
창에서 릴리스 노트를 확인하고, 서명된 ZIP을 내려받아 앱을 교체할 수 있습니다.
Settings > Updates 또는 앱 메뉴의 `Check for Updates…`에서 수동 확인도 가능합니다.

업데이트 피드는 저장소 루트의 `appcast.xml`, 배포용 ZIP은 GitHub Releases에 둡니다.
`./scripts/release.sh finish`는 키체인의 Sparkle EdDSA 키(account: `com.tokenmeter.app`)로
ZIP에 서명하고 `appcast.xml`을 갱신합니다. 비밀 키는 저장소에 보관하지 않습니다.

릴리스마다 `MARKETING_VERSION`과 Sparkle이 비교에 사용하는 `CURRENT_PROJECT_VERSION`을 올린 뒤
실행하세요. 완료 후에는 다음 두 가지를 수행합니다:

1. `v<version>` 태그의 GitHub Release에 `build/TokenMeter-<version>.zip` 업로드
2. 갱신된 `appcast.xml`을 main 브랜치에 커밋·푸시

## 테스트

파서와 스토어 테스트는 Swift Package 쪽에 있습니다.

```bash
swift test --package-path TokenMeterCore
# 111 tests, 0 failures
```

커버하는 내용:

- Claude Code / Codex / Copilot CLI 파서(실제 로그로 만든 익명화 fixture 사용)
- **시간 한도**(5시간 블록의 구분, 만료된 한도는 표시하지 않음, 보고된 한도의 시작 시각 산출,
  롤링 한도에 초기화 시각을 붙이지 않음, 추정/보고 구분이 위젯 JSON을 거쳐도 사라지지 않음)
- **중복 제거**(Claude Code의 동일 메시지 중복, Codex의 동일 값 이벤트)
- **누적 토큰의 차분 계산**(세션 재개 시 이중 집계 방지, 카운터 초기화)
- **Claude OAuth 사용량 조회**(키체인 JSON의 형태 변화, 만료된 토큰, 401/403/429/500·
  네트워크 단절·API 형식 변경의 분류, 메모리 캐시와 동시 요청의 병합,
  위젯 JSON에 자격 증명이 실리지 않음)
- **한도 초기화 감지**(5시간 한도의 롤오버를 주간으로 오인하지 않음, 소비나 최초 관측을
  초기화로 간주하지 않음)
- 불완전한 JSON / 알 수 없는 필드 / 빈 파일 / 손상된 JSONL
- 날짜 변경·시간대 처리(UTC 로그 → 로컬 날짜)
- 위젯용 JSON의 읽기·쓰기(동시 쓰기, 손상된 파일)
- 데이터 소스 미검출 시, 증분 읽기

fixture는 실제 데이터에서 생성했지만 **프롬프트 본문·응답 본문·자격 증명·개인정보는 완전히
제거**되어 있습니다(`TokenMeterCore/Tests/TokenMeterCoreTests/Fixtures/`).

Windows 버전의 테스트는 `Windows/` 아래 .NET 쪽에 있으며, 이 익명화 fixture를 공유합니다.
실행 방법은 [Windows/README.md](Windows/README.md)를 참조하세요.

## 초기 설정

첫 실행 시 설정 화면이 열립니다(메뉴 막대의 Token Meter → Dashboard → Setup에서 언제든 열 수 있습니다).

- 각 제공자의 연결 상태와, 연결되지 않았을 때의 구체적인 조치(커맨드는 복사 가능)
- 메뉴 막대에 표시할지 여부, 표시 형식, 표시 항목
- 무엇을 읽고 있는지에 대한 명시

### Claude Code 연결

**설정이 필요 없습니다.** Claude Code를 한 번이라도 사용했다면 자동으로 감지됩니다.

- 읽는 위치: `~/.claude/projects/<프로젝트>/<세션 ID>.jsonl`
- `claude` CLI가 PATH에 없어도 동작합니다(로그 파일만 읽기 때문)
- 아무것도 표시되지 않으면 Claude Code에서 세션을 한 번 실행하세요

### Codex 연결

- 읽는 위치: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- 미설치라면: `brew install --cask codex`
- 미로그인이라면: `codex login`
- 로그인 후 Codex를 한 번 실행하면 로그가 기록되어 사용률이 표시됩니다

**자격 증명 파일(`~/.codex/auth.json`)은 열지 않습니다.** 로그인 판단은 파일 존재 확인만 합니다.

### Copilot CLI 연결

- 읽는 위치: `~/.copilot/session-state/<세션 ID>/events.jsonl`
- 미설치라면: `npm install -g @github/copilot`
- `copilot` CLI가 PATH에 없어도 동작합니다(세션 로그만 읽기 때문)
- 토큰 수는 `session.shutdown`에 기록되므로 **세션을 한 번 종료**하면 표시됩니다
- Copilot은 한도를 로컬에 공개하지 않으므로 사용률·잔여량·초기화 시각을 표시하지 않습니다

### 위젯 추가

1. 앱을 한 번 실행합니다(스냅샷이 기록됩니다)
2. 데스크탑을 오른쪽 클릭 → "위젯 편집"
3. Token Meter를 선택하고 Small / Medium / Large 중에서 고릅니다
4. 위젯을 클릭하면 앱의 대시보드가 열립니다

위젯은 **로그를 직접 읽지 않습니다.** 본체 앱이 App Group에 기록한 JSON 스냅샷만 읽습니다.

| 크기 | 표시 내용 |
|---|---|
| Small | Claude / Codex의 잔여량(또는 토큰 수), 마지막 갱신 시각 |
| Medium | 진행 막대, 다음 5시간 초기화까지의 시간, 오늘의 토큰 |
| Large | 위 항목 + 5시간 한도 / 오늘 / 주간(또는 최근 7일)의 토큰, 간단한 그래프 |

추정 초기화 시각에는 위젯에서도 `est.`가 붙습니다.

## 데이터 저장 위치

| 데이터 | 위치 |
|---|---|
| 기록 DB(SQLite) | `~/Library/Application Support/TokenMeter/history.sqlite` |
| 위젯용 스냅샷 | `~/Library/Group Containers/group.com.tokenmeter.b97m43j5tt.shared/snapshot.json` |
| (App Group 미사용 시) | `~/Library/Application Support/TokenMeter/snapshot.json` |
| 설정 | UserDefaults |

스냅샷은 임시 파일에 쓴 뒤 원자적으로 교체하므로, 쓰는 도중에 손상되지 않습니다.

## 보안 방침

- **인증 토큰을 저장하지 않습니다.** DB에도 UserDefaults에도 기록하지 않습니다
- Claude 연동을 활성화한 경우에만 Security 프레임워크의 `SecItemCopyMatching`으로
  `Claude Code-credentials`를 읽고, 액세스 토큰을 Anthropic의 고정 엔드포인트로만 보냅니다
- **CLI의 자격 증명 파일을 읽거나 복사하지 않습니다.** `~/.codex/auth.json`은 존재 확인만 하고
  내용은 열지 않습니다
- **프롬프트 본문·응답 본문을 저장하지 않습니다.** 파싱 대상은 `usage` / `token_count`에
  해당하는 필드뿐입니다
- 저장하는 것은 **토큰 수·일시·모델명·사용률·초기화 시각**뿐입니다
- Claude OAuth 사용량 조회와 GitHub에 대한 앱 업데이트 확인 외에는 외부 전송을 하지 않습니다.
  애널리틱스·크래시 리포트를 사용하지 않습니다
- 파일 접근은 `~/.claude/projects`, `~/.codex/sessions`, `~/.copilot/session-state`,
  그리고 선택적 연동 시의 키체인 항목뿐입니다
- 로그에 비밀 정보를 출력하지 않습니다
- 위젯은 샌드박스 안에서 동작하며 App Group의 JSON만 읽을 수 있습니다

본체 앱은 App Sandbox를 비활성화했습니다. `~/.claude`, `~/.codex`, `~/.copilot`은 샌드박스
컨테이너 밖에 있고 읽기가 필요하기 때문입니다. 쓰기는 자신의 Application Support와 App Group에만 합니다.

Token Meter 자체는 키체인에 자격 증명을 기록하지 않습니다. Claude Code가 저장한 항목을
사용량 조회 중에만 읽습니다.

### 키체인 / 샌드박스 / 배포상의 제약

- 현재 본체 타깃은 `ENABLE_APP_SANDBOX=NO`이며 키체인 access group을 지정하지 않습니다.
  직접 배포판에서는 일반 Generic Password를 `SecItemCopyMatching`으로 조회할 수 있지만,
  항목의 ACL에 따라 최초 접근 확인이 뜨거나 거부될 수 있습니다.
- 위젯은 샌드박스가 켜져 있지만 키체인에도 네트워크에도 접근하지 않고,
  본체가 자격 증명을 제외하고 기록한 App Group 스냅샷만 읽습니다.
- 샌드박스를 활성화하면 Claude Code와 서명 팀도 키체인 access group도 공유하지 않기 때문에
  Claude Code가 만든 항목을 보통 읽을 수 없습니다. 임의로 샌드박스를 비활성화하는 폴백은 하지 않습니다.
- Mac App Store 버전은 원칙적으로 샌드박스가 필요하고, 현재의 로컬 로그 읽기에도 같은 제약이
  있으므로 이 방식의 Claude 연동을 그대로 제공하는 것은 현실적이지 않습니다. Anthropic이 공식 API,
  공유 access group, 안전한 IPC를 제공하지 않는 한 직접 배포하는 비샌드박스 버전이 실용적인 구성입니다.
- 토큰 수동 입력은 구현하지 않습니다. 샌드박스 버전이 필요하다면 사용자가 명시적으로 실행하는
  서명된 비샌드박스 헬퍼나 Claude Code 쪽의 공식 로컬 연동이 필요하지만, 현시점에서는 채택하지 않았습니다.

## 갱신 시점

| 경로 | 구현 |
|---|---|
| 앱 실행 시 | `applicationDidFinishLaunching` |
| CLI 로그 갱신 시 | FSEvents(3초 디바운스) |
| 일정 간격 | 타이머(기본 5분, 최소 1분) |
| 수동 갱신 | 메뉴 막대 / 대시보드의 새로고침 버튼 |
| macOS 복귀 시 | `NSWorkspace.didWakeNotification` |
| 날짜 변경 시 | `NSCalendarDayChanged` |

갱신은 직렬화되어 동시에 실행되지 않으며 타임아웃이 있습니다.
로그는 **추가된 부분만** 읽으므로(파일 오프셋을 영속화) 두 번째부터는 가볍습니다.
Claude OAuth의 성공 값은 메모리에 5분간 캐시하고, 실패 시에도 이전 값과 그 갱신 시각을 유지합니다.

## 문제 해결

**메뉴 막대에 아무것도 나오지 않음**
→ 먼저 설정 > 메뉴 막대 > "Show Token Meter in the menu bar"를 확인하세요.
이것을 끄면 Dock 아이콘으로 전환됩니다(창을 열 수 없게 되지 않도록).

→ 켜져 있는데도 보이지 않는다면 **메뉴 막대의 공간이 부족해 macOS가 항목을 숨기고 있을**
가능성이 큽니다. 노치가 있는 Mac에서 전면 앱의 메뉴가 많을 때 발생합니다. 실기에서 확인한 동작으로는,
이때 상태 항목 자체는 생성되어 있습니다(`NSStatusBarWindow`가 화면 밖 좌표에 배치됨).
메뉴 막대의 `•••`를 클릭하거나 메뉴 막대 상주 앱을 줄이면 표시됩니다.
표시 형식을 Compact / Icon only로 바꾸면 폭이 줄어 개선되기도 합니다.

**Claude Code의 사용률이 나오지 않음**
→ 설정 > Claude Pro / Max usage에서 OAuth 사용량 확인을 활성화하고, Claude Code에 로그인되어
있는지 확인하세요. 키체인 거부, 401/403, 레이트 리밋, 오프라인, API 형식 변경은 화면에서
구분해 표시합니다. 연동을 꺼도 5시간 한도·최근 7일의 로컬 토큰 수는 표시할 수 있습니다.

**Claude Code의 5시간 초기화 시각이 어긋난 것 같음**
→ 그럴 수 있습니다. 이 시각은 Anthropic이 내보낸 값이 아니라,
"세션은 첫 메시지에서 시작해 5시간 지속된다"는 공개 사양을
**이 Mac의 로그에 적용해 재현한 추정값**입니다(UI에는 *estimated*로 표시).
브라우저의 claude.ai나 다른 기기의 Claude Code에서 한도가 시작되었다면,
이쪽 추정은 실제보다 늦어집니다. 정확한 값은 Claude Code 안의 `/usage`에서 확인할 수 있습니다.

**Codex의 5시간 한도가 표시되지 않음**
→ Codex가 `rate_limits`에 5시간 한도를 항상 포함하지는 않습니다(주간 한도만 있는 세션이 있습니다).
보고가 없을 때는 추측하지 않고 해당 행을 표시하지 않습니다.

**Codex의 사용률이 나오지 않음**
→ `codex login`을 했는지, Codex를 한 번이라도 실행했는지 확인하세요.
Setup 화면에 구체적인 조치가 나옵니다.

**Copilot CLI의 토큰 수가 나오지 않음**
→ 세션을 한 번 **종료**했는지 확인하세요. Copilot은 `session.shutdown` 이벤트에서만 토큰 수를
확정하므로 실행 중인 세션은 반영되지 않습니다. Copilot에 사용률·초기화 시각 행이 없는 것은
사양입니다(로컬 로그에 존재하지 않음).

**위젯에 데이터가 나오지 않음**
→ App Group에는 서명이 필요합니다. 설정 > Diagnostics에서 `App Group: Unavailable`이라면
Xcode에서 개발 팀을 설정하고 다시 빌드하세요.

**숫자가 오래됨**
→ 갱신에서 1시간 이상 지나면 "Data may be outdated"라고 명시합니다.
오래된 데이터를 최신인 것처럼 보이게 하지 않습니다.

**표시가 이상하거나 숫자가 의심스러울 때**
→ 설정 > Diagnostics에 DB 경로, 스냅샷 경로, 각 제공자의 검출 상태,
읽는 경로, 마지막 갱신 시각, 최근 오류가 모두 나옵니다.

## 구성

```
TokenMeterCore/          Swift Package(UI 비의존, 테스트 대상)
  Models/                UsageSnapshot, UsageWindow, UsageEvent, TokenWindowUsage, 가용성·오류
  Parsing/               ClaudeCodeLogParser, CodexLogParser, CopilotLogParser, 증분 JSONL 리더
  Providers/             UsageProvider 프로토콜과 3개 구현 + Claude OAuth 사용량 조회
  Persistence/           UsageStore(SQLite), SharedSnapshotStore(App Group)
  Aggregation/           일별 집계·모델별 집계
  Monitoring/            FSEvents 디렉터리 감시
  Support/               경로 정의, 한도 초기화 감지, 잔여량으로 구하는 경고 레벨
TokenMeterApp/           메뉴 막대·대시보드·설정·알림(영어·일본어·간체 중국어·한국어)
TokenMeterWidget/        Small / Medium / Large
Windows/                 Windows 버전(C# / .NET 10 / WinUI 3, 독립 solution)
docs/data-sources.md     데이터 소스 조사 결과
docs/claude-sign-in.md   Claude Code 로그인·키체인 허용의 수동 절차
docs/release-runbook.md  macOS 릴리스 절차
```

데이터 수집·로그 해석·UI는 분리되어 있습니다. 위젯은 Core의 모델만 공유하고 로그에는 접근하지 않습니다.
Windows 버전은 macOS 버전의 소스에 의존하지 않고 익명화 fixture만 공유합니다.

## 알려진 제한

- Claude 사용량은 비공개 OAuth 엔드포인트와 Claude Code의 자격 증명 형식에 의존하며,
  예고 없이 동작하지 않게 될 수 있습니다
- 키체인 항목의 접근 제어에 따라, 샌드박스를 끈 직접 배포판에서도 사용자 허용이나
  재서명 후 재허용이 필요할 수 있습니다
- Claude Code의 5시간 한도 구간은 **추정**이며, claude.ai나 다른 기기에서의 사용은 보이지 않습니다.
  토큰 수 자체는 실측이지만 "이 Mac의 Claude Code 분"만의 합계입니다
- Codex의 5시간 한도는 Codex가 `rate_limits`에 포함한 세션에서만 표시됩니다
- Copilot CLI는 세션 종료 시에만 토큰 수를 확정하므로 실행 중인 세션은 반영되지 않습니다.
  한도를 로컬에 공개하지 않으므로 사용률·잔여량·초기화 시각도 표시할 수 없습니다
- 위젯이 표시하는 것은 Claude Code와 Codex뿐이며, Copilot CLI는 본체 앱 쪽(메뉴 막대·
  대시보드)에만 표시됩니다
- 첫 실행에서는 모든 로그를 읽으므로 몇 초 걸립니다(실측: 약 4초 / 로그 약 680MB).
  두 번째부터는 증분만 읽습니다
- 메뉴 막대에 공간이 없으면 macOS가 항목을 숨깁니다(위 문제 해결 참조)
- Developer ID 서명·공증을 마친 앱에서 App Group 컨테이너 생성과 스냅샷 쓰기를 확인했습니다.
  위젯의 데스크탑상 최종 렌더링은 다른 Mac에서의 배포 테스트가 필요합니다
- 육안 확인 완료: 메뉴 막대 항목·팝오버·대시보드·Setup 화면(라이트/다크 두 모드).
  다만 시간 한도 행(5시간 한도·주간)은 다크 모드에서만 실기 확인했으며, 라이트 모드는 미확인입니다

## 기여와 신고

| | |
|---|---|
| 풀 리퀘스트 | [CONTRIBUTING.md](CONTRIBUTING.md) |
| 행동 강령 | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| 취약점 신고 | [SECURITY.md](SECURITY.md)(GitHub의 비공개 신고를 사용. 공개 Issue로 올리지 말 것) |

Issue·PR·fixture에 프롬프트 본문, 응답 본문, 자격 증명, 실제 경로 등 개인정보를 포함하지 마세요.

## 라이선스

Apache License 2.0. 전문은 [LICENSE](LICENSE)를 참조하세요.

```
Copyright 2026 Takeru Fujii

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

"Token Meter"는 Takeru Fujii의 상표이며, Apache License 2.0 제6조에 따라 본 라이선스는
상표 사용을 허락하지 않습니다. 포크와 파생물은 다른 이름을 사용하세요.

바이너리에 동봉한 서드파티 컴포넌트(Sparkle 등)의 저작권 표시와 라이선스는
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)에 있습니다. 재배포 시에는 [NOTICE](NOTICE)를
함께 포함하세요(Apache License 2.0 제4조 (d)).

Token Meter는 Anthropic, OpenAI, GitHub, Microsoft와 제휴하지 않았으며 이들의 승인도 받지 않았습니다.
