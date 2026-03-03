#!/bin/bash
#==============================================================================
# check_port.sh - Red Hat Linux Port Status Check Script
#
# Supports: RHEL 6.x / 7.x / 8.x (CentOS compatible)
# Language: Auto-detect (Korean / English)
#
# Features:
#   1. Check if port is in use (ss/netstat)
#   2. Check firewalld rules (RHEL 7+)
#   3. Check iptables rules
#   4. Check nftables rules (RHEL 8+)
#   5. Check SELinux port policy
#   6. Local port connectivity test
#
# Usage:
#   ./check_port.sh <port> [tcp|udp]
#   ./check_port.sh 8080
#   ./check_port.sh 8080 tcp
#   ./check_port.sh 53 udp
#==============================================================================

set -uo pipefail

#==============================================================================
# Locale detection & message definitions
#==============================================================================
detect_lang() {
    # Check LANG, LC_ALL, LC_MESSAGES for Korean locale
    local lc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    case "$lc" in
        ko_KR*|ko.*|korean*) echo "ko" ;;
        *) echo "en" ;;
    esac
}

SCRIPT_LANG=$(detect_lang)

# Force language via environment: CHECK_PORT_LANG=ko or CHECK_PORT_LANG=en
if [ -n "${CHECK_PORT_LANG:-}" ]; then
    SCRIPT_LANG="$CHECK_PORT_LANG"
fi

# --- Message function: returns Korean or English based on SCRIPT_LANG ---
msg() {
    if [ "$SCRIPT_LANG" = "ko" ]; then
        echo "$1"
    else
        echo "$2"
    fi
}

# --- Color setup (with terminal capability check) ---
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# --- Utility functions ---
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

# --- RHEL version detection ---
detect_rhel_version() {
    RHEL_MAJOR=0
    if [ -f /etc/redhat-release ]; then
        RHEL_MAJOR=$(sed 's/.*release \([0-9]*\).*/\1/' /etc/redhat-release 2>/dev/null || echo 0)
    elif [ -f /etc/os-release ]; then
        RHEL_MAJOR=$(grep -oE 'VERSION_ID="?[0-9]+' /etc/os-release 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo 0)
    fi
    case "$RHEL_MAJOR" in
        ''|*[!0-9]*) RHEL_MAJOR=0 ;;
    esac
}

# --- Service status check (RHEL 6/7/8 compatible) ---
is_service_active() {
    local svc_name="$1"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active "$svc_name" >/dev/null 2>&1
    else
        service "$svc_name" status >/dev/null 2>&1
    fi
}

# --- Argument validation ---
if [ $# -lt 1 ]; then
    echo -e "${RED}$(msg '사용법' 'Usage'): $0 <$(msg '포트번호' 'port')> [tcp|udp]${NC}"
    echo "  $(msg '예시' 'Example'): $0 8080"
    echo "  $(msg '예시' 'Example'): $0 8080 tcp"
    echo "  $(msg '예시' 'Example'): $0 53 udp"
    exit 1
fi

PORT="$1"
PROTO="${2:-tcp}"

# Port number validation
case "$PORT" in
    ''|*[!0-9]*)
        echo -e "${RED}$(msg '오류: 유효한 포트 번호를 입력하세요 (1-65535)' 'Error: Enter a valid port number (1-65535)')${NC}"
        exit 1
        ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo -e "${RED}$(msg '오류: 유효한 포트 번호를 입력하세요 (1-65535)' 'Error: Enter a valid port number (1-65535)')${NC}"
    exit 1
fi

# Protocol validation
PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
if [ "$PROTO" != "tcp" ] && [ "$PROTO" != "udp" ]; then
    echo -e "${RED}$(msg '오류: 프로토콜은 tcp 또는 udp만 지원합니다.' 'Error: Only tcp or udp protocols are supported.')${NC}"
    exit 1
fi

# RHEL version detection
detect_rhel_version
if [ "$RHEL_MAJOR" -gt 0 ]; then
    RELEASE_INFO=$(cat /etc/redhat-release 2>/dev/null || echo "RHEL ${RHEL_MAJOR}")
