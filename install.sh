#!/bin/bash
# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================
#
# Usage: curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh [options]
#
# Options:
#   --help, -h        도움말 정보 표시
#   --verbose, -v     상세 출력 활성화 (명령 실행 세부 정보 표시)
#   --dry-run, -d     시뮬레이션 모드 (변경 없이 실행 과정만 시뮬레이션)
#   --uninstall, -u   Openclaw 삭제 및 구성 설정 정리
#   --update, -U      확인 절차 없이 최신 버전으로 강제 업데이트
#
# Examples:
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --verbose
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --dry-run
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --uninstall
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --update
#
# Note: 로컬에서 직접 실행 시: bash install-openclaw-termux.sh [options]
#
# ==========================================

set -e
set -o pipefail

# 명령줄 옵션 분석
VERBOSE=0
DRY_RUN=0
UNINSTALL=0
FORCE_UPDATE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --dry-run|-d)
            DRY_RUN=1
            shift
            ;;
        --uninstall|-u)
            UNINSTALL=1
            shift
            ;;
        --update|-U)
            FORCE_UPDATE=1
            shift
            ;;
        --help|-h)
            echo "용법: $0 [옵션]"
            echo "옵션:"
            echo "  --verbose, -v    상세 출력 활성화"
            echo "  --dry-run, -d    시뮬레이션 실행 (실제 명령 미수행)"
            echo "  --uninstall, -u  Openclaw 및 관련 설정 제거"
            echo "  --update, -U     최신 버전으로 강제 업데이트"
            echo "  --help, -h       이 도움말 표시"
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            echo "--help를 사용하여 도움말을 확인하세요"
            exit 1
            ;;
    esac
done

trap 'echo -e "${RED}오류: 스크립트 실행 실패, 위 출력을 확인하세요${NC}"; exit 1' ERR

# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================

# 함수 정의부

apply_koffi_stub() {
    # Termux 호환성을 위한 koffi stub 적용 (android-arm64)
    # koffi는 Windows VT 입력을 위한 pi-tui에서만 사용되며 Android에서는 실행되지 않음
    log "koffi stub 적용 중"
    echo -e "${YELLOW}[2.5/6] koffi 호환성 수정 사항 적용 중...${NC}"
    
    KOFFI_DIR="$NPM_GLOBAL/lib/node_modules/openclaw/node_modules/koffi"
    
    if [ -d "$KOFFI_DIR" ]; then
        cat > "$KOFFI_DIR/index.js" << 'EOF'
// Koffi stub for android-arm64 — native module not available on this platform.
// koffi is only used by pi-tui for Windows VT input (enableWindowsVTInput),
// which is guarded by process.platform !== "win32" and never executes here.
const handler = {
  get(_, prop) {
    if (prop === '__esModule') return false;
    if (prop === 'default') return proxy;
    if (prop === 'then') return undefined;
    return function() { throw new Error('koffi stub: not available on android-arm64'); };
  }
};
const proxy = new Proxy({}, handler);
module.exports = proxy;
module.exports.default = proxy;
EOF
        log "koffi stub 적용 성공"
        echo -e "${GREEN}✓ koffi stub 적용 성공${NC}"
    else
        log "koffi 디렉토리가 존재하지 않음, stub 적용 건너뜀"
    fi
}

