# Openclaw Termux 원클릭 배포 스크립트

<img width="1080" height="1920" alt="image" src="https://github.com/user-attachments/assets/d035b4ee-0aea-41b2-bdc4-7afd30266f17" />


> 🦞 안드로이드 Termux 환경에서 클릭 한 번으로 Openclaw를 배포하여, 모바일 기기에서도 손쉽게 AI 게이트웨이 서비스를 운영할 수 있습니다.

## 📖 목차

- [프로젝트 개요](https://www.google.com/search?q=%23%ED%94%84%EB%A1%9C%EC%A0%9D%ED%8A%B8-%EA%B0%9C%EC%9A%94)
    
- [주요 기능](https://www.google.com/search?q=%23%EC%A3%BC%EC%9A%94-%EA%B8%B0%EB%8A%A5)
    
- [시스템 요구 사항](https://www.google.com/search?q=%23%EC%8B%9C%EC%8A%A4%ED%85%9C-%EC%9A%94%EA%B5%AC-%EC%82%AC%ED%95%AD)
    
- [빠른 시작](https://www.google.com/search?q=%23%EB%B9%A0%EB%A5%B8-%EC%8B%9C%EC%9E%91)
    
- [상세 사용법](https://www.google.com/search?q=%23%EC%83%81%EC%84%B8-%EC%82%AC%EC%9A%A9%EB%B2%95)
    
- [주요 명령어](https://www.google.com/search?q=%23%EC%A3%BC%EC%9A%94-%EB%AA%85%EB%A0%B9%EC%96%B4)
    
- [문제 해결](https://www.google.com/search?q=%23%EB%AC%B8%EC%A0%9C-%ED%95%B4%EA%B2%B0)
    
- [삭제 가이드](https://www.google.com/search?q=%23%EC%82%AD%EC%A0%9C-%EA%B0%80%EC%9D%B4%EB%93%9C)
    
- [자주 묻는 질문(FAQ)](https://www.google.com/search?q=%23faq)
    

---

## 프로젝트 개요

Openclaw는 강력한 AI 게이트웨이 서비스입니다. 본 스크립트는 Android Termux 환경에 최적화되어 다음과 같은 호환성 문제를 자동으로 해결합니다.

- **의존성 자동 설치**: 필요한 모든 패키지를 확인하고 설치합니다.
    
- **안드로이드 패치**: 로그 경로 및 클립보드 호환성 문제를 수정합니다.
    
- **환경 최적화**: NPM 미러 소스 설정 및 터미널 절전 방지(Wake Lock)를 구성합니다.
    
- **백그라운드 실행**: tmux를 사용하여 서비스가 계속 실행되도록 유지합니다.
    

---

## 주요 기능

### 🚀 간편한 배포

단 한 줄의 명령어로 설치가 완료됩니다.

Bash

```
curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh
```

### 🔧 자동화된 설정

- **Node.js 버전 검증**: v22 이상의 최신 환경을 보장합니다.
    
- **미러 가속**: NPM 다운로드 속도를 위해 미러 서버를 자동으로 설정합니다.
    
- **로그 관리**: `$HOME/openclaw-logs` 경로로 로그를 통합 관리합니다.
    

### 💪 고가용성 및 보안

- **서비스 지속성**: tmux 세션을 통해 백그라운드에서 안전하게 실행됩니다.
    
- **보안 인증**: 커스텀 토큰을 통한 접근 제어를 지원합니다.
    
- **관리 명령**: `ocr`(재시작), `oclog`(로그 확인) 등 전용 별칭(Alias)을 제공합니다.
    

---

## 시스템 요구 사항

|**항목**|**권장 사양**|
|---|---|
|**운영 체제**|Android 7.0 이상|
|**Termux**|최신 버전 (F-Droid 설치 권장)|
|**Node.js**|v22.0.0 이상|
|**저장 공간**|500MB 이상의 여유 공간|
|**메모리(RAM)**|2GB 이상 권장|

---

## 빠른 시작

### 1. 설치 방법 (온라인 권장)

Bash

```
curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh
```

### 2. 대화형 설정

설치 중에 다음 정보를 입력하게 됩니다.

- **Gateway 포트**: 기본값 `18789`
    
- **커스텀 토큰**: 보안을 위해 강력한 비밀번호 입력을 권장합니다.
    
- **부팅 시 자동 실행**: `y` 선택 시 기기 시작 시 자동 실행됩니다.
    

---

## 주요 명령어

설치가 완료되면 다음 단축 명령어를 사용할 수 있습니다.

|**명령어**|**기능**|**설명**|
|---|---|---|
|`ocr`|**서비스 재시작**|기존 프로세스를 종료하고 서비스를 다시 시작합니다.|
|`oclog`|**실시간 로그**|tmux 세션에 접속하여 현재 실행 로그를 확인합니다.|
|`ockill`|**서비스 중지**|실행 중인 모든 Openclaw 프로세스를 강제 종료합니다.|

---

## 문제 해결

### Node.js 버전 오류

- **현상**: 버전이 낮다는 메시지가 출력됨
    
- **해결**: `pkg update && pkg install nodejs -y` 명령어로 최신 버전으로 업데이트하세요.
    

### 서비스 접속 불가

- **현상**: `Connection refused` 발생
    
- **해결**: `tmux list-sessions`로 서비스가 살아있는지 확인하고, `ocr` 명령어로 재시작해 보세요.
    

---

## 삭제 가이드

스크립트를 사용하여 모든 설정을 한 번에 제거할 수 있습니다.

Bash

```
bash install-openclaw-termux.sh --uninstall
```

- 설치된 패키지, 로그 폴더, `.bashrc` 설정이 모두 삭제됩니다.
    

---

## FAQ

**Q: 왜 Node.js 22 버전이 필요한가요?**

A: Openclaw의 최신 기능과 네이티브 모듈 호환성을 위해 최신 LTS 환경이 필수적입니다.

**Q: 백그라운드에서 자꾸 종료됩니다.**

A: 안드로이드 설정에서 Termux 앱의 **'배터리 최적화 제외'**를 설정했는지 확인해 주세요.
