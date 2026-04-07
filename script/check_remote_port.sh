#!/bin/bash
#==============================================================================
# check_remote_port.sh - Remote Host Port Connectivity Check Script
#
# Supports: RHEL 6.x / 7.x / 8.x (CentOS compatible)
# Language: Auto-detect (Korean / English)
#
# Features:
#   1. TCP/UDP connectivity test (multiple methods)
#   2. DNS resolution check
#   3. Route/gateway check
#   4. Traceroute diagnostics (optional)
#   5. Latency measurement
#
# Usage:
#   ./check_remote_port.sh <host> <port> [tcp|udp]
#   ./check_remote_port.sh 192.168.1.100 8080
#   ./check_remote_port.sh myserver.com 443 tcp
#   ./check_remote_port.sh 10.0.0.1 53 udp
#==============================================================================

set -uo pipefail

#==============================================================================
# Locale detection & message definitions
#==============================================================================
detect_lang() {
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

msg() {
    if [ "$SCRIPT_LANG" = "ko" ]; then
        echo "$1"
    else
        echo "$2"
    fi
}

# --- Color setup ---
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

# --- Argument validation ---
if [ $# -lt 2 ]; then
    echo -e "${RED}$(msg '사용법' 'Usage'): $0 <$(msg '호스트/IP' 'host/IP')> <$(msg '포트' 'port')> [tcp|udp]${NC}"
    echo ""
    echo "  $(msg '예시' 'Example'): $0 192.168.1.100 8080"
    echo "  $(msg '예시' 'Example'): $0 myserver.com 443 tcp"
    echo "  $(msg '예시' 'Example'): $0 10.0.0.1 53 udp"
    echo ""
    echo "  $(msg '환경변수' 'Env var'): CHECK_PORT_LANG=en|ko  ($(msg '언어 강제 지정' 'force language'))"
    echo "  $(msg '환경변수' 'Env var'): CHECK_PORT_TIMEOUT=5   ($(msg '타임아웃 초 (기본: 5)' 'timeout seconds (default: 5)'))"
    exit 1
fi

TARGET_HOST="$1"
TARGET_PORT="$2"
PROTO="${3:-tcp}"
TIMEOUT="${CHECK_PORT_TIMEOUT:-5}"

# Port validation
case "$TARGET_PORT" in
    ''|*[!0-9]*)
        echo -e "${RED}$(msg '오류: 유효한 포트 번호를 입력하세요 (1-65535)' 'Error: Enter a valid port number (1-65535)')${NC}"
        exit 1
        ;;
esac
if [ "$TARGET_PORT" -lt 1 ] || [ "$TARGET_PORT" -gt 65535 ]; then
    echo -e "${RED}$(msg '오류: 유효한 포트 번호를 입력하세요 (1-65535)' 'Error: Enter a valid port number (1-65535)')${NC}"
    exit 1
fi

# Protocol validation
PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]')
if [ "$PROTO" != "tcp" ] && [ "$PROTO" != "udp" ]; then
    echo -e "${RED}$(msg '오류: 프로토콜은 tcp 또는 udp만 지원합니다.' 'Error: Only tcp or udp protocols are supported.')${NC}"
    exit 1
fi

OVERALL_ISSUES=0

print_header "$(msg '원격 포트 접속 점검 시작' 'Remote Port Connectivity Check')"
echo -e "  $(msg '점검 시간' 'Check Time')  : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  $(msg '출발지' 'Source')      : $(hostname)"
echo -e "  $(msg '대상 호스트' 'Target Host'): ${TARGET_HOST}"
echo -e "  $(msg '대상 포트' 'Target Port')  : ${TARGET_PORT}/${PROTO}"
echo -e "  $(msg '타임아웃' 'Timeout')    : ${TIMEOUT}$(msg '초' 's')"
echo -e "  $(msg '언어' 'Language')     : $(msg '한국어' 'English')"

#==============================================================================
# 1. DNS resolution check
#==============================================================================
print_header "1. $(msg 'DNS 이름 해석 확인' 'DNS Resolution Check')"

