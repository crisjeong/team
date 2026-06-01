# OCS 시스템 (Linux) JVM GC 로그 설정 가이드

> **대상 환경**: Linux + JDK 1.8 (Java 8)  
> **목적**: CPU 10% → 30% 급등 현상의 원인이 GC인지 확인

---

## 1. GC 로그 JVM 옵션

### 1.1 권장 옵션 (전체)

```
-verbose:gc
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-XX:+PrintGCTimeStamps
-XX:+PrintHeapAtGC
-XX:+PrintGCCause
-Xloggc:/opt/ocs/logs/gc.log
-XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=10
-XX:GCLogFileSize=50M
```

### 1.2 각 옵션 설명

| 옵션 | 설명 | 필수 여부 |
|---|---|---|
| `-verbose:gc` | GC 발생 시 기본 정보 출력 | ✅ 필수 |
| `-XX:+PrintGCDetails` | GC 유형, 영역별 크기 변화, 소요시간 상세 출력 | ✅ 필수 |
| `-XX:+PrintGCDateStamps` | 날짜+시간 형식 타임스탬프 (2026-06-01T22:49:56) | ✅ 필수 |
| `-XX:+PrintGCTimeStamps` | JVM 시작 이후 경과 시간(초) | ✅ 필수 |
| `-XX:+PrintHeapAtGC` | GC 전후 힙 영역별 상세 상태 | 🟡 권장 |
| `-XX:+PrintGCCause` | GC가 발생한 원인 출력 | 🟡 권장 |
| `-Xloggc:<파일경로>` | GC 로그를 파일로 저장 | ✅ 필수 |
| `-XX:+UseGCLogFileRotation` | 로그 파일 로테이션 활성화 | 🟡 권장 |
| `-XX:NumberOfGCLogFiles=10` | 보관할 로그 파일 수 | 🟡 권장 |
| `-XX:GCLogFileSize=50M` | 로그 파일 하나의 최대 크기 | 🟡 권장 |

> [!TIP]
> GC 로그는 **성능에 거의 영향을 주지 않습니다** (1~2% 미만). 프로덕션 환경에서도 안전하게 활성화할 수 있습니다.

---

## 2. 적용 방법

### 2.1 방법 A: 쉘 스크립트(.sh)로 실행하는 경우

OCS를 쉘 스크립트로 실행한다면, `java` 명령에 옵션을 추가합니다.

```bash
#!/bin/bash
# === OCS 실행 스크립트 (start_ocs.sh) ===

JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
OCS_HOME=/opt/ocs
LOG_DIR=${OCS_HOME}/logs

# 로그 디렉토리 생성 (없으면)
mkdir -p ${LOG_DIR}

# --- GC 로그 옵션 ---
GC_OPTS="-verbose:gc"
GC_OPTS="${GC_OPTS} -XX:+PrintGCDetails"
GC_OPTS="${GC_OPTS} -XX:+PrintGCDateStamps"
GC_OPTS="${GC_OPTS} -XX:+PrintGCTimeStamps"
GC_OPTS="${GC_OPTS} -XX:+PrintHeapAtGC"
GC_OPTS="${GC_OPTS} -XX:+PrintGCCause"
GC_OPTS="${GC_OPTS} -Xloggc:${LOG_DIR}/gc.log"
GC_OPTS="${GC_OPTS} -XX:+UseGCLogFileRotation"
GC_OPTS="${GC_OPTS} -XX:NumberOfGCLogFiles=10"
GC_OPTS="${GC_OPTS} -XX:GCLogFileSize=50M"

# --- 기존 JVM 옵션 ---
JAVA_OPTS="-Xms512m -Xmx1024m"

# --- 실행 ---
${JAVA_HOME}/bin/java ${JAVA_OPTS} ${GC_OPTS} -jar ${OCS_HOME}/ocs-server.jar &

echo "OCS started. PID: $!"
echo "GC log: ${LOG_DIR}/gc.log"
```

```bash
# 실행
chmod +x /opt/ocs/start_ocs.sh
/opt/ocs/start_ocs.sh
```

### 2.2 방법 B: systemd 서비스로 등록된 경우

#### `/etc/systemd/system/ocs.service` 수정

