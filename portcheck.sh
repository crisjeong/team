#!/bin/bash
#==============================================================================
# portcheck.sh - Interactive Port Diagnostic Tool for Red Hat Linux
#
# Supports: RHEL 6.x / 7.x / 8.x (CentOS compatible)
# Language: Auto-detect (Korean / English)
#
# Usage:
#   Interactive mode : ./portcheck.sh
#   Direct mode      : ./portcheck.sh local  <port> [tcp|udp]
#                      ./portcheck.sh remote <host> <port> [tcp|udp]
#   Help             : ./portcheck.sh --help
#==============================================================================

set -uo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

#==============================================================================
# Locale detection
#==============================================================================
detect_lang() {
    local lc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    case "$lc" in
        ko_KR*|ko.*|korean*) echo "ko" ;;
        *) echo "en" ;;
    esac
}

SCRIPT_LANG=$(detect_lang)
[ -n "${CHECK_PORT_LANG:-}" ] && SCRIPT_LANG="$CHECK_PORT_LANG"

msg() {
    if [ "$SCRIPT_LANG" = "ko" ]; then echo "$1"; else echo "$2"; fi
}

#==============================================================================
# Color & UI setup
#==============================================================================
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
    BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; BOLD=''; DIM=''; NC=''
fi

print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_ok()   { echo -e "  ${GREEN}[OK]   $1${NC}"; }
print_warn() { echo -e "  ${YELLOW}[WARN] $1${NC}"; }
print_fail() { echo -e "  ${RED}[FAIL] $1${NC}"; }
print_info() { echo -e "  ${CYAN}[INFO] $1${NC}"; }

# Prompt helper: display prompt and read input with default value
prompt_input() {
    local prompt_text="$1"
    local default_val="${2:-}"
    local var_name="$3"

    if [ -n "$default_val" ]; then
        printf "  ${CYAN}>${NC} ${prompt_text} [${GREEN}${default_val}${NC}]: "
    else
        printf "  ${CYAN}>${NC} ${prompt_text}: "
    fi
    read -r input_val
    if [ -z "$input_val" ] && [ -n "$default_val" ]; then
        input_val="$default_val"
    fi
    eval "$var_name=\$input_val"
}