check_deps() {
    # 기초 의존성 확인 및 설치
    log "기초 환경 검사 시작"
    echo -e "${YELLOW}[1/6] 기초 실행 환경 검사 중...${NC}"

    # pkg 업데이트 필요 여부 확인 (하루에 한 번만 실행)
    UPDATE_FLAG="$HOME/.pkg_last_update"
    if [ ! -f "$UPDATE_FLAG" ] || [ $(($(date +%s) - $(stat -c %Y "$UPDATE_FLAG" 2>/dev/null || echo 0))) -gt 86400 ]; then
        log "pkg update 실행"
        echo -e "${YELLOW}패키지 목록 업데이트 중...${NC}"
        run_cmd pkg update -y
        if [ $? -ne 0 ]; then
            log "pkg update 실패"
            echo -e "${RED}오류: pkg 업데이트 실패${NC}"
            exit 1
        fi
        run_cmd touch "$UPDATE_FLAG"
        log "pkg update 완료"
    else
        log "pkg update 건너뜀 (이미 업데이트됨)"
        echo -e "${GREEN}패키지 목록이 최신 상태입니다${NC}"
    fi

    # 필요한 기초 패키지 정의
    DEPS=("nodejs" "git" "openssh" "tmux" "termux-api" "termux-tools" "cmake" "python" "golang" "which")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        cmd=$dep
        if [ "$dep" = "nodejs" ]; then cmd="node"; fi
        if ! command -v $cmd &> /dev/null; then
            MISSING_DEPS+=($dep)
        fi
    done

    log "Node.js 버전: $(node --version 2>/dev/null || echo '알 수 없음')"
    echo -e "${BLUE}Node.js 버전: $(node -v)${NC}"
    echo -e "${BLUE}NPM 버전: $(npm -v)${NC}" 

    # Node.js 버전 확인 (22 이상 필수)
    NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" -lt 22 ]; then
        log "Node.js 버전 검사 실패: $NODE_VERSION"
        echo -e "${RED}오류: Node.js 버전은 22 이상이어야 합니다. 현재 버전: $(node --version 2>/dev/null || echo '알 수 없음')${NC}"
        exit 1
    fi
    
    # 경고: Node.js 25 (비 LTS)인 경우 호환성 문제 안내 및 다운그레이드 옵션 제공
    if [ "$NODE_VERSION" -eq 25 ]; then
        log "경고: Node.js 25(비 LTS 버전) 감지됨"
        echo -e "${YELLOW}⚠️  경고: 현재 Node.js 25(Current 버전)를 사용 중이며, 네이티브 모듈 호환성 문제가 발생할 수 있습니다${NC}"
        echo -e "${YELLOW}    더 나은 안정성을 위해 Node.js 24 LTS 버전으로 다운그레이드하는 것을 권장합니다${NC}"
        echo ""
        read -p "Node.js 24 LTS로 다운그레이드하시겠습니까? (y/n) [기본값: y]: " DOWNGRADE_CHOICE
        DOWNGRADE_CHOICE=${DOWNGRADE_CHOICE:-y}
        
        if [ "$DOWNGRADE_CHOICE" = "y" ] || [ "$DOWNGRADE_CHOICE" = "Y" ]; then
            log "Node.js를 LTS 버전으로 다운그레이드 시작"
            echo -e "${YELLOW}Node.js 24 LTS로 다운그레이드 중...${NC}"
            
            # 현재 버전 삭제
            run_cmd pkg uninstall nodejs -y
            if [ $? -ne 0 ]; then
                log "Node.js 삭제 실패"
                echo -e "${RED}오류: Node.js 삭제 실패${NC}"
                exit 1
            fi
            
            # LTS 버전 설치
            run_cmd pkg install nodejs-lts -y
            if [ $? -ne 0 ]; then
                log "Node.js LTS 설치 실패"
                echo -e "${RED}오류: Node.js LTS 설치 실패${NC}"
                exit 1
            fi
            
            # 버전 정보 갱신
            NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
            echo -e "${GREEN}✅ Node.js가 $(node --version) 버전으로 다운그레이드되었습니다.${NC}"
            log "Node.js 다운그레이드 완료: $(node --version)"
        else
            log "사용자가 Node.js 25 계속 사용을 선택함"
            echo -e "${YELLOW}설치를 계속 진행하지만 호환성 문제가 발생할 수 있습니다.${NC}"
            read -p "계속하시겠습니까? (y/n) [기본값: n]: " CONTINUE_INSTALL
            CONTINUE_INSTALL=${CONTINUE_INSTALL:-n}
            if [ "$CONTINUE_INSTALL" != "y" ] && [ "$CONTINUE_INSTALL" != "Y" ]; then
                log "사용자가 설치 취소를 선택함"
                echo -e "${YELLOW}설치가 취소되었습니다.${NC}"
                exit 0
            fi
        fi
    fi
    
    log "Node.js 버전 확인 통과: $NODE_VERSION"

    touch "$BASHRC" 2>/dev/null

    log "NPM 미러 서버 설정"
    npm config set registry https://registry.npmmirror.com
    if [ $? -ne 0 ]; then
        log "NPM 미러 설정 실패"
        echo -e "${RED}오류: NPM 미러 설정 실패${NC}"
        exit 1
    fi

    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        log "누락된 의존성: ${MISSING_DEPS[*]}"
        echo -e "${YELLOW}누락된 구성 요소 확인 중: ${MISSING_DEPS[*]}${NC}"
        run_cmd pkg upgrade -y
        if [ $? -ne 0 ]; then
            log "pkg upgrade 실패"
            echo -e "${RED}오류: pkg 업그레이드 실패${NC}"
            exit 1
        fi
        run_cmd pkg install ${MISSING_DEPS[*]} -y
        if [ $? -ne 0 ]; then
            log "의존성 설치 실패"
            echo -e "${RED}오류: 의존성 설치 실패${NC}"
            exit 1
        fi
        log "의존성 설치 완료"
    else
        log "모든 의존성이 설치됨"
        echo -e "${GREEN}✅ 기초 환경 준비 완료${NC}"
    fi
}

