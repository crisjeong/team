# Java JDK 1.8 — CPU 상승 원인 종합 점검 가이드

> JDK 1.8 기반 소스코드에서 CPU 상승의 원인이 되는 17가지 주요 패턴과 진단 방법을 정리한 문서입니다.

---

## 1. 🔄 무한 루프 / Busy Waiting

가장 흔한 CPU 상승 원인입니다.

```java
// ❌ Bad: CPU를 100% 점유하는 busy wait
while (!flag) {
    // 아무 것도 하지 않고 계속 루프
}

// ❌ Bad: sleep 없는 polling
while (queue.isEmpty()) {
    continue;
}

// ✅ Good: 적절한 대기
while (!flag) {
    Thread.sleep(100); // 또는 wait/notify, Lock/Condition 사용
}
```

**점검 포인트:**
- `while(true)`, `for(;;)` 루프에서 `sleep`, `wait`, `await`, `take` 등 블로킹 호출 없이 반복하는 코드
- `Thread.yield()` 만으로 대기하는 경우 (CPU 양보를 보장하지 않음)

---

## 2. 🔒 Lock Contention / Synchronized 경합

```java
// ❌ Bad: 넓은 범위의 synchronized
public synchronized void processAll(List<Item> items) {
    for (Item item : items) {
        // 긴 작업...
    }
}

// ❌ Bad: 빈번한 lock 경합으로 spin-wait 발생
synchronized (sharedLock) {
    // 짧지만 매우 자주 호출되는 코드
}
```

**점검 포인트:**
- `synchronized` 블록이 넓은 범위를 감싸고 있는 경우
- 여러 스레드가 동일한 lock을 빈번하게 획득/해제하는 경우
- `ConcurrentHashMap` 대신 `Hashtable` 또는 `Collections.synchronizedMap()` 사용

---

## 3. 🧵 Thread 과다 생성

```java
// ❌ Bad: 매 요청마다 새 Thread 생성
public void handleRequest(Request req) {
    new Thread(() -> process(req)).start();
}

// ✅ Good: ThreadPool 사용
ExecutorService executor = Executors.newFixedThreadPool(
    Runtime.getRuntime().availableProcessors()
);
```

**점검 포인트:**
- `new Thread()` 직접 생성이 반복적으로 일어나는 경우
- `ThreadPoolExecutor`의 pool size가 과도하게 큰 경우
- Thread가 종료되지 않고 계속 누적되는 경우

---

## 4. 📝 비효율적인 String 처리

```java
// ❌ Bad: 루프 내 String 연결 (매번 새 객체 생성)
String result = "";
for (int i = 0; i < 100000; i++) {
    result += data[i]; // O(n²) 복잡도
}

// ✅ Good: StringBuilder 사용
StringBuilder sb = new StringBuilder();
for (int i = 0; i < 100000; i++) {
    sb.append(data[i]);
}
```

**점검 포인트:**
- 루프 안에서 `+` 연산자로 문자열 연결
- 대량 데이터에 대한 `String.split()`, 정규식 반복 사용

---

## 5. 🔍 정규식 (Regex) 남용

```java
// ❌ Bad: 매번 Pattern 컴파일
for (String line : lines) {
    if (line.matches("complex-regex-pattern.*")) { // 내부에서 매번 compile
        // ...
    }
}

// ✅ Good: Pattern 미리 컴파일
private static final Pattern PATTERN = Pattern.compile("complex-regex-pattern.*");
for (String line : lines) {
    if (PATTERN.matcher(line).matches()) {
        // ...
    }
}
```

**점검 포인트:**
- 루프 안에서 `String.matches()`, `String.replaceAll()`, `String.split()` 반복 호출
- **Catastrophic Backtracking** 가능한 정규식 패턴 (예: `(a+)+`, `(a|aa)+`)

---

## 6. 🗂️ 비효율적인 컬렉션 사용

```java
// ❌ Bad: 대량 데이터에서 List로 contains 검색 → O(n)
List<String> list = new ArrayList<>(1000000);
if (list.contains(target)) { ... }

// ✅ Good: HashSet 사용 → O(1)
Set<String> set = new HashSet<>(1000000);
if (set.contains(target)) { ... }
```

**점검 포인트:**
- 대용량 `ArrayList`에 대한 `contains()`, `indexOf()` 호출
- `HashMap`의 key에 `hashCode()`가 비효율적인 객체 사용 (해시 충돌 다발)
- 불필요한 `Collections.sort()` 반복 호출

---

## 7. 💾 GC (Garbage Collection) 압박

