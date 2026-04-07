package com.jprm.model;

import java.time.Instant;

/**
 * 특정 시점의 프로세스 리소스 스냅샷 (불변).
 *
 * @param timestamp      수집 시각
 * @param cpuPercent     프로세스 CPU 사용률 (%, 0~100)
 * @param rssBytes       RSS — 물리 메모리 (bytes)
 * @param heapUsed       JVM Heap Used (bytes, JMX 미연결 시 -1)
 * @param heapMax        JVM Heap Max (bytes, JMX 미연결 시 -1)
 * @param heapCommitted  JVM Heap Committed (bytes, JMX 미연결 시 -1)
 * @param nonHeapUsed    JVM Non-Heap Used (bytes, JMX 미연결 시 -1)
 * @param gcCount        누적 GC 횟수 (-1 if unavailable)
 * @param gcTimeMs       누적 GC 시간 ms (-1 if unavailable)
 * @param threadCount    활성 스레드 수 (-1 if unavailable)
 */
public record ResourceSnapshot(
        Instant timestamp,
        double cpuPercent,
        long rssBytes,
        long heapUsed,
        long heapMax,
        long heapCommitted,
        long nonHeapUsed,
        long gcCount,
        long gcTimeMs,
        int threadCount
) {
    /** JMX 미연결 시 사용하는 OS-only 스냅샷 팩토리 */
    public static ResourceSnapshot osOnly(Instant ts, double cpu, long rss) {
        return new ResourceSnapshot(ts, cpu, rss, -1, -1, -1, -1, -1, -1, -1);
    }
}
