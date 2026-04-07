package com.jprm.monitor.store;

import com.jprm.config.JprmProperties;
import com.jprm.model.ResourceSnapshot;
import org.springframework.stereotype.Component;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 인메모리 Rolling Window 메트릭 저장소.
 * 각 프로세스당 maxDataPoints만큼의 스냅샷을 유지한다.
 */
@Component
public class InMemoryMetricStore implements MetricStore {

    private final int maxDataPoints;
    private final Map<String, LinkedList<ResourceSnapshot>> store = new ConcurrentHashMap<>();

    public InMemoryMetricStore(JprmProperties props) {
        this.maxDataPoints = props.getMonitoring().getMaxDataPoints();
    }

    @Override
    public synchronized void save(String processId, ResourceSnapshot snapshot) {
        LinkedList<ResourceSnapshot> series = store.computeIfAbsent(processId, k -> new LinkedList<>());
        series.addLast(snapshot);
        while (series.size() > maxDataPoints) {
            series.removeFirst();
        }
    }

    @Override
    public List<ResourceSnapshot> getTimeSeries(String processId) {
        LinkedList<ResourceSnapshot> series = store.get(processId);
        if (series == null) return List.of();
        synchronized (this) {
            return new ArrayList<>(series);
        }
    }

    @Override
    public ResourceSnapshot getLatest(String processId) {
        LinkedList<ResourceSnapshot> series = store.get(processId);
        if (series == null || series.isEmpty()) return null;
        synchronized (this) {
            return series.getLast();
        }
    }

    @Override
    public void remove(String processId) {
        store.remove(processId);
    }
}