# Yes/No prompt with default
prompt_yn() {
    local prompt_text="$1"
    local default_val="${2:-y}"

    if [ "$default_val" = "y" ]; then
        printf "  ${CYAN}>${NC} ${prompt_text} [${GREEN}Y${NC}/n]: "
    else
        printf "  ${CYAN}>${NC} ${prompt_text} [y/${GREEN}N${NC}]: "
    fi
    read -r yn_val
    case "${yn_val:-$default_val}" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# Clear screen (portable)
clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033[2J\033[H'
    fi
}

#==============================================================================
# RHEL version detection
#==============================================================================
detect_rhel_version() {
    RHEL_MAJOR=0
    if [ -f /etc/redhat-release ]; then
        RHEL_MAJOR=$(sed 's/.*release \([0-9]*\).*/\1/' /etc/redhat-release 2>/dev/null || echo 0)
    elif [ -f /etc/os-release ]; then
        RHEL_MAJOR=$(grep -oE 'VERSION_ID="?[0-9]+' /etc/os-release 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo 0)
    fi
    case "$RHEL_MAJOR" in ''|*[!0-9]*) RHEL_MAJOR=0 ;; esac
}

is_service_active() {
    local svc_name="$1"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active "$svc_name" >/dev/null 2>&1
    else
        service "$svc_name" status >/dev/null 2>&1
    fi
}

detect_rhel_version

#==============================================================================
# Validation helpers
#==============================================================================
validate_port() {
    local port="$1"
    case "$port" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_proto() {
    local proto
    proto=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [ "$proto" = "tcp" ] || [ "$proto" = "udp" ]
}

#==============================================================================
# Help / Usage
#==============================================================================
show_help() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║       portcheck.sh - $(msg '포트 진단 도구' 'Port Diagnostic Tool') v${SCRIPT_VERSION}           ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}$(msg '설명' 'DESCRIPTION')${NC}"
    echo -e "  $(msg 'Red Hat Linux (RHEL 6/7/8) 환경에서 포트의 사용 여부,' 'Check port usage, firewall status, and connectivity')"
    echo -e "  $(msg '방화벽 차단 여부, 원격 접속 가능 여부를 종합 점검합니다.' 'on Red Hat Linux (RHEL 6/7/8) environments.')"
    echo ""
    echo -e "${BOLD}$(msg '사용법' 'USAGE')${NC}"
    echo -e "  ${GREEN}${SCRIPT_NAME}${NC}                                  $(msg '인터랙티브 모드' 'Interactive mode')"
    echo -e "  ${GREEN}${SCRIPT_NAME} local${NC}  <port> [tcp|udp]          $(msg '로컬 포트 점검' 'Local port check')"
    echo -e "  ${GREEN}${SCRIPT_NAME} remote${NC} <host> <port> [tcp|udp]   $(msg '원격 포트 점검' 'Remote port check')"
    echo -e "  ${GREEN}${SCRIPT_NAME} --help${NC}                           $(msg '도움말 표시' 'Show this help')"
    echo -e "  ${GREEN}${SCRIPT_NAME} --version${NC}                        $(msg '버전 표시' 'Show version')"
    echo ""
    echo -e "${BOLD}$(msg '인터랙티브 모드' 'INTERACTIVE MODE')${NC}"
    echo -e "  $(msg '인자 없이 실행하면 메뉴가 표시됩니다:' 'Run without arguments to see the menu:')"
    echo ""
    echo -e "    ${DIM}┌──────────────────────────────────┐${NC}"
    echo -e "    ${DIM}│  1. $(msg '로컬 포트 점검' 'Local port check')              │${NC}"
    echo -e "    ${DIM}│  2. $(msg '원격 포트 접속 점검' 'Remote port connectivity')          │${NC}"
    echo -e "    ${DIM}│  3. $(msg '빠른 다중 포트 스캔' 'Quick multi-port scan')          │${NC}"
    echo -e "    ${DIM}│  h. $(msg '도움말' 'Help')                          │${NC}"
    echo -e "    ${DIM}│  q. $(msg '종료' 'Quit')                            │${NC}"
    echo -e "    ${DIM}└──────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}$(msg '예시' 'EXAMPLES')${NC}"
    echo ""
    echo -e "  ${DIM}# $(msg '인터랙티브 모드' 'Interactive mode')${NC}"
    echo -e "  ${YELLOW}sudo ./${SCRIPT_NAME}${NC}"
    echo ""
    echo -e "  ${DIM}# $(msg '로컬 포트 8080/tcp 점검' 'Check local port 8080/tcp')${NC}"
    echo -e "  ${YELLOW}sudo ./${SCRIPT_NAME} local 8080${NC}"
    echo ""
    echo -e "  ${DIM}# $(msg '원격 서버 443 포트 접속 점검' 'Check remote server port 443')${NC}"
    echo -e "  ${YELLOW}sudo ./${SCRIPT_NAME} remote 192.168.1.100 443${NC}"
    echo ""
    echo -e "  ${DIM}# $(msg 'UDP 프로토콜 지정' 'Specify UDP protocol')${NC}"
    echo -e "  ${YELLOW}sudo ./${SCRIPT_NAME} remote 10.0.0.1 53 udp${NC}"
    echo ""
    echo -e "${BOLD}$(msg '환경변수' 'ENVIRONMENT VARIABLES')${NC}"
    echo ""
    echo -e "  ${GREEN}CHECK_PORT_LANG${NC}=en|ko    $(msg '출력 언어 강제 지정 (기본: 자동 감지)' 'Force output language (default: auto-detect)')"
    echo -e "  ${GREEN}CHECK_PORT_TIMEOUT${NC}=5     $(msg '연결 타임아웃 초 (기본: 5)' 'Connection timeout in seconds (default: 5)')"
    echo ""
    echo -e "${BOLD}$(msg '점검 항목' 'CHECK ITEMS')${NC}"
    echo ""
    echo -e "  ${BOLD}$(msg '[로컬 포트 점검]' '[Local Port Check]')${NC}"
    echo -e "  $(msg '  1. 포트 LISTEN 상태 및 프로세스 확인   (ss/netstat)' '  1. Port LISTEN status & process       (ss/netstat)')"
    echo -e "  $(msg '  2. firewalld 방화벽 인바운드 규칙      (RHEL 7+)' '  2. firewalld inbound rules             (RHEL 7+)')"
    echo -e "  $(msg '  3. iptables INPUT 규칙                (모든 RHEL)' '  3. iptables INPUT rules                (all RHEL)')"
    echo -e "  $(msg '  4. nftables 규칙                      (RHEL 8+)' '  4. nftables rules                      (RHEL 8+)')"
    echo -e "  $(msg '  5. SELinux 포트 정책                   ' '  5. SELinux port policy                  ')"
    echo -e "  $(msg '  6. 로컬 접속 테스트                    ' '  6. Local connectivity test              ')"
    echo ""
    echo -e "  ${BOLD}$(msg '[원격 포트 점검]' '[Remote Port Check]')${NC}"
    echo -e "  $(msg '  1. DNS 이름 해석                       ' '  1. DNS resolution                      ')"
    echo -e "  $(msg '  2. 네트워크 경로 확인                  ' '  2. Network route check                 ')"
    echo -e "  $(msg '  3. ICMP Ping 테스트                    ' '  3. ICMP Ping test                      ')"
    echo -e "  $(msg '  4. TCP/UDP 포트 접속 테스트             ' '  4. TCP/UDP port connectivity test       ')"
    echo -e "  $(msg '  5. 아웃바운드 방화벽 확인              ' '  5. Outbound firewall check             ')"
    echo -e "  $(msg '  6. 경로 추적 (Traceroute)              ' '  6. Traceroute diagnostics              ')"
    echo ""
    echo -e "${BOLD}$(msg '권한' 'PRIVILEGES')${NC}"
    echo -e "  $(msg 'root 권한(sudo)으로 실행하면 모든 항목을 완전히 점검할 수 있습니다.' 'Run with root(sudo) for complete checks on all items.')"
    echo -e "  $(msg '일반 사용자로도 실행 가능하나 일부 항목이 제한됩니다.' 'Regular users can run it but some checks will be limited.')"
    echo ""
}

#==============================================================================
# Banner
#==============================================================================
show_banner() {
    echo -e "${CYAN}"
    echo '  ____            _    ____ _               _    '
    echo ' |  _ \ ___  _ __| |_ / ___| |__   ___  ___| | __'
    echo ' | |_) / _ \| '__| __| |   | '_ \ / _ \/ __| |/ /'
    echo ' |  __/ (_) | |  | |_| |___| | | |  __/ (__|   < '
    echo ' |_|   \___/|_|   \__|\____|_| |_|\___|\___|_|\_\'
    echo -e "${NC}"
    echo -e "  ${DIM}v${SCRIPT_VERSION} | RHEL 6/7/8 | $(msg '한/영 자동 감지' 'Auto i18n') | $(date '+%Y-%m-%d %H:%M')${NC}"
    echo ""
}

