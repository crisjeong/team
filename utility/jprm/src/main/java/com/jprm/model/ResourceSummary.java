package com.jprm.model;

import java.time.Duration;

/**
 * 모니터링 구간 전체의 요약 통계.
 */
public record ResourceSummary(
        Duration monitoringDuration,
        int sampleCount,
        // CPU (%)
        double cpuPeak,
        double cpuAvg,
        double cpuP95,
        // Memory — RSS (bytes)
        long rssPeak,
        long rssAvg,
        // JVM Heap (bytes)
        long heapPeakUsed,
        long heapAvgUsed,
        // GC
        long totalGcCount,
        long totalGcTimeMs,
        // Alerts
        int thresholdViolationCount
) {}
