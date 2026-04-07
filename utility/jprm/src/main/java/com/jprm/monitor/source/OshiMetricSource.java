package com.jprm.monitor.source;

import com.jprm.model.ResourceSnapshot;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import oshi.SystemInfo;
import oshi.software.os.OSProcess;
import oshi.software.os.OperatingSystem;

import java.time.Instant;

/**
 * OSHI 기반 OS 수준 메트릭 수집기.
 * 프로세스 CPU 사용률과 RSS 메모리를 수집한다.
 */
public class OshiMetricSource implements MetricSource {

    private static final Logger log = LoggerFactory.getLogger(OshiMetricSource.class);

    private final long pid;
    private final OperatingSystem os;
    private OSProcess previousSnapshot;

    public OshiMetricSource(long pid) {
        this.pid = pid;
        SystemInfo si = new SystemInfo();
        this.os = si.getOperatingSystem();
        // 초기 스냅샷 (CPU 계산용 베이스라인)
        this.previousSnapshot = os.getProcess((int) pid);
    }

    @Override
    public ResourceSnapshot collect() {
        try {
            OSProcess currentProcess = os.getProcess((int) pid);
            if (currentProcess == null) {
                log.debug("Process {} not found (may have exited)", pid);
                return null;
            }

            double cpuLoad = 0.0;
            if (previousSnapshot != null) {
                cpuLoad = currentProcess.getProcessCpuLoadBetweenTicks(previousSnapshot) * 100.0;
                // OSHI는 코어 수 기반으로 100% 이상을 반환할 수 있음 → 클램프
                cpuLoad = Math.min(cpuLoad, 100.0);
                cpuLoad = Math.max(cpuLoad, 0.0);
            }

            long rss = currentProcess.getResidentSetSize();

            previousSnapshot = currentProcess;

            return ResourceSnapshot.osOnly(Instant.now(), cpuLoad, rss);
        } catch (Exception e) {
            log.warn("OSHI collection failed for PID {}: {}", pid, e.getMessage());
            return null;
        }
    }
}