#==============================================================================
# ROOT CHECK
#==============================================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo ""
        echo -e "  ${YELLOW}$(msg '⚠ root 권한 없이 실행 중 - 일부 점검 항목이 제한됩니다.' '⚠ Running without root - some checks will be limited.')${NC}"
        echo -e "  ${DIM}$(msg '완전한 점검: sudo' 'Full check: sudo') ./${SCRIPT_NAME}${NC}"
        echo ""
        if [ -t 0 ]; then
            if prompt_yn "$(msg 'sudo로 재실행하시겠습니까?' 'Re-run with sudo?')" "y"; then
                echo ""
                exec sudo "$0" "$@"
            fi
        fi
    fi
}

#==============================================================================
# LOCAL PORT CHECK
#==============================================================================
do_local_check() {
    local PORT="$1"
    local PROTO="$2"
    local ISSUES=0

    print_header "$(msg '로컬 포트 점검' 'Local Port Check'): ${PORT}/${PROTO}"
    echo -e "  $(msg '호스트' 'Host'):  $(hostname)"
    if [ "$RHEL_MAJOR" -gt 0 ]; then
        echo -e "  RHEL  :  ${RHEL_MAJOR}.x"
    fi

    # --- 1. Port usage ---
    print_header "1. $(msg '포트 사용 여부' 'Port Usage')"
    local LISTEN_RESULT="" TOOL_USED="none"
    if command -v ss >/dev/null 2>&1; then
        if [ "$PROTO" = "tcp" ]; then
            LISTEN_RESULT=$(ss -tlnp 2>/dev/null | grep ":${PORT} " || true)
        else
            LISTEN_RESULT=$(ss -ulnp 2>/dev/null | grep ":${PORT} " || true)
        fi
        TOOL_USED="ss"
    elif command -v netstat >/dev/null 2>&1; then
        if [ "$PROTO" = "tcp" ]; then
            LISTEN_RESULT=$(netstat -tlnp 2>/dev/null | grep ":${PORT} " || true)
        else
            LISTEN_RESULT=$(netstat -ulnp 2>/dev/null | grep ":${PORT} " || true)
        fi
        TOOL_USED="netstat"
    else
        print_warn "$(msg 'ss/netstat 을 찾을 수 없습니다.' 'ss/netstat not found.')"
    fi

    if [ -n "$LISTEN_RESULT" ]; then
        print_ok "$(msg "포트 ${PORT}/${PROTO} LISTEN 중" "Port ${PORT}/${PROTO} is LISTENING") (${TOOL_USED})"
        echo "$LISTEN_RESULT" | while IFS= read -r line; do echo "    ${line}"; done
    else
        print_warn "$(msg "포트 ${PORT}/${PROTO} LISTEN 중인 서비스 없음" "No service LISTENING on ${PORT}/${PROTO}")"
        ISSUES=$((ISSUES + 1))
    fi

    # ESTABLISHED
    if command -v ss >/dev/null 2>&1; then
        local EST
        EST=$(ss -tn state established "( sport = :${PORT} or dport = :${PORT} )" 2>/dev/null | tail -n +2 || true)
        if [ -n "$EST" ]; then
            print_info "$(msg "활성 연결: $(echo "$EST" | wc -l)개" "Active connections: $(echo "$EST" | wc -l)")"
        fi
    fi

    # --- 2. firewalld ---
    print_header "2. $(msg 'firewalld 확인' 'firewalld Check')"
    if [ "$RHEL_MAJOR" -ge 7 ] || [ "$RHEL_MAJOR" -eq 0 ]; then
        if command -v firewall-cmd >/dev/null 2>&1 && is_service_active firewalld; then
            print_ok "$(msg 'firewalld 실행 중' 'firewalld is running')"
            local ZONE
            ZONE=$(firewall-cmd --get-active-zones 2>/dev/null | head -1 || echo "public")
            print_info "Zone: ${ZONE}"

            if firewall-cmd --query-port="${PORT}/${PROTO}" --zone="${ZONE}" >/dev/null 2>&1; then
                print_ok "$(msg "포트 ${PORT}/${PROTO} 허용됨" "Port ${PORT}/${PROTO} ALLOWED")"
            else
                local svc_found=false
                for svc in $(firewall-cmd --list-services --zone="${ZONE}" 2>/dev/null || true); do
                    case " $(firewall-cmd --service="${svc}" --get-ports 2>/dev/null) " in
                        *" ${PORT}/${PROTO} "*) svc_found=true; print_ok "$(msg "서비스 '${svc}' 통해 허용" "Allowed via service '${svc}'")" ; break ;;
                    esac
                done
                if [ "$svc_found" = "false" ]; then
                    print_fail "$(msg "포트 ${PORT}/${PROTO} 차단됨!" "Port ${PORT}/${PROTO} BLOCKED!")"
                    echo -e "    ${YELLOW}sudo firewall-cmd --permanent --add-port=${PORT}/${PROTO} && sudo firewall-cmd --reload${NC}"
                    ISSUES=$((ISSUES + 1))
                fi
            fi
        else
            print_info "$(msg 'firewalld 미실행 또는 미설치' 'firewalld not running or not installed')"
        fi
    else
        print_info "$(msg 'RHEL 6 - firewalld 미지원 (iptables 참조)' 'RHEL 6 - no firewalld (see iptables)')"
    fi

    # --- 3. iptables ---
    print_header "3. $(msg 'iptables 확인' 'iptables Check')"
    if command -v iptables >/dev/null 2>&1; then
        if [ "$(id -u)" -eq 0 ]; then
            local IPT_RULES DEFAULT_POL
            IPT_RULES=$(iptables -L INPUT -n --line-numbers 2>/dev/null | grep -i "${PROTO}" | grep "${PORT}" || true)
            if [ -n "$IPT_RULES" ]; then
                print_info "$(msg '관련 규칙:' 'Related rules:')"
                echo "$IPT_RULES" | while IFS= read -r rule; do
                    case "$rule" in
                        *DROP*|*REJECT*) echo -e "    ${RED}${rule}${NC}" ;;
                        *ACCEPT*) echo -e "    ${GREEN}${rule}${NC}" ;;
                        *) echo "    ${rule}" ;;
                    esac
                done
            else
                print_info "$(msg '명시적 규칙 없음' 'No explicit rules')"
            fi
            DEFAULT_POL=$(iptables -L INPUT 2>/dev/null | head -1 | awk '{print $4}' | tr -d ')' || echo "?")
            case "$DEFAULT_POL" in
                DROP|REJECT) print_warn "$(msg "INPUT 기본 정책: ${DEFAULT_POL}" "INPUT default: ${DEFAULT_POL}")"; ISSUES=$((ISSUES + 1)) ;;
                *) print_info "$(msg "INPUT 기본 정책: ${DEFAULT_POL}" "INPUT default: ${DEFAULT_POL}")" ;;
            esac

            if [ "$RHEL_MAJOR" -le 6 ] && [ "$RHEL_MAJOR" -gt 0 ] && [ -f /etc/sysconfig/iptables ]; then
                local SAVED
                SAVED=$(grep "${PORT}" /etc/sysconfig/iptables 2>/dev/null || true)
                [ -n "$SAVED" ] && { print_info "/etc/sysconfig/iptables:"; echo "    ${SAVED}"; }
            fi
        else
            print_warn "$(msg 'root 필요' 'Root required')"
        fi
    else
        print_info "$(msg 'iptables 미설치' 'iptables not found')"
    fi

    # --- 4. nftables ---
    print_header "4. $(msg 'nftables 확인' 'nftables Check')"
    if [ "$RHEL_MAJOR" -ge 8 ] || [ "$RHEL_MAJOR" -eq 0 ]; then
        if command -v nft >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
            local NFT_R
            NFT_R=$(nft list ruleset 2>/dev/null | grep -iE "${PROTO}.*dport.*${PORT}|${PROTO}.*${PORT}" || true)
            if [ -n "$NFT_R" ]; then
                print_info "$(msg '관련 규칙:' 'Related rules:')"
                echo "$NFT_R" | while IFS= read -r rule; do
                    case "$rule" in *drop*|*reject*) echo -e "    ${RED}${rule}${NC}" ;; *accept*) echo -e "    ${GREEN}${rule}${NC}" ;; *) echo "    ${rule}" ;; esac
                done
            else
                print_info "$(msg '명시적 규칙 없음' 'No explicit rules')"
            fi
        else
            print_info "$(msg 'nft 미설치 또는 root 필요' 'nft not found or root required')"
        fi
    else
        print_info "$(msg 'RHEL 8+ 전용' 'RHEL 8+ only')"
    fi

    # --- 5. SELinux ---
    print_header "5. $(msg 'SELinux 확인' 'SELinux Check')"
    if command -v sestatus >/dev/null 2>&1; then
        local SE_STATUS SE_MODE
        SE_STATUS=$(sestatus 2>/dev/null | grep "SELinux status" | awk '{print $3}' || echo "?")
        SE_MODE=$(sestatus 2>/dev/null | grep "Current mode" | awk '{print $3}' || echo "?")
        if [ "$SE_STATUS" = "enabled" ]; then
            print_info "SELinux: ${SE_STATUS} (${SE_MODE})"
            if command -v semanage >/dev/null 2>&1; then
                local SE_PORT
                SE_PORT=$(semanage port -l 2>/dev/null | grep "${PROTO}" | grep -w "${PORT}" || true)
                if [ -n "$SE_PORT" ]; then
                    print_ok "$(msg 'SELinux 정책에 등록됨' 'Registered in SELinux policy')"
                    echo "    ${SE_PORT}"
                elif [ "$SE_MODE" = "enforcing" ]; then
                    print_warn "$(msg 'SELinux 미등록 (enforcing 모드 - 차단 가능)' 'Not in SELinux (enforcing - may block)')"
                    ISSUES=$((ISSUES + 1))
                fi
            else
                print_warn "$(msg 'semanage 미설치' 'semanage not installed')"
            fi
        else
            print_info "$(msg 'SELinux 비활성' 'SELinux disabled')"
        fi
    fi

    # --- 6. Local connectivity test ---
    print_header "6. $(msg '로컬 접속 테스트' 'Local Connectivity Test')"
    if [ "$PROTO" = "tcp" ]; then
        if (echo > /dev/tcp/127.0.0.1/${PORT}) 2>/dev/null; then
            print_ok "127.0.0.1:${PORT} $(msg 'TCP 연결 성공' 'TCP OK')"
        elif command -v nc >/dev/null 2>&1 && nc -z -w 3 127.0.0.1 "${PORT}" 2>/dev/null; then
            print_ok "127.0.0.1:${PORT} $(msg 'TCP 연결 성공' 'TCP OK') (nc)"
        else
            print_warn "127.0.0.1:${PORT} $(msg 'TCP 연결 실패' 'TCP FAILED')"
            ISSUES=$((ISSUES + 1))
        fi
    elif [ "$PROTO" = "udp" ]; then
        if command -v nc >/dev/null 2>&1; then
            nc -zu -w 3 127.0.0.1 "${PORT}" 2>/dev/null && print_ok "UDP $(msg '접근 가능' 'accessible')" || print_warn "UDP $(msg '접근 불가' 'unreachable')"
        fi
    fi

    # --- 7. Version guide ---
    print_header "7. $(msg 'RHEL 방화벽 가이드' 'RHEL Firewall Guide')"
    if [ "$RHEL_MAJOR" -le 6 ] && [ "$RHEL_MAJOR" -gt 0 ]; then
        echo -e "  ${BOLD}[RHEL 6]${NC} iptables"
        echo -e "    ${YELLOW}sudo iptables -I INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT${NC}"
        echo -e "    ${YELLOW}sudo service iptables save && sudo service iptables restart${NC}"
    elif [ "$RHEL_MAJOR" -eq 7 ]; then
        echo -e "  ${BOLD}[RHEL 7]${NC} firewalld"
        echo -e "    ${YELLOW}sudo firewall-cmd --permanent --add-port=${PORT}/${PROTO} && sudo firewall-cmd --reload${NC}"
    elif [ "$RHEL_MAJOR" -ge 8 ]; then
        echo -e "  ${BOLD}[RHEL 8]${NC} firewalld + nftables"
        echo -e "    ${YELLOW}sudo firewall-cmd --permanent --add-port=${PORT}/${PROTO} && sudo firewall-cmd --reload${NC}"
    fi

    # --- Summary ---
    print_header "$(msg '종합 결과' 'Summary')"
    if [ "$ISSUES" -eq 0 ]; then
        print_ok "$(msg "포트 ${PORT}/${PROTO}: 모든 항목 통과" "Port ${PORT}/${PROTO}: All checks PASSED")"
    else
        print_fail "$(msg "포트 ${PORT}/${PROTO}: ${ISSUES}개 문제 발견" "Port ${PORT}/${PROTO}: ${ISSUES} issue(s) found")"
    fi
    echo ""
    return $ISSUES
}