configure_npm() {
    # NPM 환경 설정 및 Openclaw 설치
    log "NPM 설정 시작"
    echo -e "\n${YELLOW}[2/6] Openclaw 설정 중...${NC}"

    # NPM 전역 경로 설정
    mkdir -p "$NPM_GLOBAL"
    npm config set prefix "$NPM_GLOBAL"
    if [ $? -ne 0 ]; then
        log "NPM prefix 설정 실패"
        echo -e "${RED}오류: NPM prefix 설정 실패${NC}"
        exit 1
    fi
    grep -qxF "export PATH=$NPM_BIN:$PATH" "$BASHRC" || echo "export PATH=$NPM_BIN:$PATH" >> "$BASHRC"
    export PATH="$NPM_BIN:$PATH"

    # 설치 전 필수 디렉토리 생성 (Termux 호환성 처리)
    log "Termux 호환용 디렉토리 생성"
    mkdir -p "$LOG_DIR" "$HOME/tmp"
    if [ $? -ne 0 ]; then
        log "디렉토리 생성 실패"
        echo -e "${RED}오류: 디렉토리 생성 실패${NC}"
        exit 1
    fi

    # Openclaw 설치/업데이트 확인
    INSTALLED_VERSION=""
    LATEST_VERSION=""
    NEED_UPDATE=0

    log "Openclaw 설치 상태 확인"
    if [ -f "$NPM_BIN/openclaw" ]; then
        log "Openclaw가 이미 설치됨, 버전 확인 중"
        echo -e "${BLUE}Openclaw 버전 확인 중...${NC}"
        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
        if [ -z "$INSTALLED_VERSION" ]; then
            log "버전 추출 실패, 대체 방법 시도"
            INSTALLED_VERSION=$(npm view openclaw version 2>/dev/null || echo "unknown")
        fi
        echo -e "${BLUE}현재 버전: $INSTALLED_VERSION${NC}"

        # 최신 버전 확인
        log "최신 버전 정보 가져오는 중"
        echo -e "${BLUE}npm에서 최신 버전 정보 확인 중...${NC}"
        LATEST_VERSION=$(npm view openclaw version 2>/dev/null || echo "")

        if [ -z "$LATEST_VERSION" ]; then
            log "최신 버전 정보 획득 실패"
            echo -e "${YELLOW}⚠️  최신 버전 정보를 가져올 수 없습니다(네트워크 문제 가능성), 현재 버전을 유지합니다.${NC}"
        else
            echo -e "${BLUE}최신 버전: $LATEST_VERSION${NC}"

            # 버전 비교
            if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
                log "새 버전 발견: $LATEST_VERSION (현재: $INSTALLED_VERSION)"
                echo -e "${YELLOW}🔔 새 버전 발견: $LATEST_VERSION (현재: $INSTALLED_VERSION)${NC}"

                if [ $FORCE_UPDATE -eq 1 ]; then
                    log "강제 업데이트 모드, 업데이트 진행"
                    echo -e "${YELLOW}Openclaw 업데이트 중...${NC}"
                    run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw --ignore-scripts
                    if [ $? -ne 0 ]; then
                        log "Openclaw 업데이트 실패"
                        echo -e "${RED}오류: Openclaw 업데이트 실패${NC}"
                        exit 1
                    fi
                    log "Openclaw 업데이트 완료"
                    echo -e "${GREEN}✅ Openclaw가 $LATEST_VERSION 버전으로 업데이트되었습니다.${NC}"
                    # koffi stub 재적용
                    apply_koffi_stub
                else
                    read -p "새 버전으로 업데이트하시겠습니까? (y/n) [기본값: y]: " UPDATE_CHOICE
                    UPDATE_CHOICE=${UPDATE_CHOICE:-y}

                    if [ "$UPDATE_CHOICE" = "y" ] || [ "$UPDATE_CHOICE" = "Y" ]; then
                        log "Openclaw 업데이트 시작"
                        echo -e "${YELLOW}Openclaw 업데이트 중...${NC}"
                        run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw --ignore-scripts
                        if [ $? -ne 0 ]; then
                            log "Openclaw 업데이트 실패"
                            echo -e "${RED}오류: Openclaw 업데이트 실패${NC}"
                            exit 1
                        fi
                        log "Openclaw 업데이트 완료"
                        echo -e "${GREEN}✅ Openclaw가 $LATEST_VERSION 버전으로 업데이트되었습니다.${NC}"
                        # koffi stub 재적용
                        apply_koffi_stub
                    else
                        log "사용자가 업데이트 건너뜀"
                        echo -e "${YELLOW}업데이트를 건너뛰고 현재 버전을 유지합니다.${NC}"
                    fi
                fi
            else
                log "최신 버전 사용 중"
                echo -e "${GREEN}✅ Openclaw가 이미 최신 버전입니다. ($INSTALLED_VERSION)${NC}"
            fi
        fi
    else
        log "Openclaw 설치 시작"
        echo -e "${YELLOW}Openclaw 설치 중...${NC}"
        # Openclaw 설치 (--ignore-scripts를 사용하여 네이티브 모듈 컴파일 건너뜀)
        # 환경변수를 설정하여 node-llama-cpp 다운로드/컴파일 건너뜀 (Termux 미지원)
        run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw --ignore-scripts
        if [ $? -ne 0 ]; then
            log "Openclaw 설치 실패"
            echo -e "${RED}오류: Openclaw 설치 실패${NC}"
            exit 1
        fi
        log "Openclaw 설치 완료"
        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
        if [ -z "$INSTALLED_VERSION" ]; then
            INSTALLED_VERSION=$(npm view openclaw version 2>/dev/null || echo "unknown")
        fi
        echo -e "${GREEN}✅ Openclaw 설치 완료 (버전: $INSTALLED_VERSION)${NC}"
    fi

    BASE_DIR="$NPM_GLOBAL/lib/node_modules/openclaw"
    
    # koffi stub 적용 (Termux 호환성 수정)
    apply_koffi_stub
}