else
    RELEASE_INFO=$(msg "알 수 없음 (RHEL 호환 환경으로 가정)" "Unknown (assuming RHEL-compatible)")
fi

print_header "$(msg '포트 점검 시작' 'Port Check Start'): ${PORT}/${PROTO}"
echo -e "  $(msg '점검 시간' 'Check Time')  : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  $(msg '호스트명' 'Hostname')   : $(hostname)"
echo -e "  $(msg 'OS 정보' 'OS Info')    : ${RELEASE_INFO}"
echo -e "  $(msg '언어' 'Language')     : $(msg '한국어' 'English')"
if [ "$RHEL_MAJOR" -gt 0 ]; then
    echo -e "  RHEL Major : ${RHEL_MAJOR}.x"
fi

# --- Root privilege check ---
if [ "$(id -u)" -ne 0 ]; then
    echo ""
    echo -e "  ${YELLOW}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}│  $(msg '경고: root 권한 없이 실행 중입니다!' 'WARNING: Running without root privileges!')                       │${NC}"
    echo -e "  ${YELLOW}│                                                              │${NC}"
    echo -e "  ${YELLOW}│  $(msg '다음 항목은 root 권한이 필요하여 점검이 제한됩니다:' 'The following checks require root and will be limited:')    │${NC}"
    echo -e "  ${YELLOW}│    - ss/netstat -p $(msg '(프로세스 정보 표시)' '(show process info)')                       │${NC}"
    echo -e "  ${YELLOW}│    - iptables $(msg '규칙 조회' 'rule listing')                                  │${NC}"
    echo -e "  ${YELLOW}│    - nftables $(msg '규칙 조회' 'rule listing')                                  │${NC}"
    echo -e "  ${YELLOW}│    - SELinux $(msg '포트 정책 조회' 'port policy query') (semanage)                      │${NC}"
    echo -e "  ${YELLOW}│                                                              │${NC}"
    echo -e "  ${YELLOW}│  $(msg '완전한 점검을 위해 sudo로 실행하세요:' 'For a complete check, run with sudo:')                   │${NC}"
    echo -e "  ${YELLOW}│    sudo $0 ${PORT} ${PROTO}$(printf '%*s' $((28 - ${#PORT} - ${#PROTO})) '')│${NC}"
    echo -e "  ${YELLOW}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Auto sudo re-execution (interactive terminal only)
    if [ -t 0 ]; then
        printf "  $(msg 'sudo로 재실행하시겠습니까?' 'Re-run with sudo?') [Y/n] "
        read -r REPLY
        case "$REPLY" in
            ''|[Yy]|[Yy][Ee][Ss])
                echo ""
                exec sudo "$0" "$PORT" "$PROTO"
                ;;
            *)
                echo ""
                print_info "$(msg 'root 없이 가능한 범위에서 점검을 계속합니다...' 'Continuing with limited checks (no root)...')"
                ;;
        esac
    fi
fi

OVERALL_ISSUES=0

#==============================================================================
# 1. Port usage check (ss or netstat)
#==============================================================================
print_header "1. $(msg '포트 사용 여부 확인' 'Port Usage Check')"

LISTEN_RESULT=""
TOOL_USED="none"

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
    print_warn "$(msg 'ss 또는 netstat 명령어를 찾을 수 없습니다.' 'Cannot find ss or netstat command.')"
    print_info "$(msg 'RHEL 6: net-tools / RHEL 7+: iproute 패키지를 설치하세요.' 'RHEL 6: install net-tools / RHEL 7+: install iproute')"
fi

if [ -n "$LISTEN_RESULT" ]; then
    print_ok "$(msg "포트 ${PORT}/${PROTO}가 현재 LISTEN 상태입니다." "Port ${PORT}/${PROTO} is currently LISTENING.") (${TOOL_USED})"
    echo ""
    echo "$LISTEN_RESULT" | while IFS= read -r line; do
        echo "    ${line}"
    done

    # Process info extraction (ss only)
    if [ "$TOOL_USED" = "ss" ]; then
        PROC_INFO=""
        if [ "$PROTO" = "tcp" ]; then
            PROC_INFO=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | sed -n 's/.*\(users:([^)]*)\).*/\1/p' || true)
        else
            PROC_INFO=$(ss -ulnp 2>/dev/null | grep ":${PORT} " | sed -n 's/.*\(users:([^)]*)\).*/\1/p' || true)
        fi
        if [ -n "$PROC_INFO" ]; then
            echo ""
            print_info "$(msg '사용 중인 프로세스' 'Process using port'): ${PROC_INFO}"
        fi
    fi
