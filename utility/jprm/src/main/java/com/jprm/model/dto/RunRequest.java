package com.jprm.model.dto;

/**
 * JAR 실행 요청 DTO.
 */
public record RunRequest(
        String jarPath,
        String jvmOpts,
        String args,
        String label
) {
    public RunRequest {
        if (jarPath == null || jarPath.isBlank()) {
            throw new IllegalArgumentException("jarPath must not be blank");
        }
    }
}