apply_patches() {
    # Android 호환성 패치 적용
    log "패치 적용 시작"
    echo -e "${YELLOW}[3/6] Android 호환성 패치 적용 중...${NC}"

    # 하드코딩된 /tmp/openclaw 경로가 포함된 모든 파일 수정
    log "하드코딩된 모든 /tmp/openclaw 경로 검색 및 수정"
    
    # openclaw 디렉토리 내 dist/ 폴더에서 /tmp/openclaw 검색
    cd "$BASE_DIR"
    FILES_WITH_TMP=$(grep -rl "/tmp/openclaw" dist/ 2>/dev/null || true)
    
    if [ -n "$FILES_WITH_TMP" ]; then
        log "수정할 파일 발견"
        for file in $FILES_WITH_TMP; do
            log "파일 수정 중: $file"
            node -e "const fs = require('fs'); const file = '$BASE_DIR/$file'; let c = fs.readFileSync(file, 'utf8'); c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); fs.writeFileSync(file, c);"
        done
        log "모든 파일 수정 완료"
    else
        log "수정할 파일을 찾지 못함"
    fi
    
    # 패치 적용 확인
    REMAINING=$(grep -r "/tmp/openclaw" dist/ 2>/dev/null || true)
    if [ -n "$REMAINING" ]; then
        log "패치 검증 실패, 여전히 /tmp/openclaw가 포함된 파일이 있음"
        echo -e "${RED}경고: 일부 파일에 여전히 /tmp/openclaw 경로가 포함되어 있습니다.${NC}"
        echo -e "${YELLOW}영향을 받는 파일:${NC}"
        echo "$REMAINING"
    else
        log "패치 검증 성공, 모든 경로 교체됨"
        echo -e "${GREEN}✓ 모든 /tmp/openclaw 경로가 $HOME/openclaw-logs 로 교체되었습니다.${NC}"
    fi

    # 클립보드 기능 수정
    CLIP_FILE="$BASE_DIR/node_modules/@mariozechner/clipboard/index.js"
    if [ -f "$CLIP_FILE" ]; then
        log "클립보드 패치 적용"
        node -e "const fs = require('fs'); const file = '$CLIP_FILE'; const mock = 'module.exports = { availableFormats:()=>[], getText:()=>\"\", setText:()=>false, hasText:()=>false, getImageBinary:()=>null, getImageBase64:()=>null, setImageBinary:()=>false, setImageBase64:()=>false, hasImage:()=>false, getHtml:()=>\"\", setHtml:()=>false, hasHtml:()=>false, getRtf:()=>\"\", setRtf:()=>false, hasRtf:()=>false, clear:()=>{}, watch:()=>({stop:()=>{}}), callThreadsafeFunction:()=>{} };'; fs.writeFileSync(file, mock);"
        if [ $? -ne 0 ]; then
            log "클립보드 패치 적용 실패"
            echo -e "${RED}오류: 클립보드 패치 적용 실패${NC}"
            exit 1
        fi
        # 패치 적용 확인
        if ! grep -q "availableFormats" "$CLIP_FILE"; then
            log "클립보드 패치 검증 실패"
            echo -e "${RED}오류: 클립보드 패치가 올바르게 적용되지 않았습니다. 파일 내용을 확인하세요.${NC}"
            exit 1
        fi
        log "클립보드 패치 적용 성공"
    fi
}

