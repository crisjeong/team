package com.jprm.model;

import java.time.Instant;

/**
 * 임계값 초과 이벤트.
 */
public record ThresholdEvent(
        String processId,
        Instant timestamp,
        String metricType,
        double actualValue,
        double thresholdValue
) {}
