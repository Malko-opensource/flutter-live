# Flutter Live 제품 기획서

2026-11-04 갱신. **Tauri + Svelte로 전환하고 Flutter 구현은 제거**한다. Flutter Seoul 행사라는 제품 맥락과 승인된 2D Dash 에셋은 유지한다.

## 확정 경험

지원 언어는 한국어·영어·일본어·중국어 네 가지다. 양쪽 선택 목록에 네 언어를 항상 표시한다. 반대쪽에 선택된 언어를 고르면 두 언어를 교환해 서로 다른 언어쌍을 유지한다.

- **대화 화면**: 두 언어를 설정하고 발화 언어에 따라 반대 언어로 통역한다. 현재 원문·번역과 Dash를 표시한다. 번역 음성은 기본으로 켠다.
- **자막 오버레이**: 원문 언어와 번역 언어를 직접 지정하고 해당 방향을 유지한다. 자동 양방향 전환을 하지 않는다. 발표 화면 위에 독립된 반투명 자막 바를 띄운다. 작은 Dash, 번역문, 원문 순서로 배치한다. 드래그로 이동하며 메인 창을 숨겨도 유지한다. 번역 음성은 기본으로 끈다.
- **대화 기록 없음**: 목록·저장·조회 기능을 만들지 않는다. 현재 발화만 메모리에 표시한다.
- **설정**: API 키·모델, 입력 소스·마이크, 의상, 확성기 감도를 설정한다. 적용·취소를 구분한다. 키는 가리고 앱 실행 중 메모리에만 보관한다.
- **로컬 미리보기**: API 호출이나 녹음 없이 예시 자막·캐릭터 동작을 보여준다. 마이크 테스트는 로컬 입력 크기만 확인한다.
- **모드 전환**: 연결 중·통역 중·일시 정지 상태에서 모드를 바꾸면 기존 연결을 종료한다. 사용자가 언어를 확인하고 통역 시작을 눌러 새 모드의 규칙으로 연결한다.
- **메뉴바**: 메인 창 열기, 통역 중지, 앱 종료. 일시 정지·재개는 메인 창에서 수행한다.

## 표시 설정

Linear 기본 어두운 테마를 사용하며 밝게·어둡게·시스템 설정에 맞추기를 제공한다. 글꼴은 Linear 기본(Inter/Noto Sans KR)·macOS 시스템·명조다. 화면 글자 크기는 90–130%, 자막 크기는 18–48px다. 자막 배경은 별도로 선택한다. 실시간 미리보기, 적용 후 로컬 저장, 취소 시 복귀를 제공한다. API 키·발화는 저장하지 않는다.

## 디자인과 캐릭터

Atlas Design Pack의 실제 Svelte 컴포넌트와 Linear 테마를 사용한다. 기본 어두운 작업면, 밝은 글자, 하나의 라임색 주동작, 작은 컨트롤과 구분선을 적용한다. 자막 오버레이는 어두운 배경으로 발표 내용과 구분한다. [디자인 기준](../DESIGN.md)에 따른다.

현재 2D Dash의 둥근 눈과 몸통, 짧은 날개·다리 비율을 유지한다. 한복·갓·단청 무대복의 세 의상과 Idle·Listen·Speak·Wave·Celebrate·Reconnect·Sing·Megaphone 여덟 동작을 사용한다. 한복·갓에는 선글라스를 쓰지 않고, 단청에는 유지한다. 갓 아래 정수리 깃은 보이지 않는다.

일반 발화는 마이크를 잡은 Sing, 큰 입력은 확성기·파동이 있는 Megaphone이다. 기준은 녹음 신호의 dBFS이며 공간의 실제 소음 데시벨이 아니다. 기본 −18dBFS 이상이 100ms 이어지면 전환하며 무음 450ms 뒤 Listen으로 돌아간다. 설정 범위는 −36~−6dBFS다. 동작 줄이기를 존중한다. Blender 원본을 유지하되 앱에서는 렌더한 12fps 투명 프레임을 재생한다.

## 기술 구성

Svelte가 화면·현재 자막·세션·Gemini WSS를 소유한다. Tauri/Rust가 메뉴바·창·Swift 연결을 담당한다. Swift가 Core Audio 장치 조회, AVAudioEngine 입력·출력, ScreenCaptureKit 시스템 오디오를 담당한다.

- 입력: 16kHz PCM signed16 little endian mono, 20ms/640바이트.
- 출력: 24kHz PCM16 mono. 네이티브 예약량 상한 2초; 넘친 새 청크는 폐기한다.
- 연결: setupComplete 뒤 캡처 시작. Base64 오디오, 원문·출력 transcription, 모든 audio part, interrupted, turnComplete, session resumption, goAway를 처리한다.
- 자막: 서버 텍스트 조각을 현재 발화에 결합한다. 임의의 과거 단어 수정이나 음성 복제를 보장하지 않는다.
- 재연결: 지수 백오프와 jitter, 최대 6회. 최근 입력 최대 2초를 보관하고 복구 후 20ms마다 최대 4청크를 전송한다. 오래된 입력은 폐기하며 누락 가능성을 표시한다.
- 중지·일시 정지·서버 인터럽트: 예약 재생을 비운다. 중지·일시 정지는 연결과 캡처도 종료한다. 재개는 새 연결이다.
- 마이크: 입력 가능한 Core Audio 장치를 UID로 선택한다. 기본 장치와 연결 변경을 관찰한다. Bluetooth 프로필 변경은 네이티브 엔진 변경 알림으로 처리한다.
- 시스템 오디오: macOS13+ ScreenCaptureKit, 자기 앱 오디오 제외. 별도 가상 드라이버를 설치하지 않는다. 입력 동시 믹싱과 개별 출력 장치 선택은 후속 범위다.
- 권한: microphone usage description, audio-input 및 network.client entitlements. 현재 빌드는 App Store 배포 검증본이 아니다.

## 검증과 배포 기준

1. 두 모드·설정·미리보기·캐릭터를 실제 Tauri 앱에서 확인한다.
2. 실제 입력 장치에서 PCM 수신, 중지, 권한 거부, 장치 변경을 확인한다.
3. 사용자 키로 Gemini 인증·언어 전환·자막·음성·인터럽트를 확인한다.
4. 긴 발표, 재연결, 에코, 전체 화면과 다중 모니터를 검증한다.
5. 공개 배포 전 내부 디자인 패키지 라이선스, 앱 서명·공증, 행사장 음향을 확인한다.

현재 결과와 미검증 범위는 [구현 현황](implementation-status.md)에 기록한다.

## 기술 근거

- [Gemini Live API](https://ai.google.dev/api/live)
- [Gemini 오디오 규격](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
- [Gemini 세션 관리](https://ai.google.dev/gemini-api/docs/live-api/session-management)
- [Tauri v2](https://v2.tauri.app/)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