#==============================================================================
# REMOTE PORT CHECK
#==============================================================================
do_remote_check() {
    local HOST="$1"
    local PORT="$2"
    local PROTO="$3"
    local TIMEOUT="${CHECK_PORT_TIMEOUT:-5}"
    local ISSUES=0

    print_header "$(msg '원격 포트 접속 점검' 'Remote Port Connectivity Check'): ${HOST}:${PORT}/${PROTO}"
    echo -e "  $(msg '출발지' 'Source')  : $(hostname)"
    echo -e "  $(msg '대상' 'Target')    : ${HOST}:${PORT}/${PROTO}"
    echo -e "  $(msg '타임아웃' 'Timeout'): ${TIMEOUT}$(msg '초' 's')"

    # --- 1. DNS ---
    print_header "1. $(msg 'DNS 해석' 'DNS Resolution')"
    local RESOLVED_IP=""
    case "$HOST" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*)
            RESOLVED_IP="$HOST"
            print_info "$(msg "IP 직접 입력: ${RESOLVED_IP}" "IP provided: ${RESOLVED_IP}")"
            ;;
        *)
            if command -v host >/dev/null 2>&1; then
                RESOLVED_IP=$(host "$HOST" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}' || true)
            elif command -v nslookup >/dev/null 2>&1; then
                RESOLVED_IP=$(nslookup "$HOST" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1 || true)
            elif command -v getent >/dev/null 2>&1; then
                RESOLVED_IP=$(getent hosts "$HOST" 2>/dev/null | awk '{print $1}' | head -1 || true)
            fi
            if [ -n "$RESOLVED_IP" ]; then
                print_ok "${HOST} -> ${RESOLVED_IP}"
            else
                print_fail "$(msg 'DNS 해석 실패!' 'DNS resolution FAILED!')"
                ISSUES=$((ISSUES + 1))
            fi
            ;;
    esac

    # --- 2. Route ---
    print_header "2. $(msg '네트워크 경로' 'Network Route')"
    if command -v ip >/dev/null 2>&1; then
        local ROUTE
        ROUTE=$(ip route get "$HOST" 2>/dev/null | head -1 || true)
        if [ -n "$ROUTE" ]; then
            print_ok "$(msg '경로 존재' 'Route exists')"
            echo "    ${ROUTE}"
        else
            print_fail "$(msg '경로 없음!' 'No route!')"
            ISSUES=$((ISSUES + 1))
        fi
    elif command -v route >/dev/null 2>&1; then
        print_info "$(msg '라우팅 테이블' 'Routing table'):"
        route -n 2>/dev/null | head -5 | while IFS= read -r line; do echo "    ${line}"; done
    fi

    # --- 3. Ping ---
    print_header "3. $(msg 'Ping 테스트' 'Ping Test')"
    if command -v ping >/dev/null 2>&1; then
        local PING_OUT
        PING_OUT=$(ping -c 3 -W "$TIMEOUT" "$HOST" 2>&1 || true)
        if echo "$PING_OUT" | grep -q " 0% packet loss\| 0% loss"; then
            print_ok "$(msg 'Ping 성공' 'Ping OK')"
        elif echo "$PING_OUT" | grep -q "100% packet loss\|100% loss"; then
            print_warn "$(msg 'Ping 실패 - ICMP 차단 가능성' 'Ping failed - ICMP may be blocked')"
        else
            print_warn "$(msg '부분 손실' 'Partial loss')"
        fi
        local STATS
        STATS=$(echo "$PING_OUT" | grep -E "rtt|round-trip|packets" || true)
        [ -n "$STATS" ] && echo "$STATS" | while IFS= read -r line; do echo "    ${line}"; done
    fi

    # --- 4. Port connectivity ---
    print_header "4. $(msg 'TCP/UDP 접속 테스트' 'TCP/UDP Connectivity Test')"
    local CONNECT_OK=false CONNECT_METHOD=""

    if [ "$PROTO" = "tcp" ]; then
        # /dev/tcp
        if (echo > /dev/tcp/${HOST}/${PORT}) 2>/dev/null; then
            print_ok "${HOST}:${PORT} $(msg 'TCP 연결 성공' 'TCP OK') (/dev/tcp)"
            CONNECT_OK=true; CONNECT_METHOD="/dev/tcp"
        fi
        # nc
        if [ "$CONNECT_OK" = "false" ] && command -v nc >/dev/null 2>&1; then
            if nc -z -w "$TIMEOUT" "$HOST" "$PORT" 2>/dev/null; then
                print_ok "${HOST}:${PORT} $(msg 'TCP 연결 성공' 'TCP OK') (nc)"
                CONNECT_OK=true; CONNECT_METHOD="nc"
            fi
        fi
        # ncat
        if [ "$CONNECT_OK" = "false" ] && command -v ncat >/dev/null 2>&1; then
            if ncat -z -w "$TIMEOUT" "$HOST" "$PORT" 2>/dev/null; then
                print_ok "${HOST}:${PORT} $(msg 'TCP 연결 성공' 'TCP OK') (ncat)"
                CONNECT_OK=true; CONNECT_METHOD="ncat"
            fi
        fi
        # curl
        if [ "$CONNECT_OK" = "false" ] && command -v curl >/dev/null 2>&1; then
            local CURL_EXIT=0
            curl -so /dev/null --connect-timeout "$TIMEOUT" "http://${HOST}:${PORT}" 2>/dev/null || CURL_EXIT=$?
            if [ $CURL_EXIT -eq 0 ] || [ $CURL_EXIT -eq 52 ] || [ $CURL_EXIT -eq 56 ]; then
                print_ok "${HOST}:${PORT} $(msg 'TCP 연결 성공' 'TCP OK') (curl)"
                CONNECT_OK=true; CONNECT_METHOD="curl"
            fi
        fi

        if [ "$CONNECT_OK" = "false" ]; then
            print_fail "${HOST}:${PORT} $(msg 'TCP 연결 실패' 'TCP FAILED')"
        fi
    elif [ "$PROTO" = "udp" ]; then
        print_info "$(msg 'UDP는 비연결 프로토콜 - 정확한 판정 제한적' 'UDP is connectionless - limited accuracy')"
        if command -v nc >/dev/null 2>&1; then
            nc -zu -w "$TIMEOUT" "$HOST" "$PORT" 2>/dev/null && { print_ok "UDP $(msg '접근 가능' 'accessible')"; CONNECT_OK=true; } || print_warn "UDP $(msg '접근 불가' 'unreachable')"
        fi
    fi

    echo ""
    if [ "$CONNECT_OK" = "true" ]; then
        print_ok "${BOLD}$(msg "최종: ${HOST}:${PORT}/${PROTO} 접속 가능" "Final: ${HOST}:${PORT}/${PROTO} REACHABLE")${NC}"
    else
        print_fail "${BOLD}$(msg "최종: ${HOST}:${PORT}/${PROTO} 접속 불가" "Final: ${HOST}:${PORT}/${PROTO} UNREACHABLE")${NC}"
        ISSUES=$((ISSUES + 1))
    fi

    # --- 5. Outbound firewall ---
    print_header "5. $(msg '아웃바운드 방화벽' 'Outbound Firewall')"
    if [ "$(id -u)" -eq 0 ] && command -v iptables >/dev/null 2>&1; then
        local OUT_R OUT_POL
        OUT_R=$(iptables -L OUTPUT -n --line-numbers 2>/dev/null | grep -i "${PROTO}" | grep "${PORT}" || true)
        if [ -n "$OUT_R" ]; then
            print_info "$(msg '관련 OUTPUT 규칙:' 'OUTPUT rules:')"
            echo "$OUT_R" | while IFS= read -r rule; do
                case "$rule" in *DROP*|*REJECT*) echo -e "    ${RED}${rule}${NC}" ;; *) echo "    ${rule}" ;; esac
            done
        else
            print_info "$(msg 'OUTPUT 차단 규칙 없음' 'No OUTPUT blocking rules')"
        fi
        OUT_POL=$(iptables -L OUTPUT 2>/dev/null | head -1 | awk '{print $4}' | tr -d ')' || echo "?")
        case "$OUT_POL" in DROP|REJECT) print_warn "OUTPUT $(msg '기본 정책' 'default'): ${OUT_POL}"; ISSUES=$((ISSUES + 1)) ;; esac
    else
        print_info "$(msg 'root 필요 또는 iptables 미설치' 'Root required or iptables not found')"
    fi

    # --- 6. Traceroute ---
    print_header "6. $(msg '경로 추적' 'Traceroute')"
    if command -v traceroute >/dev/null 2>&1; then
        print_info "$(msg '추적 중... (최대 15홉)' 'Tracing... (max 15 hops)')"
        traceroute -m 15 -w 2 "$HOST" 2>&1 | head -20 | while IFS= read -r line; do
            case "$line" in *"* * *"*) echo -e "    ${YELLOW}${line}${NC}" ;; *) echo "    ${line}" ;; esac
        done
    elif command -v tracepath >/dev/null 2>&1; then
        tracepath "$HOST" 2>&1 | head -20 | while IFS= read -r line; do echo "    ${line}"; done
    else
        print_info "$(msg 'traceroute 미설치 (sudo yum install traceroute)' 'traceroute not found (sudo yum install traceroute)')"
    fi

    # --- Troubleshooting ---
    if [ "$CONNECT_OK" = "false" ]; then
        print_header "$(msg '문제 해결 가이드' 'Troubleshooting Guide')"
        echo -e "  1. $(msg '대상 서버에서 서비스 실행 확인:' 'Check service on target:')"
        echo -e "     ${YELLOW}ssh ${HOST} \"ss -tlnp | grep :${PORT}\"${NC}"
        echo -e "  2. $(msg '대상 서버 방화벽 확인:' 'Check target firewall:')"
        echo -e "     ${YELLOW}ssh ${HOST} \"sudo ./${SCRIPT_NAME} local ${PORT} ${PROTO}\"${NC}"
        echo -e "  3. $(msg '중간 네트워크 장비 확인 (라우터/스위치/IDS)' 'Check intermediate devices')"
        echo -e "  4. $(msg '아웃바운드 차단 확인:' 'Check outbound block:')"
        echo -e "     ${YELLOW}sudo iptables -L OUTPUT -n | grep ${PORT}${NC}"
    fi

    # --- Summary ---
    print_header "$(msg '종합 결과' 'Summary')"
    echo -e "  $(msg '대상' 'Target'):  ${BOLD}${HOST}:${PORT}/${PROTO}${NC}"
    echo ""
    if [ "$ISSUES" -eq 0 ]; then
        print_ok "$(msg '모든 항목 통과' 'All checks PASSED')"
    else
        print_fail "$(msg "${ISSUES}개 문제 발견" "${ISSUES} issue(s) found")"
    fi
    echo ""
    return $ISSUES
}