```ini
[Unit]
Description=OCS Server
After=network.target

[Service]
Type=simple
User=ocs
Group=ocs
WorkingDirectory=/opt/ocs

# JAVA_OPTS에 GC 로그 옵션 포함
Environment="JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk"
Environment="JAVA_OPTS=-Xms512m -Xmx1024m -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+PrintHeapAtGC -XX:+PrintGCCause -Xloggc:/opt/ocs/logs/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=50M"

ExecStart=/usr/lib/jvm/java-1.8.0-openjdk/bin/java $JAVA_OPTS -jar /opt/ocs/ocs-server.jar
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
# 서비스 재시작
sudo systemctl daemon-reload
sudo systemctl restart ocs

# 상태 확인
sudo systemctl status ocs
```

#### 또는 별도 환경 파일 사용 (더 깔끔한 방식)

`/etc/sysconfig/ocs` 또는 `/opt/ocs/ocs.env` 파일 생성:

```bash
# /opt/ocs/ocs.env
JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
JAVA_OPTS=-Xms512m -Xmx1024m
GC_OPTS=-verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+PrintHeapAtGC -XX:+PrintGCCause -Xloggc:/opt/ocs/logs/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=50M
```

서비스 파일에서 참조:

```ini
[Service]
EnvironmentFile=/opt/ocs/ocs.env
ExecStart=/usr/lib/jvm/java-1.8.0-openjdk/bin/java $JAVA_OPTS $GC_OPTS -jar /opt/ocs/ocs-server.jar
```

### 2.3 방법 C: 환경변수로 설정 (스크립트 수정 없이)

```bash
# 실행 전 환경변수 설정
export JAVA_TOOL_OPTIONS="-verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+PrintGCCause -Xloggc:/opt/ocs/logs/gc.log"

# 이후 OCS 실행 (JAVA_TOOL_OPTIONS가 자동 적용됨)
java -jar /opt/ocs/ocs-server.jar
```

> [!NOTE]
> `JAVA_TOOL_OPTIONS`는 JVM이 시작될 때 자동으로 읽는 환경변수입니다. 기존 실행 스크립트를 수정하기 어려운 경우에 유용합니다. 단, JVM 시작 시 `Picked up JAVA_TOOL_OPTIONS: ...` 메시지가 stderr에 출력됩니다.

---

## 3. GC 로그 출력 예시 및 읽는 법

### 3.1 Minor GC (정상 상태)

```
2026-06-01T10:00:05.123+0900: 3600.456: [GC (Allocation Failure)
    [PSYoungGen: 153600K->12800K(179200K)]
    204800K->64000K(716800K), 0.0123456 secs]
    [Times: user=0.03 sys=0.00, real=0.01 secs]
```

```
해석:
├─ 시각: 2026-06-01 10:00:05
├─ JVM 시작 후: 3600초 (1시간)
├─ GC 유형: GC (Minor GC)
├─ 원인: Allocation Failure (Young Gen 부족)
├─ Young Gen: 153,600K → 12,800K (179,200K 중)  ← 잘 회수됨 ✅
├─ 전체 힙: 204,800K → 64,000K (716,800K 중)
├─ 소요시간: 0.012초 (12ms) ← 정상 ✅
└─ 판정: 정상. Young Gen이 효과적으로 회수됨
```

### 3.2 Full GC (⚠️ CPU 급등 시 이것이 보임)

```
2026-06-01T14:30:22.789+0900: 19822.123: [Full GC (Ergonomics)
    [PSYoungGen: 12800K->0K(179200K)]
    [ParOldGen: 520000K->495000K(537600K)]     ← ⚠️ 거의 안 줄어듦!
    532800K->495000K(716800K), 1.2345678 secs]
    [Times: user=3.50 sys=0.10, real=1.23 secs]
```

```
해석:
├─ 시각: 2026-06-01 14:30:22
├─ JVM 시작 후: 19,822초 (약 5.5시간) ← 시간 경과 후 발생!
├─ GC 유형: Full GC ← ⚠️ 전체 힙 스캔
├─ 원인: Ergonomics (JVM이 자동 판단)
├─ Old Gen: 520,000K → 495,000K  ← ⚠️ 25MB만 회수 (거의 줄지 않음!)
├─ 전체 힙: 532,800K → 495,000K
├─ 소요시간: 1.23초 ← 🔴 매우 느림! (Minor GC의 100배)
├─ CPU 시간: user=3.50초 ← 🔴 멀티코어에서 총 3.5초 CPU 사용
└─ 판정: 🔴 비정상. Old Gen 누수 의심 + CPU 급등 원인
```

> [!CAUTION]
> **Full GC에서 Old Gen이 거의 줄어들지 않으면** → **메모리 누수**입니다.  
> **Full GC가 수 초~수십 초 간격으로 반복되면** → **CPU 30% 급등의 직접 원인**입니다.