```java
// ❌ Bad: 대량의 단기 객체 생성
for (int i = 0; i < 1000000; i++) {
    byte[] buffer = new byte[1024]; // 매번 새 버퍼 할당
    process(buffer);
}

// ❌ Bad: Autoboxing 반복
Map<Integer, Integer> map = new HashMap<>();
for (int i = 0; i < 1000000; i++) {
    map.put(i, i * 2); // int → Integer autoboxing
}
```

**점검 포인트:**
- 루프 안에서 대량의 임시 객체 생성
- `Integer`, `Long` 등 wrapper 클래스의 과도한 autoboxing
- `finalize()` 메서드를 오버라이드한 클래스 (JDK 8에서 GC 지연 유발)

---

## 8. 🌐 I/O 기본

```java
// ❌ Bad: 동기 I/O를 busy-wait로 체크
while (socket.getInputStream().available() == 0) {
    // CPU 소모하며 대기
}

// ❌ Bad: timeout 없는 HTTP 호출을 retry 루프에서 반복
while (true) {
    try {
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        // timeout 미설정...
    } catch (Exception e) {
        continue; // 즉시 재시도 → CPU 폭주
    }
}
```

**점검 포인트:**
- Connection/Read timeout 미설정
- 실패 시 backoff 없는 무한 retry
- 버퍼 미사용 I/O (`BufferedInputStream` 없이 byte 단위 읽기)

---

## 9. 🛠️ 실전 진단 도구 및 방법

| 방법 | 명령어 / 도구 | 용도 |
|------|--------------|------|
| **Thread Dump** | `jstack <pid>` | CPU를 점유 중인 스레드와 코드 위치 파악 |
| **CPU Profiling** | VisualVM, JProfiler, async-profiler | 메서드별 CPU 사용 시간 분석 |
| **GC 로그** | `-XX:+PrintGCDetails -XX:+PrintGCTimeStamps` | GC 빈도와 소요 시간 확인 |
| **Thread 상태** | `jcmd <pid> Thread.print` | 스레드 상태 확인 (RUNNABLE이 과다한지) |
| **Heap 분석** | `jmap -heap <pid>` | 메모리 사용 현황 및 GC 압박 확인 |

### 빠른 진단 순서

1. **`top -H -p <pid>`** (Linux)로 CPU를 많이 쓰는 스레드 ID 확인
2. **`jstack <pid>`**로 해당 스레드가 실행 중인 코드 위치 확인
3. 해당 코드에서 위의 패턴들을 점검

---

## 10. 🗄️ DB / JDBC 관련

### 10-1. Connection Pool 고갈로 인한 Spin Wait

```java
// ❌ Bad: 커넥션 풀 부족 → getConnection()에서 대기/재시도 폭주
while (true) {
    try {
        Connection conn = dataSource.getConnection(); // pool 고갈 시 timeout
        break;
    } catch (SQLException e) {
        // backoff 없이 즉시 재시도 → CPU 폭주
    }
}
```

**점검 포인트:**
- Connection Pool 크기 (`maxActive`, `maximumPoolSize`)가 동시 요청 대비 너무 작은 경우
- `getConnection()` timeout 미설정 → 내부적으로 busy-wait 발생 가능
- Connection 누수 (`close()` 미호출) → 풀 고갈 → 대기 스레드 폭주

### 10-2. 비효율적인 쿼리로 인한 대량 데이터 처리

```java
// ❌ Bad: 전체 결과를 메모리에 로드
ResultSet rs = stmt.executeQuery("SELECT * FROM huge_table"); // 수백만 행
List<Record> records = new ArrayList<>();
while (rs.next()) {
    records.add(mapToRecord(rs)); // CPU + 메모리 동시 압박
}

// ✅ Good: fetchSize 설정 + 스트리밍 처리
stmt.setFetchSize(100);
ResultSet rs = stmt.executeQuery("SELECT * FROM huge_table WHERE condition = ?");
while (rs.next()) {
    processSingle(rs); // 건건 처리
}
```

**점검 포인트:**
- `setFetchSize()` 미설정 → JDBC 드라이버 기본값으로 전체 로드 (Oracle: 10, MySQL: 전체)
- **N+1 쿼리 문제**: 루프 안에서 반복적으로 DB 호출
- `SELECT *` 남용 → 불필요한 컬럼 데이터 직렬화/역직렬화에 CPU 소모

### 10-3. N+1 쿼리 패턴

```java
// ❌ Bad: 대표적인 N+1 문제
List<Order> orders = orderDao.findAll(); // 1번 쿼리
for (Order order : orders) {
    Customer c = customerDao.findById(order.getCustomerId()); // N번 쿼리
    order.setCustomerName(c.getName());
}

// ✅ Good: JOIN 또는 IN 절로 한 번에 조회
List<Order> orders = orderDao.findAllWithCustomer(); // JOIN 1번
```

### 10-4. PreparedStatement 미사용