else
    print_warn "$(msg "포트 ${PORT}/${PROTO}에서 LISTEN 중인 서비스가 없습니다." "No service is LISTENING on port ${PORT}/${PROTO}.")"
    OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
fi

# ESTABLISHED connections
if command -v ss >/dev/null 2>&1; then
    ESTABLISHED=$(ss -tn state established "( sport = :${PORT} or dport = :${PORT} )" 2>/dev/null | tail -n +2 || true)
    if [ -n "$ESTABLISHED" ]; then
        CONN_COUNT=$(echo "$ESTABLISHED" | wc -l)
        echo ""
        print_info "$(msg "현재 활성 연결 수: ${CONN_COUNT}개" "Active connections: ${CONN_COUNT}")"
    fi
elif command -v netstat >/dev/null 2>&1; then
    ESTABLISHED=$(netstat -tn 2>/dev/null | grep ":${PORT} " | grep "ESTABLISHED" || true)
    if [ -n "$ESTABLISHED" ]; then
        CONN_COUNT=$(echo "$ESTABLISHED" | wc -l)
        echo ""
        print_info "$(msg "현재 활성 연결 수: ${CONN_COUNT}개" "Active connections: ${CONN_COUNT}")"
    fi
fi

#==============================================================================
# 2. firewalld check (RHEL 7+)
#==============================================================================
print_header "2. $(msg 'firewalld 방화벽 확인' 'firewalld Firewall Check')"

if [ "$RHEL_MAJOR" -ge 7 ] || [ "$RHEL_MAJOR" -eq 0 ]; then
    if command -v firewall-cmd >/dev/null 2>&1; then
        if is_service_active firewalld; then
            print_ok "$(msg 'firewalld가 실행 중입니다.' 'firewalld is running.')"

            ACTIVE_ZONE=$(firewall-cmd --get-active-zones 2>/dev/null | head -1 || echo "public")
            print_info "$(msg '활성 Zone' 'Active Zone'): ${ACTIVE_ZONE}"

            PORT_ALLOWED=false
            if firewall-cmd --query-port="${PORT}/${PROTO}" --zone="${ACTIVE_ZONE}" >/dev/null 2>&1; then
                print_ok "$(msg "포트 ${PORT}/${PROTO}가 firewalld에서 허용되어 있습니다." "Port ${PORT}/${PROTO} is ALLOWED in firewalld.") (zone: ${ACTIVE_ZONE})"
                PORT_ALLOWED=true
            fi

            if [ "$PORT_ALLOWED" = "false" ]; then
                SERVICE_FOUND=false
                SERVICES=$(firewall-cmd --list-services --zone="${ACTIVE_ZONE}" 2>/dev/null || true)
                for svc in $SERVICES; do
                    SVC_PORTS=$(firewall-cmd --service="${svc}" --get-ports 2>/dev/null || true)
                    case " $SVC_PORTS " in
                        *" ${PORT}/${PROTO} "*)
                            print_ok "$(msg "포트 ${PORT}/${PROTO}가 서비스 '${svc}'를 통해 허용되어 있습니다." "Port ${PORT}/${PROTO} is allowed via service '${svc}'.")"
                            SERVICE_FOUND=true
                            break
                            ;;
                    esac
                done

                if [ "$SERVICE_FOUND" = "false" ]; then
                    print_fail "$(msg "포트 ${PORT}/${PROTO}가 firewalld에서 차단되어 있습니다!" "Port ${PORT}/${PROTO} is BLOCKED by firewalld!")"
                    echo ""
                    print_info "$(msg '허용하려면 다음 명령어를 실행하세요:' 'To allow, run:')"
                    echo -e "    ${YELLOW}sudo firewall-cmd --permanent --add-port=${PORT}/${PROTO}${NC}"
                    echo -e "    ${YELLOW}sudo firewall-cmd --reload${NC}"
                    OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
                fi
            fi

            RICH_RULES=$(firewall-cmd --list-rich-rules --zone="${ACTIVE_ZONE}" 2>/dev/null | grep "${PORT}" || true)
            if [ -n "$RICH_RULES" ]; then
                echo ""
                print_info "$(msg '관련 Rich Rules:' 'Related Rich Rules:')"
                echo "$RICH_RULES" | while IFS= read -r rule; do
                    echo "    ${rule}"
                done
            fi
        else
            print_info "$(msg 'firewalld가 실행 중이 아닙니다. (iptables 규칙을 직접 확인합니다)' 'firewalld is not running. (Checking iptables directly)')"
        fi
    else
        print_info "$(msg 'firewall-cmd 명령어를 찾을 수 없습니다. (firewalld 미설치)' 'firewall-cmd not found. (firewalld not installed)')"
    fi