RESOLVED_IP=""

# Check if input is already an IP address
case "$TARGET_HOST" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*)
        RESOLVED_IP="$TARGET_HOST"
        print_info "$(msg "IP 주소가 직접 입력되었습니다: ${RESOLVED_IP}" "IP address provided directly: ${RESOLVED_IP}")"
        ;;
    *)
        # Try DNS resolution
        if command -v host >/dev/null 2>&1; then
            RESOLVED_IP=$(host "$TARGET_HOST" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}' || true)
        elif command -v nslookup >/dev/null 2>&1; then
            RESOLVED_IP=$(nslookup "$TARGET_HOST" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1 || true)
        elif command -v dig >/dev/null 2>&1; then
            RESOLVED_IP=$(dig +short "$TARGET_HOST" 2>/dev/null | head -1 || true)
        elif command -v getent >/dev/null 2>&1; then
            RESOLVED_IP=$(getent hosts "$TARGET_HOST" 2>/dev/null | awk '{print $1}' | head -1 || true)
        fi

        if [ -n "$RESOLVED_IP" ]; then
            print_ok "$(msg "${TARGET_HOST} → ${RESOLVED_IP} (DNS 해석 성공)" "${TARGET_HOST} → ${RESOLVED_IP} (DNS resolved)")"
        else
            print_fail "$(msg "${TARGET_HOST} DNS 해석 실패! 호스트명을 확인하세요." "${TARGET_HOST} DNS resolution FAILED! Check hostname.")"
            OVERALL_ISSUES=$((OVERALL_ISSUES + 1))

            # Try /etc/hosts
            HOSTS_ENTRY=$(grep -w "$TARGET_HOST" /etc/hosts 2>/dev/null || true)
            if [ -n "$HOSTS_ENTRY" ]; then
                print_info "$(msg '/etc/hosts 에서 발견:' 'Found in /etc/hosts:')"
                echo "    ${HOSTS_ENTRY}"
            else
                print_info "$(msg '/etc/hosts 에도 등록되어 있지 않습니다.' 'Not found in /etc/hosts either.')"
            fi

            print_info "$(msg '확인 사항:' 'Check:')"
            echo "    - /etc/resolv.conf (DNS $(msg '서버 설정' 'server config'))"
            echo "    - /etc/hosts ($(msg '로컬 호스트 매핑' 'local host mapping'))"
        fi
        ;;
esac

#==============================================================================
# 2. Network route check
#==============================================================================
print_header "2. $(msg '네트워크 경로 확인' 'Network Route Check')"

if command -v ip >/dev/null 2>&1; then
    ROUTE_INFO=$(ip route get "$TARGET_HOST" 2>/dev/null | head -1 || true)
    if [ -n "$ROUTE_INFO" ]; then
        print_ok "$(msg '라우팅 경로가 존재합니다:' 'Route exists:')"
        echo "    ${ROUTE_INFO}"

        # Extract gateway
        GW=$(echo "$ROUTE_INFO" | sed -n 's/.*via \([^ ]*\).*/\1/p' || true)
        SRC=$(echo "$ROUTE_INFO" | sed -n 's/.*src \([^ ]*\).*/\1/p' || true)
        DEV=$(echo "$ROUTE_INFO" | sed -n 's/.*dev \([^ ]*\).*/\1/p' || true)

        [ -n "$GW" ] && print_info "$(msg '게이트웨이' 'Gateway'): ${GW}"
        [ -n "$SRC" ] && print_info "$(msg '출발 IP' 'Source IP'): ${SRC}"
        [ -n "$DEV" ] && print_info "$(msg '네트워크 인터페이스' 'Network Interface'): ${DEV}"
    else
        print_fail "$(msg "${TARGET_HOST}로의 라우팅 경로가 없습니다!" "No route to ${TARGET_HOST}!")"
        OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
    fi
elif command -v route >/dev/null 2>&1; then
    # RHEL 6 fallback
    ROUTE_INFO=$(route -n 2>/dev/null | head -5 || true)
    if [ -n "$ROUTE_INFO" ]; then
        print_info "$(msg '라우팅 테이블:' 'Routing table:')"
        echo "$ROUTE_INFO" | while IFS= read -r line; do
            echo "    ${line}"
        done
    fi