```java
// ❌ Bad: 매번 SQL 파싱 → DB와 애플리케이션 양쪽 CPU 소모
for (String id : ids) {
    Statement stmt = conn.createStatement();
    ResultSet rs = stmt.executeQuery(
        "SELECT * FROM users WHERE id = '" + id + "'"
    );
    // SQL Injection 위험 + 매번 파싱
}

// ✅ Good: PreparedStatement 재사용
PreparedStatement pstmt = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
for (String id : ids) {
    pstmt.setString(1, id);
    ResultSet rs = pstmt.executeQuery();
}
```

---

## 11. 🌐 Network / HTTP 관련

### 11-1. Timeout 미설정

```java
// ❌ Bad: timeout 없는 HTTP 호출
HttpURLConnection conn = (HttpURLConnection) url.openConnection();
// connectTimeout, readTimeout 미설정 → 무한 대기 후 스레드 누적

// ✅ Good: 반드시 timeout 설정
HttpURLConnection conn = (HttpURLConnection) url.openConnection();
conn.setConnectTimeout(3000);  // 3초
conn.setReadTimeout(5000);     // 5초
```

**점검 포인트:**
- `HttpURLConnection`, `Socket`, `HttpClient` 등에서 timeout 미설정
- 외부 API 장애 시 스레드가 무한 대기 → 스레드 풀 고갈 → 새 스레드 생성 폭주

### 11-2. DNS Lookup 캐싱 문제

```java
// JDK 1.8 기본: 보안 매니저 있으면 DNS 영구 캐싱
// 매번 DNS 조회가 필요한 경우 networkaddress.cache.ttl 설정 필요
// 반대로 캐싱이 안 되면 매 요청마다 DNS 조회 → 지연 + 스레드 적체
```

**점검 포인트:**
- `java.security` 파일의 `networkaddress.cache.ttl` 설정 확인
- DNS 조회 실패 시 negative cache TTL (`networkaddress.cache.negative.ttl`)

### 11-3. HTTP Connection Pool 미관리

```java
// ❌ Bad: 매 요청마다 새 연결 → TCP handshake 반복
for (String url : urls) {
    HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
    // 사용 후 disconnect → 연결 재사용 불가
    conn.disconnect();
}

// ✅ Good: Apache HttpClient Connection Pool 사용
PoolingHttpClientConnectionManager cm = new PoolingHttpClientConnectionManager();
cm.setMaxTotal(200);
cm.setDefaultMaxPerRoute(20);
CloseableHttpClient client = HttpClients.custom()
    .setConnectionManager(cm)
    .build();
```

---

## 12. 📋 Logging 관련

### 12-1. 과도한 로깅

```java
// ❌ Bad: 고빈도 경로에서 DEBUG 로깅 + 문자열 연결
for (Item item : largeList) {
    logger.debug("Processing item: " + item.toString() + " with data: " + item.getData());
    // DEBUG가 꺼져 있어도 문자열 연결은 실행됨!
}

// ✅ Good: 파라미터화된 로깅
for (Item item : largeList) {
    logger.debug("Processing item: {} with data: {}", item.getId(), item.getData());
    // DEBUG가 꺼져 있으면 문자열 생성 자체를 안 함
}
```

### 12-2. 로그 파일 I/O 병목

**점검 포인트:**
- Log4j 1.x → 2.x 마이그레이션 여부 (1.x는 synchronized 기반)
- `AsyncAppender` 사용 여부
- 로그 레벨이 운영 환경에서 `DEBUG`/`TRACE`로 설정되어 있지 않은지

---

## 13. 🔄 직렬화 / 역직렬화 (Serialization)

```java
// ❌ Bad: 대량 데이터의 반복적 JSON 직렬화
for (Record record : records) {
    String json = new ObjectMapper().writeValueAsString(record);
    // ObjectMapper를 매번 생성 → 내부 캐시 재구축에 CPU 소모
}

// ✅ Good: ObjectMapper 싱글턴 재사용
private static final ObjectMapper MAPPER = new ObjectMapper();
for (Record record : records) {
    String json = MAPPER.writeValueAsString(record);
}
```

**점검 포인트:**
- `ObjectMapper`, `Gson`, `JAXBContext` 등을 매번 새로 생성하는 경우
- Java 기본 `Serializable` 직렬화는 Reflection 기반 → CPU 비효율
- XML 파싱 (`DocumentBuilder`, `SAXParser`) 반복 생성

---

## 14. ⏰ Scheduler / Timer 관련