#==============================================================================
# QUICK MULTI-PORT SCAN
#==============================================================================
do_multi_scan() {
    local HOST="$1"
    local PORTS="$2"
    local PROTO="$3"
    local TIMEOUT="${CHECK_PORT_TIMEOUT:-3}"

    print_header "$(msg '다중 포트 스캔' 'Multi-Port Scan'): ${HOST}"
    echo ""
    printf "  ${BOLD}%-8s %-10s %-12s %s${NC}\n" "$(msg '포트' 'PORT')" "$(msg '프로토콜' 'PROTO')" "$(msg '상태' 'STATUS')" "$(msg '방법' 'METHOD')"
    echo -e "  ${DIM}──────── ────────── ──────────── ────────${NC}"

    local port
    for port in $(echo "$PORTS" | tr ',' ' '); do
        # Validate port
        if ! validate_port "$port"; then
            printf "  %-8s %-10s " "$port" "$PROTO"
            echo -e "${RED}$(msg '유효하지 않음' 'INVALID')${NC}"
            continue
        fi

        local status="CLOSED" method="-" color="$RED"

        if [ "$PROTO" = "tcp" ]; then
            if (echo > /dev/tcp/${HOST}/${port}) 2>/dev/null; then
                status="OPEN"; method="/dev/tcp"; color="$GREEN"
            elif command -v nc >/dev/null 2>&1 && nc -z -w "$TIMEOUT" "$HOST" "$port" 2>/dev/null; then
                status="OPEN"; method="nc"; color="$GREEN"
            elif command -v ncat >/dev/null 2>&1 && ncat -z -w "$TIMEOUT" "$HOST" "$port" 2>/dev/null; then
                status="OPEN"; method="ncat"; color="$GREEN"
            fi
        elif [ "$PROTO" = "udp" ]; then
            if command -v nc >/dev/null 2>&1 && nc -zu -w "$TIMEOUT" "$HOST" "$port" 2>/dev/null; then
                status="OPEN"; method="nc"; color="$GREEN"
            else
                status="$(msg '불확실' 'UNKNOWN')"; color="$YELLOW"
            fi
        fi

        printf "  %-8s %-10s " "$port" "$PROTO"
        echo -e "${color}%-12s${NC} %s" "$status" "$method"
    done
    echo ""
}