setup_autostart() {
    # 별칭(alias) 및 자동 실행 옵션 설정
    log "환경 변수 및 별칭 설정 중"
    # 기존 ~/.bashrc 백업
    run_cmd cp "$BASHRC" "$BASHRC.backup"
    # 기존 설정 블록 제거
    run_cmd sed -i '/# --- [Oo]pen[Cc]law Start ---/,/# --- [Oo]pen[Cc]law End ---/d' "$BASHRC"
    if [ $? -ne 0 ]; then
        log "bashrc 수정 실패"
        echo -e "${RED}오류: bashrc 수정 실패${NC}"
        exit 1
    fi

    # 자동 실행 블록 구성
    AUTOSTART_BLOCK=""
    if [ "$AUTO_START" == "y" ]; then
        log "자동 실행 구성 중"
        AUTOSTART_BLOCK="sshd 2>/dev/null
termux-wake-lock 2>/dev/null"
    else
        log "자동 실행 건너뜀 (별칭 및 환경 변수만 작성)"
    fi

    # 설정 블록 쓰기
    cat >> "$BASHRC" <<EOT
# --- OpenClaw Start ---
# WARNING: 이 섹션에는 액세스 토큰이 포함되어 있으므로 ~/.bashrc 보안을 유지하세요.
export TERMUX_VERSION=1
export TMPDIR=\$HOME/tmp
export OPENCLAW_GATEWAY_TOKEN=$TOKEN
export PATH=$NPM_BIN:\$PATH
${AUTOSTART_BLOCK}
alias ocr="pkill -9 -f 'openclaw' 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null; sleep 1; tmux new -d -s openclaw; sleep 1; tmux send-keys -t openclaw \"export PATH=$NPM_BIN:\$PATH TMPDIR=\$HOME/tmp; export OPENCLAW_GATEWAY_TOKEN=$TOKEN; openclaw gateway --bind lan --port $PORT --token \\\$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured\" C-m"
alias oclog='tmux attach -t openclaw'
alias ockill='pkill -9 -f "openclaw" 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null'
# --- OpenClaw End ---
EOT

    source "$BASHRC"
    if [ $? -ne 0 ]; then
        log "bashrc 로드 경고"
        echo -e "${YELLOW}경고: bashrc 로드 실패, 별칭 적용에 영향을 줄 수 있습니다.${NC}"
    fi
    log "별칭 및 환경 변수 구성 완료"
}

activate_wakelock() {
    # 절전 모드 방지를 위한 Wake lock 활성화
    log "Wake lock 활성화"
    echo -e "${YELLOW}[4/6] Wake lock 활성화 중...${NC}"
    termux-wake-lock 2>/dev/null
    if [ $? -eq 0 ]; then
        log "Wake lock 활성화 성공"
        echo -e "${GREEN}✅ Wake-lock 활성화됨${NC}"
    else
        log "Wake lock 활성화 실패"
        echo -e "${YELLOW}⚠️  Wake-lock 활성화 실패, termux-api가 제대로 설치되지 않았을 수 있습니다.${NC}"
    fi
}