```java
// ❌ Bad: 너무 짧은 간격의 스케줄링
ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(10);
scheduler.scheduleAtFixedRate(() -> {
    checkStatus(); // 무거운 작업
}, 0, 10, TimeUnit.MILLISECONDS); // 10ms마다 실행!

// ❌ Bad: Timer 작업에서 예외 발생 → Timer 스레드 죽음 → 재생성 반복
Timer timer = new Timer();
timer.scheduleAtFixedRate(new TimerTask() {
    public void run() {
        riskyOperation(); // 예외 발생 시 Timer 전체 중단
    }
}, 0, 1000);
```

**점검 포인트:**
- `scheduleAtFixedRate` 간격이 비정상적으로 짧은 경우
- 작업 실행 시간이 스케줄 간격보다 긴 경우 → 작업 누적
- `@Scheduled` (Spring) 어노테이션의 `fixedRate` vs `fixedDelay` 혼동

---

## 15. 🔐 암호화 / 해싱

```java
// ❌ Bad: 매 요청마다 SecureRandom 초기화
public String generateToken() {
    SecureRandom random = new SecureRandom(); // 시드 초기화에 CPU 소모
    // ...
}

// ❌ Bad: 과도한 bcrypt 라운드
BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(15); // strength 15는 매우 느림
```

**점검 포인트:**
- `SecureRandom` 반복 인스턴스 생성 (특히 Linux의 `/dev/random` 블로킹)
- TLS/SSL handshake 빈번 발생 (keep-alive 미설정)
- 비밀번호 해싱 cost factor가 과도한 경우

---

## 16. 🧮 Reflection / Dynamic Proxy

```java
// ❌ Bad: 고빈도 경로에서 Reflection 사용
for (Object obj : objects) {
    Method method = obj.getClass().getMethod("process"); // 매번 조회
    method.invoke(obj);
}

// ✅ Good: Method 캐싱
private static final Map<Class<?>, Method> METHOD_CACHE = new ConcurrentHashMap<>();
Method method = METHOD_CACHE.computeIfAbsent(obj.getClass(),
    clz -> clz.getMethod("process"));
method.invoke(obj);
```

**점검 포인트:**
- `Class.forName()`, `getMethod()`, `getDeclaredField()` 반복 호출
- Spring AOP Proxy가 과도하게 적용된 경우 (매 호출마다 intercept 체인)
- `java.beans.Introspector` 사용 시 캐시 미활용

---

## 17. 🗺️ JDK 1.8 특화 이슈

| 이슈 | 설명 |
|------|------|
| **`HashMap` 해시 충돌** | JDK 8에서 treeify 임계값(8) 이상 충돌 시 Red-Black Tree 변환 — 나쁜 `hashCode()`는 여전히 성능 저하 |
| **`ConcurrentHashMap.computeIfAbsent` 버그** | JDK 8의 재귀 호출 시 데드락 (JDK-8062841) |
| **`Stream` 과도한 사용** | 단순 루프 대비 오버헤드 존재, 특히 `parallel()` 스트림의 `ForkJoinPool` 경합 |
| **Metaspace 누수** | 동적 클래스 생성 (Groovy, CGLIB) 시 Metaspace 증가 → Full GC 빈발 |
| **`LocalDateTime.now()` 반복 호출** | Clock 인스턴스 생성 오버헤드 (극단적 고빈도 시) |

---

## 📊 종합 점검 체크리스트

### 코드 패턴
- [ ] 무한 루프 / Busy Waiting 여부
- [ ] Lock Contention / Synchronized 경합
- [ ] Thread 과다 생성
- [ ] 비효율적인 String 연결
- [ ] 정규식 반복 컴파일 / Catastrophic Backtracking
- [ ] 비효율적인 컬렉션 사용 (List.contains 등)
- [ ] 대량 임시 객체 생성 / Autoboxing
- [ ] Reflection 반복 호출

### DB / JDBC
- [ ] Connection Pool 크기 및 timeout 설정
- [ ] N+1 쿼리 패턴 여부
- [ ] PreparedStatement 사용 여부
- [ ] fetchSize 설정 여부
- [ ] Connection 누수 (close 미호출)

### Network / HTTP
- [ ] HTTP/Socket timeout 설정
- [ ] HTTP Connection Pool 사용 여부
- [ ] DNS 캐싱 설정
- [ ] TLS keep-alive 설정
- [ ] 실패 시 exponential backoff 적용

### 기타
- [ ] 로그 레벨 및 문자열 연결 방식
- [ ] ObjectMapper 등 무거운 객체 재사용 여부
- [ ] Scheduler 간격 적절성
- [ ] SecureRandom / 암호화 객체 재사용
- [ ] Stream.parallel() 무분별 사용

### 런타임 진단
- [ ] GC 로그 확인 (Full GC 빈도)
- [ ] Thread Dump에서 RUNNABLE 스레드 코드 위치 확인
- [ ] CPU Profiler (VisualVM, async-profiler) 결과 분석