#==============================================================================
# INTERACTIVE MENU
#==============================================================================
show_menu() {
    echo ""
    echo -e "  ${BOLD}$(msg '무엇을 점검하시겠습니까?' 'What would you like to check?')${NC}"
    echo ""
    echo -e "    ${GREEN}1${NC}) $(msg '로컬 포트 점검' 'Local port check')       - $(msg '이 서버의 포트 상태 확인' 'Check port status on this server')"
    echo -e "    ${GREEN}2${NC}) $(msg '원격 포트 접속 점검' 'Remote port check')   - $(msg '다른 서버의 포트 접속 확인' 'Check connectivity to another server')"
    echo -e "    ${GREEN}3${NC}) $(msg '빠른 다중 포트 스캔' 'Quick multi-port scan') - $(msg '여러 포트를 한번에 스캔' 'Scan multiple ports at once')"
    echo ""
    echo -e "    ${CYAN}h${NC}) $(msg '도움말' 'Help')               ${CYAN}q${NC}) $(msg '종료' 'Quit')"
    echo ""
}

interactive_local() {
    echo ""
    echo -e "  ${BOLD}$(msg '── 로컬 포트 점검 ──' '── Local Port Check ──')${NC}"
    echo ""

    local port proto
    prompt_input "$(msg '포트 번호' 'Port number')" "" "port"
    if ! validate_port "$port"; then
        print_fail "$(msg '유효하지 않은 포트 번호입니다.' 'Invalid port number.')"
        return 1
    fi

    prompt_input "$(msg '프로토콜' 'Protocol')" "tcp" "proto"
    proto=$(echo "$proto" | tr '[:upper:]' '[:lower:]')
    if ! validate_proto "$proto"; then
        print_fail "$(msg '유효하지 않은 프로토콜입니다. (tcp/udp)' 'Invalid protocol. (tcp/udp)')"
        return 1
    fi

    do_local_check "$port" "$proto"
}