else
    print_info "$(msg "RHEL ${RHEL_MAJOR}.x 에서는 firewalld를 사용하지 않습니다. (iptables 섹션 참조)" "RHEL ${RHEL_MAJOR}.x does not use firewalld. (See iptables section)")"
fi

#==============================================================================
# 3. iptables rules check (all RHEL versions)
#==============================================================================
print_header "3. $(msg 'iptables 규칙 확인' 'iptables Rules Check')"

if command -v iptables >/dev/null 2>&1; then
    if [ "$RHEL_MAJOR" -le 6 ] && [ "$RHEL_MAJOR" -gt 0 ]; then
        if is_service_active iptables; then
            print_ok "$(msg "iptables 서비스가 실행 중입니다. (RHEL ${RHEL_MAJOR} 기본 방화벽)" "iptables service is running. (RHEL ${RHEL_MAJOR} default firewall)")"
        else
            print_warn "$(msg 'iptables 서비스가 실행 중이 아닙니다.' 'iptables service is not running.')"
        fi
    fi

    if [ "$(id -u)" -eq 0 ]; then
        IPTABLES_RULES=$(iptables -L INPUT -n --line-numbers 2>/dev/null | grep -i "${PROTO}" | grep "${PORT}" || true)

        if [ -n "$IPTABLES_RULES" ]; then
            print_info "$(msg "포트 ${PORT}/${PROTO} 관련 iptables 규칙:" "iptables rules for port ${PORT}/${PROTO}:")"
            echo ""
            echo "$IPTABLES_RULES" | while IFS= read -r rule; do
                case "$rule" in
                    *DROP*|*REJECT*)
                        echo -e "    ${RED}${rule}${NC}" ;;
                    *ACCEPT*)
                        echo -e "    ${GREEN}${rule}${NC}" ;;
                    *)
                        echo "    ${rule}" ;;
                esac
            done
        else
            print_info "$(msg "포트 ${PORT}/${PROTO}에 대한 명시적 iptables 규칙이 없습니다." "No explicit iptables rules for port ${PORT}/${PROTO}.")"
        fi

        DEFAULT_POLICY=$(iptables -L INPUT 2>/dev/null | head -1 | awk '{print $4}' | tr -d ')' || echo "unknown")
        case "$DEFAULT_POLICY" in
            DROP|REJECT)
                print_warn "$(msg "INPUT 체인 기본 정책: ${DEFAULT_POLICY} (명시적 ACCEPT 규칙 없으면 차단됨)" "INPUT chain default policy: ${DEFAULT_POLICY} (blocked without explicit ACCEPT)")"
                OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
                ;;
            *)
                print_info "$(msg "INPUT 체인 기본 정책: ${DEFAULT_POLICY}" "INPUT chain default policy: ${DEFAULT_POLICY}")"
                ;;
        esac

        # RHEL 6: check saved rules
        if [ "$RHEL_MAJOR" -le 6 ] && [ "$RHEL_MAJOR" -gt 0 ]; then
            if [ -f /etc/sysconfig/iptables ]; then
                SAVED_RULES=$(grep -i "${PORT}" /etc/sysconfig/iptables 2>/dev/null || true)
                if [ -n "$SAVED_RULES" ]; then
                    echo ""
                    print_info "$(msg '/etc/sysconfig/iptables 저장된 규칙:' '/etc/sysconfig/iptables saved rules:')"
                    echo "$SAVED_RULES" | while IFS= read -r rule; do
                        echo "    ${rule}"
                    done
                fi
            fi
            echo ""
            print_info "$(msg 'RHEL 6에서 포트를 영구 허용하려면:' 'To permanently allow port on RHEL 6:')"
            echo -e "    ${YELLOW}sudo iptables -I INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT${NC}"
            echo -e "    ${YELLOW}sudo service iptables save${NC}"
        fi
    else
        print_warn "$(msg 'iptables 규칙 확인에는 root 권한이 필요합니다.' 'Root privileges required to check iptables rules.')"
        print_info "sudo $0 ${PORT} ${PROTO}"
    fi
