# 구현 및 검증 현황

2026-11-04. Tauri 2 + Svelte 5 재구현이다. 기존 Flutter 코드·설정·테스트를 제거했다. 내부 디자인 패키지와 로컬 빌드 결과물은 저장소에 포함하지 않는다.

## 구현

- Atlas 디자인팩 Linear 스타일의 실제 Svelte Provider, Button, Input, Select, Tabs.
- 대화·오버레이 두 모드, 현재 자막, API 키 설정, 로컬 마이크 테스트.
- Tauri 메뉴바와 독립 투명 자막 창, 창 숨김·복귀.
- 새 Swift 호스트의 입력 장치 선택, PCM 변환, 제한된 예약 재생, 시스템 오디오.
- TypeScript Gemini WSS, 제한된 재연결 버퍼, 인터럽트 및 세션 재개.
- 기존 제작 2D Dash 에셋을 `public/dash`로 이전, 세 의상·여덟 동작.

## 검증

- Svelte/TypeScript 검사: 오류 0, 경고 0.
- 통신·세션·표시 설정 자동 테스트: 24개 통과. setup gate, 버퍼 상한, 인터럽트, 재연결·중지, 비밀 정보 없는 오류, 언어 설정, PCM 레벨, 송신 지연 시 상한, 출력 샘플레이트 검증.
- Vite 빌드와 Rust/Swift 연결, macOS Debug `.app` 번들 생성 성공.
- 실제 Tauri 앱에서 대화·설정·오버레이 제어 화면과 Dash 미리보기 렌더 확인. 독립 자막 창에 샘플 번역이 표시되고 메인 창 열기 버튼으로 복귀함을 확인.
- 새 네이티브 입력 호스트에서 현재 기본 USB 장치 `USBAudio1.0` 조회 및 PCM 청크 수신 확인. 관찰 당시 신호는 −96dBFS(무음); 실제 발성/음질 검증으로 간주하지 않는다. 테스트 중지 후 대기 상태 확인.

이전 Flutter 검증은 새 앱의 검증으로 이월하지 않는다. `docs/verification/tauri-*.jpg`는 새 Debug 번들의 실제 macOS 창 캡처다.

- 최소 680×600 웹뷰 크기에서 내부 스크롤·고정 하단 버튼을 확인했다.
- 실제 Tauri 앱에서 임시 문자열의 설정 적용·재진입 유지·마스킹을 확인하고 테스트 값을 제거했다.
- 디자인 정적 검사에서 지적 항목 0개.

## 언어 방향 수정 (2026-11-04)

- 지원 언어를 한·영·일·중으로 제한하고 양쪽 목록에 모두 표시한다. 같은 언어 선택 시 교환하며 12개 방향 조합을 테스트한다. 실제 앱에서 원문 목록에 네 언어와 English 선택, English → 한국어 고정 방향 표시를 확인했다. 캡처: `verification/presentation-languages.jpg`.

- 발표용 오버레이는 원문 언어 → 번역 언어를 지정한다. 입력 전사에는 원문 언어 힌트만 보내고 모델에는 고정 목표 언어 지시를 보낸다. 음성 모델이 지원하지 않는 speechConfig.languageCode는 사용하지 않는다.
- 대화 모드는 두 언어 힌트와 발화별 양방향 지시를 사용한다. 서버의 languageCode가 있을 때만 감지 언어를 표시한다.
- interimInputTranscription은 이전 임시 자막을 교체하며 확정 자막과 중복 결합하지 않는다.
- 통역 중 모드 전환은 기존 연결을 중지한다. 화면만 바뀌고 이전 번역 지시가 계속 쓰이는 것을 방지한다.
- 자동 테스트는 요청 설정·메시지 처리·세션 전환의 검증이다. 실제 음성의 언어 전환 정확도 검증은 아니다.
- API 근거: [Live WebSocket 명세](https://ai.google.dev/api/live), [Native audio language behavior](https://ai.google.dev/gemini-api/docs/live-api/capabilities#change-voice-and-language).

## Linear 및 표시 설정 (2026-11-04)

- 디자인팩 `765b3c4`의 Linear 스타일로 교체. 어둡게·밝게·시스템 테마, 세 글꼴, 화면 글자 90–130%, 자막 18–48px, 자막 배경을 선택한다.
- 변경 즉시 미리 보고, 취소하면 원복한다. 적용한 표시 설정만 로컬에 저장한다. API 키와 발화는 저장하지 않는다.
- Stageshow의 정보 위계와 상태 전환 원칙을 적용했다. 선택한 언어로 원문 → 번역 → 완성 자막이 이어지고, 결과를 유지한다. 모션 줄이기 설정도 따른다.
- 브라우저에서 밝은/어두운 화면, 최대 크기, 최소 창 크기, 취소 복구, 적용 후 새로고침 유지 확인. 실제 Debug 앱에서 Linear 화면·설정·독립 자막 렌더 확인. 48px 설정의 재시작 유지와 900×270 자막 창에서 번역 두 줄·원문 표시를 확인하고 기본 표시값으로 복원.
- 세부 근거와 Stageshow 검증 범위: `design-rehearsal.md`. 자동 촬영 게이트 통과를 주장하지 않는다.
- Linear 및 표시 설정 변경은 v0.2.1 배포 대상이다. 기존 v0.2.0에는 포함되지 않는다.

## 모드별 모델 고정 (2026-11-06)

- 모델 입력란과 사용자 설정의 모델 값을 제거했다. WebSocket setup에서 모드별 고정 정책을 사용하며, 재연결에도 같은 정책을 적용한다.
- 현재 두 모드 모두 `gemini-3.8-live`를 사용한다. 대화의 양방향 지시와 발표의 원문 언어 힌트·고정 목표 언어 지시를 유지한다.
- [공식 Live 모델 안내](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live)를 확인했다. [Live Translate](https://ai.google.dev/gemini-api/docs/live-api/live-translate)는 별도 translationConfig와 지시문 없는 연결 규약이므로, 이번 입력 UI 제거 작업에서 통역 엔진까지 교체하지 않았다.
- Svelte 검사 오류·경고 0, 테스트 24개 통과, macOS Debug 빌드 성공. 웹 화면에서 API 키 입력만 남은 설정을 확인했다 (`verification/fixed-model-settings.jpg`). 실제 Gemini 호출은 수행하지 않았다.

## 미검증과 제한

- 실제 사용자 키로 Gemini 인증·통역·음성 품질·언어 자동 감지·지연 측정.
- 새로운 앱의 Bluetooth 재연결, 모든 입력 장치 조합, 장시간 캡처.
- 시스템 오디오 및 출력 재생 품질, 스피커 에코·실제 전이중 통역.
- 오버레이 전체 화면·다중 모니터, 접근성 사용자 검토.
- 서명·공증·App Store 배포.
- 내부 디자인 패키지는 UNLICENSED. 로컬 의존성으로 사용하며 공개 배포 권한은 해결되지 않았다.

음성 복제, 무지연 통역, 음소 단위 립싱크를 보장하지 않는다.
