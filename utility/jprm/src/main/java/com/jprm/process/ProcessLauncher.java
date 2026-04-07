package com.jprm.process;

import com.jprm.config.JprmProperties;
import com.jprm.model.MonitoredProcess;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * JAR 파일을 자식 프로세스로 실행하는 런처.
 * JMX 원격 포트를 자동 부여한다.
 */
@Component
public class ProcessLauncher {

    private static final Logger log = LoggerFactory.getLogger(ProcessLauncher.class);
    private final JprmProperties props;
    private final AtomicInteger nextJmxPort;

    public ProcessLauncher(JprmProperties props) {
        this.props = props;
        this.nextJmxPort = new AtomicInteger(props.getJmx().getPortRangeStart());
    }

    /**
     * JAR 파일을 실행한다.
     *
     * @param jarPath  JAR 파일 경로
     * @param jvmOpts  JVM 옵션 (nullable)
     * @param appArgs  애플리케이션 인자 (nullable)
     * @param label    표시 이름 (nullable → 파일명 사용)
     * @return 실행된 프로세스 정보
     */
    public MonitoredProcess launch(String jarPath, String jvmOpts, String appArgs, String label) {
        File jarFile = new File(jarPath);
        if (!jarFile.exists()) {
            throw new IllegalArgumentException("JAR file not found: " + jarPath);
        }

        String processLabel = (label != null && !label.isBlank()) ? label : jarFile.getName();
        int jmxPort = allocateJmxPort();

        List<String> command = buildCommand(jarPath, jvmOpts, appArgs, jmxPort);
        log.info("Launching: {} (JMX port: {})", processLabel, jmxPort);
        log.debug("Command: {}", command);

        try {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(false);
            Process nativeProcess = pb.start();
            long pid = nativeProcess.pid();

            MonitoredProcess mp = new MonitoredProcess(processLabel, jarPath, pid, jvmOpts, jmxPort);
            mp.setNativeProcess(nativeProcess);

            // 비동기로 프로세스 종료 감지
            nativeProcess.onExit().thenAccept(p -> {
                int exitCode = p.exitValue();
                mp.markExited(exitCode);
                log.info("Process {} (PID:{}) exited with code {}", processLabel, pid, exitCode);
            });

            log.info("Started {} (PID: {})", processLabel, pid);
            return mp;
        } catch (IOException e) {
            throw new RuntimeException("Failed to launch JAR: " + jarPath, e);
        }
    }

    private List<String> buildCommand(String jarPath, String jvmOpts, String appArgs, int jmxPort) {
        List<String> cmd = new ArrayList<>();
        cmd.add("java");

        // JMX 원격 설정
        if (props.getJmx().isEnabled()) {
            cmd.add("-Dcom.sun.management.jmxremote");
            cmd.add("-Dcom.sun.management.jmxremote.port=" + jmxPort);
            cmd.add("-Dcom.sun.management.jmxremote.authenticate=false");
            cmd.add("-Dcom.sun.management.jmxremote.ssl=false");
            cmd.add("-Djava.rmi.server.hostname=localhost");
        }

        // 사용자 JVM 옵션
        if (jvmOpts != null && !jvmOpts.isBlank()) {
            for (String opt : jvmOpts.split("\\s+")) {
                cmd.add(opt);
            }
        }

        cmd.add("-jar");
        cmd.add(jarPath);

        // 애플리케이션 인자
        if (appArgs != null && !appArgs.isBlank()) {
            for (String arg : appArgs.split("\\s+")) {
                cmd.add(arg);
            }
        }

        return cmd;
    }

    private int allocateJmxPort() {
        int port = nextJmxPort.getAndIncrement();
        if (port > props.getJmx().getPortRangeEnd()) {
            nextJmxPort.set(props.getJmx().getPortRangeStart());
            port = nextJmxPort.getAndIncrement();
        }
        return port;
    }
}