start_service() {
    log "서비스 시작"
    echo -e "${YELLOW}[5/6] 서비스 시작 중...${NC}"

    # 이미 실행 중인 인스턴스 확인
    RUNNING_PROCESS=$(pgrep -f "openclaw gateway" 2>/dev/null || true)
    HAS_TMUX_SESSION=$(tmux has-session -t openclaw 2>/dev/null && echo "yes" || echo "no")

    if [ -n "$RUNNING_PROCESS" ] || [ "$HAS_TMUX_SESSION" = "yes" ]; then
        log "기존 Openclaw 인스턴스 발견"
        echo -e "${YELLOW}⚠️  이미 실행 중인 Openclaw 인스턴스가 감지되었습니다.${NC}"
        echo -e "${BLUE}실행 중인 프로세스: $RUNNING_PROCESS${NC}"
        read -p "기존 인스턴스를 중지하고 새로 시작하시겠습니까? (y/n) [기본값: y]: " RESTART_CHOICE
        RESTART_CHOICE=${RESTART_CHOICE:-y}

        if [ "$RESTART_CHOICE" = "y" ] || [ "$RESTART_CHOICE" = "Y" ]; then
            log "기존 인스턴스 중지"
            echo -e "${YELLOW}기존 인스턴스 중지 중...${NC}"
            pkill -9 -f "openclaw" 2>/dev/null || true
            tmux kill-session -t openclaw 2>/dev/null || true
            sleep 1
        else
            log "사용자가 재시작하지 않기로 함"
            echo -e "${GREEN}시작을 건너뛰고 현재 인스턴스를 유지합니다.${NC}"
            return 0
        fi
    fi

    # 디렉토리 존재 확인
    mkdir -p "$HOME/tmp"
    export TMPDIR="$HOME/tmp"

    # 세션 생성 및 오류 확인
    tmux new -d -s openclaw
    sleep 1
    
    # 출력을 임시 파일로 리다이렉트하여 tmux 충돌 시 오류 확인 가능하게 함
    tmux send-keys -t openclaw "export PATH=$NPM_BIN:\$PATH TMPDIR=$HOME/tmp; export OPENCLAW_GATEWAY_TOKEN=$TOKEN; openclaw gateway --bind lan --port $PORT --token \\\$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured 2>&1 | tee $LOG_DIR/runtime.log" C-m
    
    log "서비스 시작 명령 전송됨"
    echo -e "${GREEN}[6/6] 배포 명령 전송 완료${NC}"
    
    # 실시간 확인
    sleep 2
    if tmux has-session -t openclaw 2>/dev/null; then
        echo -e "${GREEN}✅ tmux 세션 생성 완료!${NC}"
        echo -e "터미널을 나갔다 다시 들어온 후 ${CYAN}oclog${NC} 명령어로 로그를 확인하세요. 설정은 ${CYAN}openclaw onboard${NC}를 사용하세요."
    else
        echo -e "${RED}❌ 오류: tmux 세션이 시작 직후 종료되었습니다.${NC}"
        echo -e "오류 로그를 확인하세요: ${YELLOW}cat $LOG_DIR/runtime.log${NC}"
    fi
}

