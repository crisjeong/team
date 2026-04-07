package com.jprm.analyzer;

import com.jprm.model.ResourceSnapshot;
import com.jprm.model.ResourceSummary;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;

/**
 * 메트릭 시계열 데이터에서 통계를 계산한다.
 */
@Component
public class StatisticsCalculator {

    /**
     * 시계열 데이터로부터 요약 통계를 생성한다.
     */
    public ResourceSummary calculate(List<ResourceSnapshot> series, int violationCount) {
        if (series == null || series.isEmpty()) {
            return new ResourceSummary(Duration.ZERO, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        }

        int n = series.size();
        Duration duration = Duration.between(series.getFirst().timestamp(), series.getLast().timestamp());

        // CPU
        double[] cpuValues = series.stream().mapToDouble(s -> Math.max(s.cpuPercent(), 0)).toArray();
        double cpuPeak = max(cpuValues);
        double cpuAvg = avg(cpuValues);
        double cpuP95 = percentile(cpuValues, 95);

        // RSS
        long[] rssValues = series.stream().mapToLong(s -> Math.max(s.rssBytes(), 0)).toArray();
        long rssPeak = max(rssValues);
        long rssAvg = avg(rssValues);

        // Heap
        long[] heapValues = series.stream()
                .filter(s -> s.heapUsed() >= 0)
                .mapToLong(ResourceSnapshot::heapUsed)
                .toArray();
        long heapPeakUsed = heapValues.length > 0 ? max(heapValues) : -1;
        long heapAvgUsed = heapValues.length > 0 ? avg(heapValues) : -1;

        // GC (마지막 값 - 첫 값 = 기간 동안의 총 GC)
        long totalGcCount = 0;
        long totalGcTime = 0;
        List<ResourceSnapshot> gcSeries = series.stream().filter(s -> s.gcCount() >= 0).toList();
        if (!gcSeries.isEmpty()) {
            totalGcCount = gcSeries.getLast().gcCount() - gcSeries.getFirst().gcCount();
            totalGcTime = gcSeries.getLast().gcTimeMs() - gcSeries.getFirst().gcTimeMs();
        }

        return new ResourceSummary(
                duration, n,
                cpuPeak, cpuAvg, cpuP95,
                rssPeak, rssAvg,
                heapPeakUsed, heapAvgUsed,
                totalGcCount, totalGcTime,
                violationCount
        );
    }

    private double max(double[] arr) {
        return Arrays.stream(arr).max().orElse(0);
    }

    private double avg(double[] arr) {
        return Arrays.stream(arr).average().orElse(0);
    }

    private double percentile(double[] arr, int p) {
        if (arr.length == 0) return 0;
        double[] sorted = arr.clone();
        Arrays.sort(sorted);
        int index = (int) Math.ceil(p / 100.0 * sorted.length) - 1;
        return sorted[Math.max(0, index)];
    }

    private long max(long[] arr) {
        return Arrays.stream(arr).max().orElse(0);
    }

    private long avg(long[] arr) {
        return (long) Arrays.stream(arr).average().orElse(0);
    }
}