### 3.3 정상 vs 비정상 비교

| 항목 | 정상 (CPU 10%) | 비정상 (CPU 30%) |
|---|---|---|
| GC 유형 | Minor GC 위주 | **Full GC 빈발** |
| Minor GC 소요시간 | 5~20ms | 변화 없음 |
| Full GC 소요시간 | 거의 발생 안 함 | **0.5~3초** |
| Full GC 빈도 | - | **수 초~수십 초 간격** |
| Old Gen 사용량 | 안정적 (30~50%) | **80~95% 고정** |
| Old Gen GC 후 회수율 | - | **거의 줄지 않음** |

---

## 4. GC 로그 분석 방법

### 4.1 명령어로 빠르게 확인

```bash
# 1. Full GC 발생 횟수 확인
grep -c "Full GC" /opt/ocs/logs/gc.log
```

```bash
# 2. Full GC 발생 시각 확인 (CPU 급등 시각과 대조)
grep "Full GC" /opt/ocs/logs/gc.log | awk '{print $1}'
```

```bash
# 3. Full GC 소요시간만 추출
grep "Full GC" /opt/ocs/logs/gc.log | grep -oP '[\d.]+ secs\]' | sort -n
```

```bash
# 4. GC 유형별 빈도 요약
echo "=== Minor GC ==="
grep -c "\[GC (" /opt/ocs/logs/gc.log

echo "=== Full GC ==="
grep -c "\[Full GC" /opt/ocs/logs/gc.log
```

```bash
# 5. 시간대별 Full GC 빈도 (시간당 발생 횟수)
grep "Full GC" /opt/ocs/logs/gc.log | awk '{print substr($1,1,13)}' | uniq -c
```

```bash
# 6. Old Gen 사용량 추이 (Full GC 라인에서 추출)
grep "Full GC" /opt/ocs/logs/gc.log | grep -oP 'ParOldGen: \K\d+K->\d+K'
```

```bash
# 7. 실시간 GC 모니터링 (OCS 실행 중)
tail -f /opt/ocs/logs/gc.log | grep --line-buffered "Full GC"
```

### 4.2 실행 중인 OCS의 GC 상태 실시간 확인

```bash
# OCS 프로세스 PID 확인
ps -ef | grep ocs-server | grep -v grep
# 또는
jps -l | grep ocs

# GC 통계 실시간 출력 (1초 간격, 30회)
jstat -gcutil <PID> 1000 30
```

`jstat -gcutil` 출력 예시:

```
  S0     S1     E      O      M     CCS    YGC   YGCT    FGC   FGCT     GCT
  0.00  99.12  45.67  87.34  95.12  92.45  1234  12.345   56   78.901  91.246
```

| 컬럼 | 의미 | 주목 포인트 |
|---|---|---|
| **O** | Old Gen 사용률 (%) | 🔴 **80% 이상이면 위험** |
| **FGC** | Full GC 누적 횟수 | 🔴 **계속 증가하면 문제** |
| **FGCT** | Full GC 누적 소요시간(초) | 🔴 **빠르게 증가하면 CPU 급등 원인** |
| YGC | Young GC 누적 횟수 | 참고 |
| YGCT | Young GC 누적 소요시간(초) | 참고 |

> [!IMPORTANT]
> **`jstat`은 GC 로그를 설정하지 않아도 즉시 사용 가능합니다.** 지금 바로 아래 명령으로 확인할 수 있습니다:
> ```bash
> # PID 확인 후 5초 간격으로 GC 현황 출력
> jstat -gcutil $(jps -l | grep ocs | awk '{print $1}') 5000
> ```

### 4.3 무료 분석 도구 활용

#### GCViewer (권장 — 오프라인 분석)

```bash
# 다운로드 (GitHub Releases)
wget https://github.com/chewiebug/GCViewer/releases/download/1.36/gcviewer-1.36.jar

# 실행 (GUI 환경 또는 로컬 PC에서)
java -jar gcviewer-1.36.jar /opt/ocs/logs/gc.log
```

| 확인 항목 | 위치 |
|---|---|
| Full GC 빈도 그래프 | 메인 차트의 빨간 세로선 |
| Heap 사용량 추이 | 파란 영역 그래프 |
| GC Pause 시간 | Summary 탭 |
| Old Gen 증가 추세 | Tenured Gen 영역 |

#### GCEasy (온라인 — 가장 쉬움)

```
접속: https://gceasy.io
사용법: gc.log 파일을 업로드하면 자동 분석 리포트 생성
```