else
    print_warn "$(msg 'iptables 명령어를 찾을 수 없습니다.' 'iptables command not found.')"
fi

#==============================================================================
# 4. nftables rules check (RHEL 8+)
#==============================================================================
print_header "4. $(msg 'nftables 규칙 확인' 'nftables Rules Check')"

if [ "$RHEL_MAJOR" -ge 8 ] || [ "$RHEL_MAJOR" -eq 0 ]; then
    if command -v nft >/dev/null 2>&1; then
        if [ "$(id -u)" -eq 0 ]; then
            NFT_RULES=$(nft list ruleset 2>/dev/null | grep -iE "${PROTO}.*dport.*${PORT}|${PROTO}.*${PORT}" || true)
            if [ -n "$NFT_RULES" ]; then
                print_info "$(msg "포트 ${PORT}/${PROTO} 관련 nftables 규칙:" "nftables rules for port ${PORT}/${PROTO}:")"
                echo "$NFT_RULES" | while IFS= read -r rule; do
                    case "$rule" in
                        *drop*|*reject*)
                            echo -e "    ${RED}${rule}${NC}" ;;
                        *accept*)
                            echo -e "    ${GREEN}${rule}${NC}" ;;
                        *)
                            echo "    ${rule}" ;;
                    esac
                done
            else
                print_info "$(msg "포트 ${PORT}/${PROTO}에 대한 명시적 nftables 규칙이 없습니다." "No explicit nftables rules for port ${PORT}/${PROTO}.")"
            fi
        else
            print_warn "$(msg 'nftables 규칙 확인에는 root 권한이 필요합니다.' 'Root privileges required to check nftables rules.')"
        fi
    else
        print_info "$(msg 'nft 명령어를 찾을 수 없습니다. (nftables 미설치)' 'nft command not found. (nftables not installed)')"
    fi
else
    print_info "$(msg "RHEL ${RHEL_MAJOR}.x 에서는 nftables를 지원하지 않습니다. (RHEL 8+ 전용)" "RHEL ${RHEL_MAJOR}.x does not support nftables. (RHEL 8+ only)")"
fi

#==============================================================================
# 5. SELinux port policy check
#==============================================================================
print_header "5. $(msg 'SELinux 포트 정책 확인' 'SELinux Port Policy Check')"