uninstall_openclaw() {
    # Openclaw 삭제 및 설정 정리
    log "Openclaw 삭제 시작"
    echo -e "${YELLOW}Openclaw 삭제 중...${NC}"

    # 서비스 중지
    echo -e "${YELLOW}서비스 중지 중...${NC}"
    run_cmd pkill -9 node 2>/dev/null || true
    run_cmd tmux kill-session -t openclaw 2>/dev/null || true
    log "서비스 중지됨"

    # 별칭 및 설정 삭제
    echo -e "${YELLOW}별칭 및 설정 삭제 중...${NC}"
    run_cmd sed -i '/# --- [Oo]pen[Cc]law Start ---/,/# --- [Oo]pen[Cc]law End ---/d' "$BASHRC"
    run_cmd sed -i '/export PATH=.*\.npm-global\/bin/d' "$BASHRC"
    log "별칭 및 설정 삭제됨"

    # 백업된 bashrc 복구
    if [ -f "$BASHRC.backup" ]; then
        echo -e "${YELLOW}원본 ~/.bashrc 복구 중...${NC}"
        run_cmd cp "$BASHRC.backup" "$BASHRC"
        run_cmd rm "$BASHRC.backup"
        log "bashrc 복구됨"
    fi

    # npm 패키지 삭제
    echo -e "${YELLOW}Openclaw 패키지 삭제 중...${NC}"
    run_cmd npm uninstall -g openclaw 2>/dev/null || true
    log "Openclaw 패키지 삭제됨"

    # 로그 및 설정 디렉토리 삭제
    echo -e "${YELLOW}로그 및 설정 디렉토리 삭제 중...${NC}"
    run_cmd rm -rf "$LOG_DIR" 2>/dev/null || true
    run_cmd rm -rf "$NPM_GLOBAL" 2>/dev/null || true
    log "디렉토리 삭제됨"

    # 업데이트 플래그 파일 삭제
    run_cmd rm -f "$HOME/.pkg_last_update" 2>/dev/null || true

    echo -e "${GREEN}삭제 완료!${NC}"
    log "삭제 완료"
}

# 메인 스크립트

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 터미널 색상 지원 확인
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    : # 지원됨
else
    GREEN=''
    BLUE=''
    YELLOW=''
    RED=''
    NC=''
fi

# 경로 변수 정의
BASHRC="$HOME/.bashrc"
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
LOG_DIR="$HOME/openclaw-logs"
LOG_FILE="$LOG_DIR/install.log"

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR" 2>/dev/null || true

# 로그 기록 함수
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# 명령 실행 함수 (dry-run 지원)
run_cmd() {
    if [ $VERBOSE -eq 1 ]; then
        echo "[VERBOSE] 실행: $@"
    fi
    log "명령 실행: $@"
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY-RUN] 건너뜀: $@"
        return 0
    else
        "$@"
    fi
}

clear
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}🔍 시뮬레이션 모드: 실제 명령을 실행하지 않습니다.${NC}"
fi
if [ $VERBOSE -eq 1 ]; then
    echo -e "${BLUE}상세 출력 모드 활성화됨${NC}"
fi
echo -e "${BLUE}=========================================="
echo -e "    🦞 Openclaw Termux 배포 도구"
echo -e "==========================================${NC}"

# --- 대화형 설정 ---
read -p "Gateway 포트 번호를 입력하세요 [기본값: 18789]: " INPUT_PORT
if [ -z "$INPUT_PORT" ]; then
    echo -e "${GREEN}✓ 기본 포트 사용: 18789${NC}"
    PORT=18789
else
    # 포트 번호 유효성 검사
    if ! [[ "$INPUT_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}오류: 포트 번호는 숫자여야 합니다. 기본값 18789를 사용합니다.${NC}"
        PORT=18789
    else
        PORT=$INPUT_PORT
        echo -e "${GREEN}✓ 사용 포트: $PORT${NC}"
    fi
fi

read -p "사용자 정의 Token을 입력하세요 (보안을 위해 강력한 암호 권장) [비워두면 무작위 생성]: " TOKEN
if [ -z "$TOKEN" ]; then
    # 무작위 Token 생성
    RANDOM_PART=$(date +%s | md5sum | cut -c 1-8)
    TOKEN="token$RANDOM_PART"
    echo -e "${GREEN}생성된 무작위 Token: $TOKEN${NC}"
fi

read -p "부팅 시 자동 실행을 활성화하시겠습니까? (y/n) [기본값: y]: " AUTO_START
AUTO_START=${AUTO_START:-y}

# 단계별 실행
if [ $UNINSTALL -eq 1 ]; then
    uninstall_openclaw
    exit 0
fi

log "스크립트 실행 시작, 설정: 포트=$PORT, Token=$TOKEN, 자동실행=$AUTO_START"
check_deps
configure_npm
apply_patches
setup_autostart
activate_wakelock
start_service
echo -e "${GREEN}스크립트 실행 완료!${NC} Token은 ${YELLOW}$TOKEN${NC} 입니다. \n자주 쓰는 명령어: 로그 확인(${CYAN}oclog${NC}), 서비스 중지(${CYAN}ockill${NC}), 서비스 재시작(${CYAN}ocr${NC})"
log "스크립트 실행 완료"