else
    print_warn "$(msg 'ip/route 명령어를 찾을 수 없습니다.' 'ip/route command not found.')"
fi

#==============================================================================
# 3. ICMP Ping test
#==============================================================================
print_header "3. $(msg 'ICMP Ping 테스트' 'ICMP Ping Test')"

if command -v ping >/dev/null 2>&1; then
    # Send 3 pings with timeout
    PING_RESULT=$(ping -c 3 -W "$TIMEOUT" "$TARGET_HOST" 2>&1 || true)
    PING_STATS=$(echo "$PING_RESULT" | grep -E "packets transmitted|loss|rtt|round-trip" || true)

    if echo "$PING_RESULT" | grep -q " 0% packet loss\| 0% loss"; then
        print_ok "$(msg "Ping 성공 (패킷 손실 없음)" "Ping successful (0% packet loss)")"
        # Extract RTT
        RTT=$(echo "$PING_RESULT" | grep -oE "rtt [^=]+ = [0-9.]+" | head -1 || true)
        if [ -z "$RTT" ]; then
            RTT=$(echo "$PING_RESULT" | grep -oE "round-trip [^=]+ = [0-9.]+" | head -1 || true)
        fi
        [ -n "$RTT" ] && print_info "${RTT}"
    elif echo "$PING_RESULT" | grep -q "100% packet loss\|100% loss"; then
        print_warn "$(msg "Ping 실패 (100% 패킷 손실) - 방화벽이 ICMP를 차단하고 있을 수 있음" "Ping failed (100% loss) - ICMP may be blocked by firewall")"
        print_info "$(msg 'ICMP가 차단되어도 TCP/UDP 포트는 접근 가능할 수 있습니다.' 'TCP/UDP port may still be accessible even if ICMP is blocked.')"
    else
        print_warn "$(msg "Ping 부분 손실 발생" "Partial ping loss detected")"
    fi

    if [ -n "$PING_STATS" ]; then
        echo "$PING_STATS" | while IFS= read -r line; do
            echo "    ${line}"
        done
    fi
else
    print_warn "$(msg 'ping 명령어를 찾을 수 없습니다.' 'ping command not found.')"
fi

#==============================================================================
# 4. TCP/UDP port connectivity test
#==============================================================================
print_header "4. $(msg 'TCP/UDP 포트 접속 테스트' 'TCP/UDP Port Connectivity Test')"

CONNECT_OK=false
CONNECT_METHOD=""