if command -v sestatus >/dev/null 2>&1; then
    SELINUX_STATUS=$(sestatus 2>/dev/null | grep "SELinux status" | awk '{print $3}' || echo "unknown")
    SELINUX_MODE=$(sestatus 2>/dev/null | grep "Current mode" | awk '{print $3}' || echo "unknown")

    if [ "$SELINUX_STATUS" = "enabled" ]; then
        print_info "$(msg "SELinux 상태: ${SELINUX_STATUS} (모드: ${SELINUX_MODE})" "SELinux status: ${SELINUX_STATUS} (mode: ${SELINUX_MODE})")"

        if command -v semanage >/dev/null 2>&1; then
            SELINUX_PORT=$(semanage port -l 2>/dev/null | grep "${PROTO}" | grep -w "${PORT}" || true)
            if [ -n "$SELINUX_PORT" ]; then
                print_ok "$(msg "포트 ${PORT}/${PROTO}가 SELinux 정책에 등록되어 있습니다:" "Port ${PORT}/${PROTO} is registered in SELinux policy:")"
                echo "$SELINUX_PORT" | while IFS= read -r line; do
                    echo "    ${line}"
                done
            else
                if [ "$SELINUX_MODE" = "enforcing" ]; then
                    print_warn "$(msg "포트 ${PORT}/${PROTO}가 SELinux에 등록되지 않았습니다. (enforcing 모드에서 차단될 수 있음)" "Port ${PORT}/${PROTO} is NOT registered in SELinux. (May be blocked in enforcing mode)")"
                    print_info "$(msg '허용하려면' 'To allow'): sudo semanage port -a -t <type> -p ${PROTO} ${PORT}"
                    OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
                else
                    print_info "$(msg "포트 ${PORT}/${PROTO}가 SELinux에 등록되지 않았지만, permissive 모드이므로 차단되지 않습니다." "Port ${PORT}/${PROTO} is not in SELinux but permissive mode - not blocked.")"
                fi
            fi
        else
            print_warn "$(msg 'semanage 명령어가 없습니다.' 'semanage command not found.')"
            if [ "$RHEL_MAJOR" -le 7 ] && [ "$RHEL_MAJOR" -gt 0 ]; then
                print_info "$(msg '설치' 'Install'): sudo yum install policycoreutils-python"
            else
                print_info "$(msg '설치' 'Install'): sudo yum install policycoreutils-python-utils"
            fi
        fi
    else
        print_info "$(msg 'SELinux가 비활성화되어 있습니다.' 'SELinux is disabled.')"
    fi
else
    print_info "$(msg 'sestatus 명령어를 찾을 수 없습니다.' 'sestatus command not found.')"
fi

#==============================================================================
# 6. Local port connectivity test
#==============================================================================
print_header "6. $(msg '로컬 포트 접속 테스트' 'Local Port Connectivity Test')"

if [ "$PROTO" = "tcp" ]; then
    CONNECT_OK=false

    # Method 1: bash built-in /dev/tcp
    if (echo > /dev/tcp/127.0.0.1/${PORT}) 2>/dev/null; then
        print_ok "127.0.0.1:${PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (/dev/tcp)"
        CONNECT_OK=true
    fi

    # Method 2: nc / ncat
    if [ "$CONNECT_OK" = "false" ]; then
        if command -v nc >/dev/null 2>&1; then
            if nc -z -w 3 127.0.0.1 "${PORT}" 2>/dev/null; then
                print_ok "127.0.0.1:${PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (nc)"
                CONNECT_OK=true
            fi
        elif command -v ncat >/dev/null 2>&1; then
            if ncat -z -w 3 127.0.0.1 "${PORT}" 2>/dev/null; then
                print_ok "127.0.0.1:${PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (ncat)"
                CONNECT_OK=true
            fi
        fi
    fi

    # Method 3: curl
    if [ "$CONNECT_OK" = "false" ]; then
        if command -v curl >/dev/null 2>&1; then
            if curl -s --connect-timeout 3 "http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
                print_ok "127.0.0.1:${PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (curl)"
                CONNECT_OK=true
            fi
        fi
    fi

    if [ "$CONNECT_OK" = "false" ]; then
        print_warn "127.0.0.1:${PORT} $(msg 'TCP 연결 실패 (서비스가 LISTEN 중이 아니거나 차단됨)' 'TCP connection failed (service not listening or blocked)')"
        OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
    fi

