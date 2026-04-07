package com.jprm.monitor;

import com.jprm.analyzer.ThresholdChecker;
import com.jprm.config.JprmProperties;
import com.jprm.model.MonitoredProcess;
import com.jprm.model.ResourceSnapshot;
import com.jprm.model.ThresholdEvent;
import com.jprm.monitor.source.JmxMetricSource;
import com.jprm.monitor.source.OshiMetricSource;
import com.jprm.monitor.store.MetricStore;
import com.jprm.notification.EmailNotificationService;
import com.jprm.web.MetricsWebSocketHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.concurrent.*;

/**
 * 프로세스별 메트릭 수집 스케줄러.
 * 수집 → 저장 → 임계값 체크 → 알림 → WebSocket 전송 파이프라인을 실행한다.
 */
@Component
public class MonitorEngine {

    private static final Logger log = LoggerFactory.getLogger(MonitorEngine.class);

    private final JprmProperties props;
    private final MetricStore metricStore;
    private final MetricsWebSocketHandler wsHandler;
    private final ThresholdChecker thresholdChecker;
    private final EmailNotificationService emailService;
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(4);
    private final Map<String, ScheduledFuture<?>> tasks = new ConcurrentHashMap<>();
    private final Map<String, OshiMetricSource> oshiSources = new ConcurrentHashMap<>();
    private final Map<String, JmxMetricSource> jmxSources = new ConcurrentHashMap<>();

    public MonitorEngine(JprmProperties props, MetricStore metricStore,
                         MetricsWebSocketHandler wsHandler,
                         ThresholdChecker thresholdChecker,
                         EmailNotificationService emailService) {
        this.props = props;
        this.metricStore = metricStore;
        this.wsHandler = wsHandler;
        this.thresholdChecker = thresholdChecker;
        this.emailService = emailService;
    }

    /**
     * 프로세스 모니터링을 시작한다.
     */
    public void startMonitoring(MonitoredProcess process) {
        String id = process.getId();
        long pid = process.getPid();

        // OS 수준 수집기
        OshiMetricSource oshi = new OshiMetricSource(pid);
        oshiSources.put(id, oshi);

        // JVM 수준 수집기 (JMX)
        JmxMetricSource jmx = null;
        if (props.getJmx().isEnabled() && process.getJmxPort() > 0) {
            jmx = new JmxMetricSource(process.getJmxPort());
            jmxSources.put(id, jmx);
        }

        final JmxMetricSource finalJmx = jmx;
        int interval = props.getMonitoring().getIntervalMs();

        ScheduledFuture<?> future = scheduler.scheduleAtFixedRate(() -> {
            try {
                collectAndStore(id, process, oshi, finalJmx);
            } catch (Exception e) {
                log.error("Collection error for process {}: {}", id, e.getMessage());
            }
        }, 0, interval, TimeUnit.MILLISECONDS);

        tasks.put(id, future);
        log.info("Monitoring started for {} (pid={}, interval={}ms)", process.getLabel(), pid, interval);
    }

    /**
     * 프로세스 모니터링을 중지한다.
     */
    public void stopMonitoring(String processId) {
        ScheduledFuture<?> future = tasks.remove(processId);
        if (future != null) {
            future.cancel(false);
        }

        JmxMetricSource jmx = jmxSources.remove(processId);
        if (jmx != null) jmx.close();

        oshiSources.remove(processId);
        log.info("Monitoring stopped for process {}", processId);
    }

    private void collectAndStore(String processId, MonitoredProcess process,
                                  OshiMetricSource oshi, JmxMetricSource jmx) {
        // 프로세스가 종료되었으면 모니터링 중지
        if (!process.isAlive()) {
            stopMonitoring(processId);
            return;
        }

        // OS 수준 수집
        ResourceSnapshot osSnapshot = oshi.collect();
        if (osSnapshot == null) {
            if (process.getNativeProcess() != null && !process.getNativeProcess().isAlive()) {
                process.markExited(process.getNativeProcess().exitValue());
            }
            stopMonitoring(processId);
            return;
        }

        // JVM 수준 수집 (병합)
        ResourceSnapshot merged;
        if (jmx != null) {
            ResourceSnapshot jvmSnapshot = jmx.collect();
            merged = mergeSnapshots(osSnapshot, jvmSnapshot);
        } else {
            merged = osSnapshot;
        }

        // 1) 메트릭 저장
        metricStore.save(processId, merged);

        // 2) WebSocket 전송
        wsHandler.broadcastMetric(processId, merged);

        // 3) 임계값 체크 → 알림
        List<ThresholdEvent> violations = thresholdChecker.check(processId, merged);
        if (!violations.isEmpty()) {
            // WebSocket으로 알림 이벤트 브로드캐스트
            wsHandler.broadcastAlert(processId, violations);

            // 이메일 알림 전송 (비동기)
            try {
                emailService.notify(violations);
            } catch (Exception e) {
                log.error("Email notification failed: {}", e.getMessage());
            }
        }
    }

    private ResourceSnapshot mergeSnapshots(ResourceSnapshot os, ResourceSnapshot jvm) {
        if (jvm == null) return os;
        return new ResourceSnapshot(
                os.timestamp(),
                os.cpuPercent(),
                os.rssBytes(),
                jvm.heapUsed(),
                jvm.heapMax(),
                jvm.heapCommitted(),
                jvm.nonHeapUsed(),
                jvm.gcCount(),
                jvm.gcTimeMs(),
                jvm.threadCount()
        );
    }
}