if [ "$PROTO" = "tcp" ]; then

    # Method 1: bash /dev/tcp (most portable, no extra tools needed)
    print_info "$(msg '방법 1: /dev/tcp (bash 내장)' 'Method 1: /dev/tcp (bash built-in)')"
    START_TIME=$(date +%s%N 2>/dev/null || date +%s)
    if (echo > /dev/tcp/${TARGET_HOST}/${TARGET_PORT}) 2>/dev/null; then
        END_TIME=$(date +%s%N 2>/dev/null || date +%s)
        print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'TCP 연결 성공' 'TCP connection successful')"
        CONNECT_OK=true
        CONNECT_METHOD="/dev/tcp"
        # Calculate elapsed time if nanoseconds are available
        if echo "$START_TIME" | grep -qE '^[0-9]{10,}$'; then
            ELAPSED=$(( (END_TIME - START_TIME) / 1000000 ))
            print_info "$(msg "응답 시간: ~${ELAPSED}ms" "Response time: ~${ELAPSED}ms")"
        fi
    else
        print_warn "$(msg '연결 실패 또는 타임아웃' 'Connection failed or timed out')"
    fi

    # Method 2: nc / ncat
    if [ "$CONNECT_OK" = "false" ]; then
        if command -v nc >/dev/null 2>&1; then
            print_info "$(msg '방법 2: nc (netcat)' 'Method 2: nc (netcat)')"
            if nc -z -w "$TIMEOUT" "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
                print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (nc)"
                CONNECT_OK=true
                CONNECT_METHOD="nc"
            else
                print_warn "$(msg '연결 실패 또는 타임아웃' 'Connection failed or timed out')"
            fi
        elif command -v ncat >/dev/null 2>&1; then
            print_info "$(msg '방법 2: ncat' 'Method 2: ncat')"
            if ncat -z -w "$TIMEOUT" "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
                print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (ncat)"
                CONNECT_OK=true
                CONNECT_METHOD="ncat"
            else
                print_warn "$(msg '연결 실패 또는 타임아웃' 'Connection failed or timed out')"
            fi
        fi
    fi

    # Method 3: curl (works for any TCP port, not just HTTP)
    if [ "$CONNECT_OK" = "false" ]; then
        if command -v curl >/dev/null 2>&1; then
            print_info "$(msg '방법 3: curl (TCP 연결 시도)' 'Method 3: curl (TCP connect attempt)')"
            CURL_OUTPUT=$(curl -so /dev/null --connect-timeout "$TIMEOUT" "http://${TARGET_HOST}:${TARGET_PORT}" -w "%{http_code}|%{time_connect}" 2>&1 || true)
            CURL_EXIT=$?
            # curl exit 0 or 52(empty reply) or 56(recv failure) means TCP connected
            if [ $CURL_EXIT -eq 0 ] || [ $CURL_EXIT -eq 52 ] || [ $CURL_EXIT -eq 56 ]; then
                CONNECT_TIME=$(echo "$CURL_OUTPUT" | grep -oE '[0-9]+\.[0-9]+$' || true)
                print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (curl)"
                [ -n "$CONNECT_TIME" ] && print_info "$(msg "연결 시간: ${CONNECT_TIME}s" "Connect time: ${CONNECT_TIME}s")"
                CONNECT_OK=true
                CONNECT_METHOD="curl"
            else
                print_warn "$(msg '연결 실패 또는 타임아웃' 'Connection failed or timed out')"
            fi
        fi
    fi

    # Method 4: telnet (very basic, available on most systems)
    if [ "$CONNECT_OK" = "false" ]; then
        if command -v telnet >/dev/null 2>&1; then
            print_info "$(msg '방법 4: telnet' 'Method 4: telnet')"
            TELNET_RESULT=$(echo "" | telnet "$TARGET_HOST" "$TARGET_PORT" 2>&1 &
                TELNET_PID=$!
                sleep "$TIMEOUT"
                kill "$TELNET_PID" 2>/dev/null
                wait "$TELNET_PID" 2>/dev/null
            )
            if echo "$TELNET_RESULT" | grep -qiE "Connected|Escape character"; then
                print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'TCP 연결 성공' 'TCP connection successful') (telnet)"
                CONNECT_OK=true
                CONNECT_METHOD="telnet"
            else
                print_warn "$(msg '연결 실패 또는 타임아웃' 'Connection failed or timed out')"
            fi
        fi
    fi

elif [ "$PROTO" = "udp" ]; then

    print_info "$(msg 'UDP는 비연결 프로토콜이므로 정확한 판정이 어렵습니다.' 'UDP is connectionless; accurate detection is limited.')"

    if command -v nc >/dev/null 2>&1; then
        print_info "$(msg '방법: nc -zu (UDP 포트 접근 테스트)' 'Method: nc -zu (UDP port access test)')"
        if nc -zu -w "$TIMEOUT" "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
            print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'UDP 포트 접근 가능 (또는 응답 없음)' 'UDP port accessible (or no response)')"
            CONNECT_OK=true
            CONNECT_METHOD="nc"
        else
            print_warn "${TARGET_HOST}:${TARGET_PORT} $(msg 'UDP 포트 접근 불가 (ICMP unreachable 수신됨)' 'UDP port unreachable (ICMP unreachable received)')"
        fi
    elif command -v ncat >/dev/null 2>&1; then
        if ncat -zu -w "$TIMEOUT" "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
            print_ok "${TARGET_HOST}:${TARGET_PORT} $(msg 'UDP 포트 접근 가능' 'UDP port accessible')"
            CONNECT_OK=true
            CONNECT_METHOD="ncat"
        else
            print_warn "${TARGET_HOST}:${TARGET_PORT} $(msg 'UDP 포트 접근 불가' 'UDP port unreachable')"
        fi
    else
        print_warn "$(msg 'UDP 테스트에 nc 또는 ncat이 필요합니다.' 'nc or ncat required for UDP testing.')"
    fi