elif [ "$PROTO" = "udp" ]; then
    if command -v nc >/dev/null 2>&1; then
        if nc -zu -w 3 127.0.0.1 "${PORT}" 2>/dev/null; then
            print_ok "127.0.0.1:${PORT} $(msg 'UDP 포트 접근 가능' 'UDP port accessible')"
        else
            print_warn "127.0.0.1:${PORT} $(msg 'UDP 포트 접근 불가 또는 응답 없음' 'UDP port unreachable or no response')"
        fi
    elif command -v ncat >/dev/null 2>&1; then
        if ncat -zu -w 3 127.0.0.1 "${PORT}" 2>/dev/null; then
            print_ok "127.0.0.1:${PORT} $(msg 'UDP 포트 접근 가능' 'UDP port accessible')"
        else
            print_warn "127.0.0.1:${PORT} $(msg 'UDP 포트 접근 불가 또는 응답 없음' 'UDP port unreachable or no response')"
        fi
    else
        print_warn "$(msg 'UDP 테스트에 nc 또는 ncat 명령어가 필요합니다.' 'nc or ncat command required for UDP test.')"
        if [ "$RHEL_MAJOR" -le 6 ] && [ "$RHEL_MAJOR" -gt 0 ]; then
            print_info "$(msg '설치' 'Install'): sudo yum install nc"
        else
            print_info "$(msg '설치' 'Install'): sudo yum install nmap-ncat"
        fi
    fi
fi

#==============================================================================
# 7. RHEL version-specific firewall guide
#==============================================================================
print_header "7. $(msg 'RHEL 버전별 방화벽 관리 참고' 'RHEL Version-Specific Firewall Guide')"

if [ "$RHEL_MAJOR" -le 6 ] && [ "$RHEL_MAJOR" -gt 0 ]; then
    echo -e "  ${BOLD}[RHEL 6.x]${NC}"
    echo -e "  $(msg '포트 허용:' 'Allow port:')"
    echo -e "    ${YELLOW}sudo iptables -I INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT${NC}"
    echo -e "    ${YELLOW}sudo service iptables save${NC}"
    echo -e "    ${YELLOW}sudo service iptables restart${NC}"
    echo -e "  $(msg '설정 파일' 'Config file'): /etc/sysconfig/iptables"
elif [ "$RHEL_MAJOR" -eq 7 ]; then
    echo -e "  ${BOLD}[RHEL 7.x]${NC}"
    echo -e "  $(msg '포트 허용 (firewalld):' 'Allow port (firewalld):')"
    echo -e "    ${YELLOW}sudo firewall-cmd --permanent --add-port=${PORT}/${PROTO}${NC}"
    echo -e "    ${YELLOW}sudo firewall-cmd --reload${NC}"
    echo -e "  $(msg '포트 허용 (iptables 직접 사용 시):' 'Allow port (using iptables directly):')"
    echo -e "    ${YELLOW}sudo iptables -I INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT${NC}"
elif [ "$RHEL_MAJOR" -ge 8 ]; then
    echo -e "  ${BOLD}[RHEL 8.x]${NC}"
    echo -e "  $(msg '포트 허용 (firewalld - 권장):' 'Allow port (firewalld - recommended):')"
    echo -e "    ${YELLOW}sudo firewall-cmd --permanent --add-port=${PORT}/${PROTO}${NC}"
    echo -e "    ${YELLOW}sudo firewall-cmd --reload${NC}"
    echo -e "  $(msg '백엔드: nftables (firewalld가 자동 관리)' 'Backend: nftables (managed by firewalld)')"
else
    echo -e "  $(msg 'RHEL 버전을 감지하지 못했습니다. 위 점검 결과를 참조하세요.' 'RHEL version not detected. Refer to the check results above.')"
fi

#==============================================================================
# Summary
#==============================================================================
print_header "$(msg '종합 점검 결과' 'Summary')"

if [ "$OVERALL_ISSUES" -eq 0 ]; then
    print_ok "$(msg "포트 ${PORT}/${PROTO}: 모든 점검 항목 통과" "Port ${PORT}/${PROTO}: All checks PASSED")"
else
    print_fail "$(msg "포트 ${PORT}/${PROTO}: ${OVERALL_ISSUES}개 항목에서 문제 발견" "Port ${PORT}/${PROTO}: ${OVERALL_ISSUES} issue(s) found")"
    echo ""
    print_info "$(msg '위의 각 섹션에서 [FAIL] 또는 [WARN] 표시된 항목을 확인하세요.' 'Review [FAIL] and [WARN] items in the sections above.')"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  $(msg '점검 완료' 'Check completed'): $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

exit $OVERALL_ISSUES
