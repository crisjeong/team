package com.jprm.model;

import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 모니터링 대상 프로세스 정보.
 */
public class MonitoredProcess {

    private final String id;
    private final String label;
    private final String jarPath;   // null if attach mode
    private final long pid;
    private final Instant startTime;
    private final String jvmOptions;
    private final int jmxPort;      // 0 if no JMX

    private final AtomicReference<ProcessStatus> status = new AtomicReference<>(ProcessStatus.RUNNING);
    private volatile Instant endTime;
    private volatile int exitCode = -1;
    private volatile Process nativeProcess;  // null if attach mode

    public MonitoredProcess(String label, String jarPath, long pid,
                            String jvmOptions, int jmxPort) {
        this.id = UUID.randomUUID().toString().substring(0, 8);
        this.label = label;
        this.jarPath = jarPath;
        this.pid = pid;
        this.startTime = Instant.now();
        this.jvmOptions = jvmOptions;
        this.jmxPort = jmxPort;
    }

    // --- Getters ---
    public String getId() { return id; }
    public String getLabel() { return label; }
    public String getJarPath() { return jarPath; }
    public long getPid() { return pid; }
    public Instant getStartTime() { return startTime; }
    public Instant getEndTime() { return endTime; }
    public String getJvmOptions() { return jvmOptions; }
    public int getJmxPort() { return jmxPort; }
    public int getExitCode() { return exitCode; }
    public ProcessStatus getStatus() { return status.get(); }
    public Process getNativeProcess() { return nativeProcess; }

    // --- Setters ---
    public void setNativeProcess(Process process) { this.nativeProcess = process; }

    public void markExited(int code) {
        this.exitCode = code;
        this.endTime = Instant.now();
        this.status.set(ProcessStatus.EXITED);
    }

    public void markStopped() {
        this.endTime = Instant.now();
        this.status.set(ProcessStatus.STOPPED);
    }

    public void markFailed() {
        this.endTime = Instant.now();
        this.status.set(ProcessStatus.FAILED);
    }

    public boolean isAlive() {
        return status.get() == ProcessStatus.RUNNING;
    }
}
