package com.jprm.monitor.source;

import com.jprm.model.ResourceSnapshot;

/**
 * 메트릭 수집 소스 인터페이스.
 */
public interface MetricSource {

    /**
     * 대상 프로세스의 현재 메트릭을 수집한다.
     *
     * @return 리소스 스냅샷, 수집 불가능 시 null
     */
    ResourceSnapshot collect();

    /**
     * 리소스를 해제한다.
     */
    default void close() {}
}
