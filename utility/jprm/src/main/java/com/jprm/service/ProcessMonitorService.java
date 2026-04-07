package com.jprm.service;

import com.jprm.model.MonitoredProcess;
import com.jprm.model.ResourceSnapshot;
import com.jprm.model.dto.ProcessInfo;
import com.jprm.monitor.MonitorEngine;
import com.jprm.monitor.store.MetricStore;
import com.jprm.process.ProcessManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * 프로세스 모니터링 비즈니스 로직 통합 서비스.
 */
@Service
public class ProcessMonitorService {

    private static final Logger log = LoggerFactory.getLogger(ProcessMonitorService.class);

    private final ProcessManager processManager;
    private final MonitorEngine monitorEngine;
    private final MetricStore metricStore;

    public ProcessMonitorService(ProcessManager processManager,
                                  MonitorEngine monitorEngine,
                                  MetricStore metricStore) {
        this.processManager = processManager;
        this.monitorEngine = monitorEngine;
        this.metricStore = metricStore;
    }

    /**
     * JAR를 실행하고 모니터링을 시작한다.
     */
    public ProcessInfo launchAndMonitor(String jarPath, String jvmOpts, String appArgs, String label) {
        MonitoredProcess mp = processManager.launchJar(jarPath, jvmOpts, appArgs, label);
        monitorEngine.startMonitoring(mp);
        return ProcessInfo.from(mp, null);
    }

    /**
     * 기존 PID에 Attach하고 모니터링을 시작한다.
     */
    public ProcessInfo attachAndMonitor(long pid, String label) {
        MonitoredProcess mp = processManager.attachProcess(pid, label);
        monitorEngine.startMonitoring(mp);
        return ProcessInfo.from(mp, null);
    }

    /**
     * 프로세스를 중지한다.
     */
    public boolean stopProcess(String processId) {
        monitorEngine.stopMonitoring(processId);
        return processManager.stopProcess(processId);
    }

    /**
     * 전체 프로세스 목록 + 최신 메트릭.
     */
    public List<ProcessInfo> getAllProcesses() {
        return processManager.getAllProcesses().stream()
                .map(p -> ProcessInfo.from(p, metricStore.getLatest(p.getId())))
                .toList();
    }

    /**
     * 특정 프로세스 정보 + 최신 메트릭.
     */
    public ProcessInfo getProcess(String processId) {
        MonitoredProcess mp = processManager.getProcess(processId);
        if (mp == null) return null;
        return ProcessInfo.from(mp, metricStore.getLatest(processId));
    }

    /**
     * 특정 프로세스의 시계열 데이터.
     */
    public List<ResourceSnapshot> getTimeSeries(String processId) {
        return metricStore.getTimeSeries(processId);
    }
}
