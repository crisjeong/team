package com.jprm.process;

import com.jprm.model.MonitoredProcess;
import com.jprm.model.ProcessStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 다중 프로세스 생명주기 관리자.
 */
@Component
public class ProcessManager {

    private static final Logger log = LoggerFactory.getLogger(ProcessManager.class);
    private final Map<String, MonitoredProcess> processes = new ConcurrentHashMap<>();
    private final ProcessLauncher launcher;

    public ProcessManager(ProcessLauncher launcher) {
        this.launcher = launcher;
    }

    /**
     * JAR를 실행하고 관리 목록에 추가한다.
     */
    public MonitoredProcess launchJar(String jarPath, String jvmOpts, String appArgs, String label) {
        MonitoredProcess mp = launcher.launch(jarPath, jvmOpts, appArgs, label);
        processes.put(mp.getId(), mp);
        log.info("Registered process: {} (id={}, pid={})", mp.getLabel(), mp.getId(), mp.getPid());
        return mp;
    }

    /**
     * 기존 PID를 Attach 모드로 추가한다.
     */
    public MonitoredProcess attachProcess(long pid, String label) {
        String processLabel = (label != null && !label.isBlank()) ? label : "PID-" + pid;
        // Attach 모드: jarPath=null, jmxPort=0 (JvmAttacher가 동적으로 연결)
        MonitoredProcess mp = new MonitoredProcess(processLabel, null, pid, null, 0);
        processes.put(mp.getId(), mp);
        log.info("Attached to process: {} (id={}, pid={})", processLabel, mp.getId(), pid);
        return mp;
    }

    /**
     * 프로세스를 중지한다.
     */
    public boolean stopProcess(String processId) {
        MonitoredProcess mp = processes.get(processId);
        if (mp == null) return false;

        Process nativeProcess = mp.getNativeProcess();
        if (nativeProcess != null && nativeProcess.isAlive()) {
            nativeProcess.destroy();
            log.info("Destroyed process: {} (pid={})", mp.getLabel(), mp.getPid());
        }
        mp.markStopped();
        return true;
    }

    public MonitoredProcess getProcess(String id) {
        return processes.get(id);
    }

    public Collection<MonitoredProcess> getAllProcesses() {
        return Collections.unmodifiableCollection(processes.values());
    }

    public List<MonitoredProcess> getRunningProcesses() {
        return processes.values().stream()
                .filter(p -> p.getStatus() == ProcessStatus.RUNNING)
                .toList();
    }
}
