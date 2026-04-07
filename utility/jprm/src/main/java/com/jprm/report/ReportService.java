package com.jprm.report;

import com.jprm.analyzer.StatisticsCalculator;
import com.jprm.analyzer.ThresholdChecker;
import com.jprm.model.MonitoredProcess;
import com.jprm.model.ResourceSnapshot;
import com.jprm.model.ResourceSummary;
import com.jprm.monitor.store.MetricStore;
import com.jprm.process.ProcessManager;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.springframework.stereotype.Service;

import java.io.StringWriter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 리포트 생성 서비스 — JSON, CSV 형식 지원.
 */
@Service
public class ReportService {

    private final MetricStore metricStore;
    private final ProcessManager processManager;
    private final StatisticsCalculator statsCalculator;
    private final ThresholdChecker thresholdChecker;
    private final ObjectMapper objectMapper;

    public ReportService(MetricStore metricStore, ProcessManager processManager,
                         StatisticsCalculator statsCalculator, ThresholdChecker thresholdChecker) {
        this.metricStore = metricStore;
        this.processManager = processManager;
        this.statsCalculator = statsCalculator;
        this.thresholdChecker = thresholdChecker;
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
        this.objectMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        this.objectMapper.enable(SerializationFeature.INDENT_OUTPUT);
    }

    /**
     * JSON 리포트 생성
     */
    public String generateJsonReport(String processId) throws Exception {
        MonitoredProcess proc = processManager.getProcess(processId);
        if (proc == null) throw new IllegalArgumentException("Process not found: " + processId);

        List<ResourceSnapshot> series = metricStore.getTimeSeries(processId);
        int violations = thresholdChecker.getViolationCount(processId);
        ResourceSummary summary = statsCalculator.calculate(series, violations);

        Map<String, Object> report = new LinkedHashMap<>();
        report.put("processId", proc.getId());
        report.put("label", proc.getLabel());
        report.put("jarPath", proc.getJarPath());
        report.put("pid", proc.getPid());
        report.put("status", proc.getStatus().name());
        report.put("startTime", proc.getStartTime());
        report.put("endTime", proc.getEndTime());
        report.put("summary", summary);
        report.put("thresholdEvents", thresholdChecker.getEvents(processId));
        report.put("timeSeries", series);

        return objectMapper.writeValueAsString(report);
    }

    /**
     * CSV 리포트 생성
     */
    public String generateCsvReport(String processId) {
        List<ResourceSnapshot> series = metricStore.getTimeSeries(processId);

        StringWriter sw = new StringWriter();
        sw.append("timestamp,cpuPercent,rssBytes,rssMB,heapUsed,heapMax,heapCommitted,nonHeapUsed,gcCount,gcTimeMs,threadCount\n");

        for (ResourceSnapshot s : series) {
            sw.append(s.timestamp().toString()).append(',');
            sw.append(String.format("%.1f", s.cpuPercent())).append(',');
            sw.append(String.valueOf(s.rssBytes())).append(',');
            sw.append(String.valueOf(s.rssBytes() >= 0 ? s.rssBytes() / (1024 * 1024) : -1)).append(',');
            sw.append(String.valueOf(s.heapUsed())).append(',');
            sw.append(String.valueOf(s.heapMax())).append(',');
            sw.append(String.valueOf(s.heapCommitted())).append(',');
            sw.append(String.valueOf(s.nonHeapUsed())).append(',');
            sw.append(String.valueOf(s.gcCount())).append(',');
            sw.append(String.valueOf(s.gcTimeMs())).append(',');
            sw.append(String.valueOf(s.threadCount())).append('\n');
        }

        return sw.toString();
    }
}
