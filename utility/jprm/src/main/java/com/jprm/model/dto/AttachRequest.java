package com.jprm.model.dto;

/**
 * 기존 프로세스 Attach 요청 DTO.
 */
public record AttachRequest(
        long pid,
        String label
) {
    public AttachRequest {
        if (pid <= 0) {
            throw new IllegalArgumentException("pid must be positive");
        }
    }
}