interactive_remote() {
    echo ""
    echo -e "  ${BOLD}$(msg '── 원격 포트 접속 점검 ──' '── Remote Port Check ──')${NC}"
    echo ""

    local host port proto
    prompt_input "$(msg '대상 호스트 (IP 또는 도메인)' 'Target host (IP or domain)')" "" "host"
    if [ -z "$host" ]; then
        print_fail "$(msg '호스트를 입력하세요.' 'Please enter a host.')"
        return 1
    fi

    prompt_input "$(msg '포트 번호' 'Port number')" "" "port"
    if ! validate_port "$port"; then
        print_fail "$(msg '유효하지 않은 포트 번호입니다.' 'Invalid port number.')"
        return 1
    fi

    prompt_input "$(msg '프로토콜' 'Protocol')" "tcp" "proto"
    proto=$(echo "$proto" | tr '[:upper:]' '[:lower:]')
    if ! validate_proto "$proto"; then
        print_fail "$(msg '유효하지 않은 프로토콜입니다. (tcp/udp)' 'Invalid protocol. (tcp/udp)')"
        return 1
    fi

    do_remote_check "$host" "$port" "$proto"
}

interactive_multi() {
    echo ""
    echo -e "  ${BOLD}$(msg '── 빠른 다중 포트 스캔 ──' '── Quick Multi-Port Scan ──')${NC}"
    echo ""

    local host ports proto
    prompt_input "$(msg '대상 호스트 (IP 또는 도메인, 로컬은 127.0.0.1)' 'Target host (IP/domain, use 127.0.0.1 for local)')" "127.0.0.1" "host"

    prompt_input "$(msg '포트 목록 (쉼표 구분, 예: 22,80,443,8080)' 'Port list (comma-sep, e.g. 22,80,443,8080)')" "22,80,443,8080" "ports"

    prompt_input "$(msg '프로토콜' 'Protocol')" "tcp" "proto"
    proto=$(echo "$proto" | tr '[:upper:]' '[:lower:]')

    do_multi_scan "$host" "$ports" "$proto"
}

