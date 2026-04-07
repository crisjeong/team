package com.jprm.analyzer;

import com.jprm.config.JprmProperties;
import com.jprm.model.ResourceSnapshot;
import com.jprm.model.ThresholdEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 메트릭 임계값 초과를 감지하고 경고를 발생시킨다.
 */
@Component
public class ThresholdChecker {

    private static final Logger log = LoggerFactory.getLogger(ThresholdChecker.class);
    private final JprmProperties props;
    private final Map<String, List<ThresholdEvent>> events = new ConcurrentHashMap<>();

    public ThresholdChecker(JprmProperties props) {
        this.props = props;
    }

    /**
     * 스냅샷을 검사하여 임계값 초과 이벤트를 반환한다.
     */
    public List<ThresholdEvent> check(String processId, ResourceSnapshot snapshot) {
        List<ThresholdEvent> violations = new ArrayList<>();

        // CPU 임계값
        double cpuThreshold = props.getThreshold().getCpuPercent();
        if (snapshot.cpuPercent() > cpuThreshold) {
            ThresholdEvent event = new ThresholdEvent(
                    processId, Instant.now(), "CPU",
                    snapshot.cpuPercent(), cpuThreshold
            );
            violations.add(event);
            log.warn("⚠ CPU threshold exceeded for {}: {}% > {}%",
                    processId, String.format("%.1f", snapshot.cpuPercent()), String.format("%.1f", cpuThreshold));
        }

        // Heap 임계값
        if (snapshot.heapUsed() >= 0 && snapshot.heapMax() > 0) {
            double heapPct = (double) snapshot.heapUsed() / snapshot.heapMax() * 100.0;
            double heapThreshold = props.getThreshold().getHeapPercent();
            if (heapPct > heapThreshold) {
                ThresholdEvent event = new ThresholdEvent(
                        processId, Instant.now(), "HEAP",
                        heapPct, heapThreshold
                );
                violations.add(event);
                log.warn("⚠ Heap threshold exceeded for {}: {}% > {}%",
                        processId, String.format("%.1f", heapPct), String.format("%.1f", heapThreshold));
            }
        }

        // RSS 임계값 (설정된 경우에만)
        long rssMbThreshold = props.getThreshold().getRssMb();
        if (rssMbThreshold > 0 && snapshot.rssBytes() >= 0) {
            long rssMb = snapshot.rssBytes() / (1024 * 1024);
            if (rssMb > rssMbThreshold) {
                ThresholdEvent event = new ThresholdEvent(
                        processId, Instant.now(), "RSS",
                        rssMb, rssMbThreshold
                );
                violations.add(event);
                log.warn("⚠ RSS threshold exceeded for {}: {} MB > {} MB",
                        processId, rssMb, rssMbThreshold);
            }
        }

        // 이벤트 저장
        if (!violations.isEmpty()) {
            events.computeIfAbsent(processId, k -> new ArrayList<>()).addAll(violations);
        }

        return violations;
    }

    public List<ThresholdEvent> getEvents(String processId) {
        return events.getOrDefault(processId, List.of());
    }

    public int getViolationCount(String processId) {
        return events.getOrDefault(processId, List.of()).size();
    }
}