fi

# Final connectivity verdict
echo ""
if [ "$CONNECT_OK" = "true" ]; then
    print_ok "${BOLD}$(msg "최종 결과: ${TARGET_HOST}:${TARGET_PORT}/${PROTO} 접속 가능 (${CONNECT_METHOD})" "Final: ${TARGET_HOST}:${TARGET_PORT}/${PROTO} REACHABLE (${CONNECT_METHOD})")${NC}"
else
    print_fail "${BOLD}$(msg "최종 결과: ${TARGET_HOST}:${TARGET_PORT}/${PROTO} 접속 불가" "Final: ${TARGET_HOST}:${TARGET_PORT}/${PROTO} UNREACHABLE")${NC}"
    OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
fi

#==============================================================================
# 5. Outbound firewall check (local iptables OUTPUT chain)
#==============================================================================
print_header "5. $(msg '아웃바운드 방화벽 확인' 'Outbound Firewall Check')"

if [ "$(id -u)" -eq 0 ]; then
    if command -v iptables >/dev/null 2>&1; then
        OUTPUT_RULES=$(iptables -L OUTPUT -n --line-numbers 2>/dev/null | grep -i "${PROTO}" | grep "${TARGET_PORT}" || true)
        if [ -n "$OUTPUT_RULES" ]; then
            print_info "$(msg "포트 ${TARGET_PORT}/${PROTO} 관련 OUTPUT 규칙:" "OUTPUT rules for port ${TARGET_PORT}/${PROTO}:")"
            echo "$OUTPUT_RULES" | while IFS= read -r rule; do
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
            print_info "$(msg "포트 ${TARGET_PORT}/${PROTO}에 대한 OUTPUT 차단 규칙이 없습니다." "No OUTPUT blocking rules for port ${TARGET_PORT}/${PROTO}.")"
        fi

        OUTPUT_POLICY=$(iptables -L OUTPUT 2>/dev/null | head -1 | awk '{print $4}' | tr -d ')' || echo "unknown")
        case "$OUTPUT_POLICY" in
            DROP|REJECT)
                print_warn "$(msg "OUTPUT 체인 기본 정책: ${OUTPUT_POLICY} (아웃바운드 트래픽이 차단될 수 있음)" "OUTPUT chain default: ${OUTPUT_POLICY} (outbound traffic may be blocked)")"
                OVERALL_ISSUES=$((OVERALL_ISSUES + 1))
                ;;
            *)
                print_info "$(msg "OUTPUT 체인 기본 정책: ${OUTPUT_POLICY}" "OUTPUT chain default policy: ${OUTPUT_POLICY}")"
                ;;
        esac
    fi
else
    print_warn "$(msg 'iptables OUTPUT 규칙 확인에는 root 권한이 필요합니다.' 'Root privileges required to check iptables OUTPUT rules.')"
fi

#==============================================================================
# 6. Traceroute (optional diagnostics)
#==============================================================================
print_header "6. $(msg '경로 추적 (Traceroute)' 'Traceroute Diagnostics')"

TRACE_DONE=false

if command -v traceroute >/dev/null 2>&1; then
    print_info "$(msg '경로 추적 중... (최대 15홉)' 'Tracing route... (max 15 hops)')"
    TRACE_OUTPUT=$(traceroute -m 15 -w 2 "$TARGET_HOST" 2>&1 | head -20 || true)
    if [ -n "$TRACE_OUTPUT" ]; then
        echo "$TRACE_OUTPUT" | while IFS= read -r line; do
            case "$line" in
                *"* * *"*)
                    echo -e "    ${YELLOW}${line}${NC}" ;;
                *)
                    echo "    ${line}" ;;
            esac
        done
        TRACE_DONE=true
    fi
