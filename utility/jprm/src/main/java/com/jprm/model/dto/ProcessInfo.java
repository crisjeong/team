package com.jprm.model.dto;

import com.jprm.model.MonitoredProcess;
import com.jprm.model.ProcessStatus;
import com.jprm.model.ResourceSnapshot;

import java.time.Instant;

/**
 * 프로세스 정보 응답 DTO.
 */
public record ProcessInfo(
        String id,
        String label,
        String jarPath,
        long pid,
        ProcessStatus status,
        int exitCode,
        Instant startTime,
        Instant endTime,
        int jmxPort,
        ResourceSnapshot latestSnapshot
) {
    public static ProcessInfo from(MonitoredProcess proc, ResourceSnapshot latest) {
        return new ProcessInfo(
                proc.getId(),
                proc.getLabel(),
                proc.getJarPath(),
                proc.getPid(),
                proc.getStatus(),
                proc.getExitCode(),
                proc.getStartTime(),
                proc.getEndTime(),
                proc.getJmxPort(),
                latest
        );
    }
}
