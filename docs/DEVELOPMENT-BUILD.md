# iPad 개발용 빌드

## 빌드 방식

사용자가 Apple Developer 유료 멤버십 없이 GitHub 빌드와 Sideloadly 경로를 선택했다. 비공개 저장소 `a44383238-lab/inkdrive-ipad`의 `iPad development IPA` 작업을 수동 실행한다. Mac에서 Expo iOS 프로젝트를 생성하고 Debug 구성, 실제 iOS 기기용 arm64, expo-dev-client 포함으로 컴파일한다. Apple 서명 없이 IPA를 패키징하며 배포용 App Store 빌드가 아니다.

`iOS PDF and storage tests` 작업은 별도로 iPad 시뮬레이터에서 PDF·저장·저장 중 편집 등의 Swift 테스트를 실행한다. 성공 여부는 각 작업의 실제 종료 결과로 판단한다.

## 설치

1. iPad를 USB로 노트북에 연결하고 잠금을 푼다. 기기에서 이 컴퓨터 신뢰를 허용한다.
2. 기존 Sideloadly에서 iPad를 선택하고 `InkDrive-development-unsigned.ipa`를 불러온다.
3. Apple ID 로그인과 인증은 Sideloadly에서 직접 수행한다. 채팅에 비밀번호나 인증번호를 보내지 않는다.
4. 설치 후 iPad가 요구하는 개발자 신뢰·개발자 모드 절차를 완료한다.
5. 노트북의 InkDrive 작업 폴더에서 `npm start`를 실행하고 같은 네트워크의 개발 서버에 연결한다. 이 빌드는 개발 서버를 사용하는 개발용 클라이언트다.
6. 서재 선택에서 iCloud Drive의 InkDrive 폴더를 선택한다. Windows 경로와 같은 폴더인지 확인한다.

일반 무료 Apple ID로 서명한 앱은 7일 후 재서명이 필요하다. Sideloadly의 자동 갱신은 노트북과 기기가 연결 가능한 조건에서 동작하며 무조건 영구 유지되는 것은 아니다.

## 수정 반영

JavaScript 화면과 로직 변경은 개발 서버에서 반영할 수 있다. Swift 필기 엔진, 새 네이티브 의존성, iOS 설정 변경은 IPA를 다시 빌드·설치해야 한다. 빌드 성공은 실제 Pencil·녹음·iCloud 기기 간 동기화 검증과 별개다.

참고: https://docs.expo.dev/develop/development-builds/introduction/ · https://sideloadly.io/
