# 구현 및 검증 현황

2026-11-04. Tauri 2 + Svelte 5 재구현이다. 기존 Flutter 코드·설정·테스트를 제거했다. 내부 디자인 패키지와 로컬 빌드 결과물은 저장소에 포함하지 않는다.

## 구현

- Hansol 디자인팩의 실제 Svelte Provider, Button, Input, Select, Tabs.
- 대화·오버레이 두 모드, 현재 자막, API 키·모델 설정, 로컬 마이크 테스트.
- Tauri 메뉴바와 독립 투명 자막 창, 창 숨김·복귀.
- 새 Swift 호스트의 입력 장치 선택, PCM 변환, 제한된 예약 재생, 시스템 오디오.
- TypeScript Gemini WSS, 제한된 재연결 버퍼, 인터럽트 및 세션 재개.
- 기존 제작 2D Dash 에셋을 `public/dash`로 이전, 세 의상·여덟 동작.

## 검증

- Svelte/TypeScript 검사: 오류 0, 경고 0.
- 통신·세션 자동 테스트: 19개 통과. setup gate, 버퍼 상한, 인터럽트, 재연결·중지, 비밀 정보 없는 오류, 언어 설정, PCM 레벨, 송신 지연 시 상한, 출력 샘플레이트 검증.
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

## 미검증과 제한

- 실제 사용자 키로 Gemini 인증·통역·음성 품질·언어 자동 감지·지연 측정.
- 새로운 앱의 Bluetooth 재연결, 모든 입력 장치 조합, 장시간 캡처.
- 시스템 오디오 및 출력 재생 품질, 스피커 에코·실제 전이중 통역.
- 오버레이 전체 화면·다중 모니터, 접근성 사용자 검토.
- 서명·공증·App Store 배포.
- 내부 디자인 패키지는 UNLICENSED. 로컬 의존성으로 사용하며 공개 배포 권한은 해결되지 않았다.

음성 복제, 무지연 통역, 음소 단위 립싱크를 보장하지 않는다.