elif command -v tracepath >/dev/null 2>&1; then
    print_info "$(msg '경로 추적 중... (tracepath)' 'Tracing route... (tracepath)')"
    TRACE_OUTPUT=$(tracepath "$TARGET_HOST" 2>&1 | head -20 || true)
    if [ -n "$TRACE_OUTPUT" ]; then
        echo "$TRACE_OUTPUT" | while IFS= read -r line; do
            echo "    ${line}"
        done
        TRACE_DONE=true
    fi
fi

if [ "$TRACE_DONE" = "false" ]; then
    print_info "$(msg 'traceroute/tracepath 명령어를 찾을 수 없습니다. 건너뜁니다.' 'traceroute/tracepath not found. Skipping.')"
    print_info "$(msg '설치' 'Install'): sudo yum install traceroute"
fi

#==============================================================================
# 7. Troubleshooting guide
#==============================================================================
if [ "$CONNECT_OK" = "false" ]; then
    print_header "7. $(msg '문제 해결 가이드' 'Troubleshooting Guide')"

    echo -e "  ${BOLD}$(msg '접속 실패 원인 체크리스트:' 'Connection failure checklist:')${NC}"
    echo ""
    echo -e "  $(msg '1. 대상 서버에서 서비스가 실행 중인지 확인' '1. Verify service is running on target server')"
    echo -e "     ${YELLOW}ssh ${TARGET_HOST} \"ss -tlnp | grep :${TARGET_PORT}\"${NC}"
    echo ""
    echo -e "  $(msg '2. 대상 서버 방화벽에서 포트가 허용되어 있는지 확인' '2. Check target server firewall allows the port')"
    echo -e "     ${YELLOW}ssh ${TARGET_HOST} \"sudo firewall-cmd --query-port=${TARGET_PORT}/${PROTO}\"${NC}"
    echo ""
    echo -e "  $(msg '3. 중간 네트워크 장비(라우터/스위치/IDS) 확인' '3. Check intermediate network devices (router/switch/IDS)')"
    echo ""
    echo -e "  $(msg '4. 로컬 방화벽 아웃바운드 규칙 확인' '4. Check local outbound firewall rules')"
    echo -e "     ${YELLOW}sudo iptables -L OUTPUT -n | grep ${TARGET_PORT}${NC}"
    echo ""
    echo -e "  $(msg '5. SELinux가 아웃바운드 연결을 차단하는지 확인' '5. Check if SELinux blocks outbound connections')"
    echo -e "     ${YELLOW}sudo ausearch -m avc -ts recent | grep ${TARGET_PORT}${NC}"
    echo ""
    echo -e "  $(msg '6. 로컬 포트 점검 스크립트로 대상 서버에서 직접 확인' '6. Run local port check directly on target server')"
    echo -e "     ${YELLOW}ssh ${TARGET_HOST} \"sudo ./check_port.sh ${TARGET_PORT} ${PROTO}\"${NC}"
fi

#==============================================================================
# Summary
#==============================================================================
print_header "$(msg '종합 점검 결과' 'Summary')"

echo -e "  $(msg '대상' 'Target'):  ${BOLD}${TARGET_HOST}:${TARGET_PORT}/${PROTO}${NC}"
echo ""

if [ "$OVERALL_ISSUES" -eq 0 ]; then
    print_ok "$(msg '모든 점검 항목 통과 - 원격 포트 접속 가능' 'All checks PASSED - remote port is reachable')"
else
    print_fail "$(msg "${OVERALL_ISSUES}개 항목에서 문제 발견" "${OVERALL_ISSUES} issue(s) found")"
    echo ""
    print_info "$(msg '위의 각 섹션에서 [FAIL] 또는 [WARN] 표시된 항목을 확인하세요.' 'Review [FAIL] and [WARN] items in the sections above.')"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  $(msg '점검 완료' 'Check completed'): $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

exit $OVERALL_ISSUES