> [!WARNING]
> GCEasy는 온라인 서비스이므로, **사내 보안 정책을 확인** 후 업로드하세요. 민감 환경이라면 GCViewer(오프라인)를 사용하세요.

#### VisualVM (원격 실시간 모니터링)

OCS 서버에 JMX를 열어 원격 모니터링:

```bash
# OCS 실행 시 JMX 옵션 추가
JAVA_OPTS="${JAVA_OPTS} -Dcom.sun.management.jmxremote"
JAVA_OPTS="${JAVA_OPTS} -Dcom.sun.management.jmxremote.port=9010"
JAVA_OPTS="${JAVA_OPTS} -Dcom.sun.management.jmxremote.ssl=false"
JAVA_OPTS="${JAVA_OPTS} -Dcom.sun.management.jmxremote.authenticate=false"
JAVA_OPTS="${JAVA_OPTS} -Djava.rmi.server.hostname=<OCS서버IP>"
```

로컬 PC에서 VisualVM 실행 → `<OCS서버IP>:9010`으로 연결

> [!WARNING]
> JMX `authenticate=false`는 **개발/테스트 환경에서만** 사용하세요. 프로덕션에서는 인증을 활성화하거나 방화벽으로 접근을 제한해야 합니다.

---

## 5. 확인 체크리스트

GC 로그를 수집한 후 아래 순서로 확인합니다:

```
□ 1. Full GC가 발생하는가?
     → Yes: 2번으로
     → No: GC가 원인이 아님, 다른 요인 조사 필요

□ 2. Full GC 시작 시각이 CPU 급등 시각과 일치하는가?
     → Yes: GC가 CPU 급등의 원인 확정 → 3번으로
     → No: 시각 불일치 시 다른 요인 조사 필요

□ 3. Full GC 후 Old Gen 사용량이 크게 줄어드는가?
     → Yes: 임시 객체 과다 (String.format 영향) → Lookup Table 교체로 해결
     → No: 메모리 누수 존재 → 힙 덤프 분석 + 코드 리뷰 필요

□ 4. Full GC 간격은?
     → 수 분 이상: 경미한 수준
     → 수 초~수십 초: 심각 → 즉시 조치 필요
```

> [!IMPORTANT]
> **CPU 급등과 Full GC의 시각이 일치하면**, 원인이 확정됩니다. 이 경우 `String.format()` → Lookup Table 교체 + Guard Clause 적용이 **근본 해결책**입니다.

---

## 6. 추가: 현재 사용 중인 GC 알고리즘 확인

```bash
# OCS 프로세스의 JVM 플래그 확인
jps -l                                          # OCS PID 확인
jinfo -flags $(jps -l | grep ocs | awk '{print $1}')   # JVM 플래그 전체
jinfo -flag UseG1GC <PID>                       # G1GC 사용 여부
jinfo -flag UseParallelGC <PID>                 # Parallel GC 사용 여부
```

| GC 알고리즘 | JDK 8 기본 | Full GC 특성 |
|---|---|---|
| **Parallel GC** (기본) | ✅ | Full GC 시 전체 Stop-the-World, CPU 급등 가능성 높음 |
| **G1 GC** | 수동 설정 | Mixed GC로 분산 처리, 급등 완화 가능 |
| **CMS** | 수동 설정 | Concurrent 수집으로 pause 감소, 단 CPU 사용량은 높을 수 있음 |

> [!TIP]
> JDK 1.8 기본값인 **Parallel GC**는 Full GC 시 모든 애플리케이션 스레드를 정지시키므로, CPU 급등 + 응답 지연이 동시에 발생합니다. GC 알고리즘 변경(`-XX:+UseG1GC`)도 검토해 볼 수 있습니다.

---

## 7. 빠른 시작 — 지금 바로 확인하기

GC 로그 설정 없이 **지금 즉시** OCS의 GC 상태를 확인하려면:

```bash
# 1단계: OCS PID 확인
OCS_PID=$(jps -l | grep ocs | awk '{print $1}')
echo "OCS PID: ${OCS_PID}"

# 2단계: GC 현황 5초 간격 출력 (Ctrl+C로 중지)
jstat -gcutil ${OCS_PID} 5000

# 3단계: Old Gen(O)이 80% 이상이고, FGC가 계속 증가하면
#        → Full GC가 CPU 급등의 원인
```

> [!TIP]
> `jstat`은 **JVM 옵션 변경이나 재시작 없이** 즉시 실행 가능합니다. CPU 급등이 발생한 상태에서 바로 확인해 보세요.