run_interactive() {
    clear_screen
    show_banner
    check_root "$@"

    while true; do
        show_menu
        printf "  ${CYAN}>${NC} $(msg '선택' 'Choice') [1-3/h/q]: "
        read -r choice

        case "$choice" in
            1) interactive_local ;;
            2) interactive_remote ;;
            3) interactive_multi ;;
            h|H) show_help ;;
            q|Q|exit)
                echo ""
                echo -e "  ${GREEN}$(msg '종료합니다. 안녕히 가세요!' 'Bye!')${NC}"
                echo ""
                exit 0
                ;;
            *)
                print_warn "$(msg "유효하지 않은 선택입니다: ${choice}" "Invalid choice: ${choice}")"
                ;;
        esac

        echo ""
        if [ -t 0 ]; then
            echo -e "  ${DIM}$(msg 'Enter를 누르면 메뉴로 돌아갑니다...' 'Press Enter to return to menu...')${NC}"
            read -r _
        fi
    done
}

#==============================================================================
# MAIN: CLI argument parsing
#==============================================================================
case "${1:-}" in
    --help|-h)
        show_banner
        show_help
        exit 0
        ;;
    --version|-v)
        echo "portcheck.sh v${SCRIPT_VERSION}"
        exit 0
        ;;
    local)
        shift
        if [ $# -lt 1 ]; then
            echo -e "${RED}$(msg '사용법' 'Usage'): ${SCRIPT_NAME} local <$(msg '포트' 'port')> [tcp|udp]${NC}"
            exit 1
        fi
        PORT="$1"; PROTO="${2:-tcp}"
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        validate_port "$PORT" || { echo -e "${RED}$(msg '유효하지 않은 포트' 'Invalid port')${NC}"; exit 1; }
        validate_proto "$PROTO" || { echo -e "${RED}$(msg '유효하지 않은 프로토콜' 'Invalid protocol')${NC}"; exit 1; }
        show_banner
        do_local_check "$PORT" "$PROTO"
        exit $?
        ;;
    remote)
        shift
        if [ $# -lt 2 ]; then
            echo -e "${RED}$(msg '사용법' 'Usage'): ${SCRIPT_NAME} remote <$(msg '호스트' 'host')> <$(msg '포트' 'port')> [tcp|udp]${NC}"
            exit 1
        fi
        HOST="$1"; PORT="$2"; PROTO="${3:-tcp}"
        PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
        validate_port "$PORT" || { echo -e "${RED}$(msg '유효하지 않은 포트' 'Invalid port')${NC}"; exit 1; }
        validate_proto "$PROTO" || { echo -e "${RED}$(msg '유효하지 않은 프로토콜' 'Invalid protocol')${NC}"; exit 1; }
        show_banner
        do_remote_check "$HOST" "$PORT" "$PROTO"
        exit $?
        ;;
    "")
        # No arguments = interactive mode
        run_interactive "$@"
        ;;
    *)
        echo -e "${RED}$(msg "알 수 없는 명령: $1" "Unknown command: $1")${NC}"
        echo -e "$(msg '도움말' 'Help'): ${SCRIPT_NAME} --help"
        exit 1
        ;;
esac
