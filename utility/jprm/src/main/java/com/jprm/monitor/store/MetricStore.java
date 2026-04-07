package com.jprm.monitor.store;

import com.jprm.model.ResourceSnapshot;

import java.util.List;

/**
 * 메트릭 저장소 인터페이스.
 */
public interface MetricStore {

    void save(String processId, ResourceSnapshot snapshot);

    List<ResourceSnapshot> getTimeSeries(String processId);

    ResourceSnapshot getLatest(String processId);

    void remove(String processId);
}
