package com.jprm.monitor.source;

import com.jprm.model.ResourceSnapshot;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.management.MBeanServerConnection;
import javax.management.ObjectName;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryUsage;
import java.time.Instant;
import java.util.Set;

/**
 * JMX 기반 JVM 수준 메트릭 수집기.
 * 원격 JMX 포트를 통해 Heap, GC, Thread 정보를 수집한다.
 */
public class JmxMetricSource implements MetricSource {

    private static final Logger log = LoggerFactory.getLogger(JmxMetricSource.class);

    private final int jmxPort;
    private JMXConnector connector;
    private MBeanServerConnection mbsc;
    private boolean connected = false;
    private int connectRetryCount = 0;
    private static final int MAX_RETRIES = 5;

    public JmxMetricSource(int jmxPort) {
        this.jmxPort = jmxPort;
    }

    /**
     * JMX 연결을 시도한다. 실패해도 예외를 던지지 않는다 (Graceful Degradation).
     */
    public boolean tryConnect() {
        if (connected) return true;
        if (connectRetryCount >= MAX_RETRIES) return false;

        try {
            String url = "service:jmx:rmi:///jndi/rmi://localhost:" + jmxPort + "/jmxrmi";
            JMXServiceURL serviceUrl = new JMXServiceURL(url);
            connector = JMXConnectorFactory.connect(serviceUrl);
            mbsc = connector.getMBeanServerConnection();
            connected = true;
            log.info("JMX connected on port {}", jmxPort);
            return true;
        } catch (Exception e) {
            connectRetryCount++;
            log.debug("JMX connect attempt {}/{} failed on port {}: {}",
                    connectRetryCount, MAX_RETRIES, jmxPort, e.getMessage());
            return false;
        }
    }

    @Override
    public ResourceSnapshot collect() {
        if (!connected && !tryConnect()) {
            return null;
        }

        try {
            // Heap Memory
            ObjectName memoryName = new ObjectName(ManagementFactory.MEMORY_MXBEAN_NAME);
            javax.management.openmbean.CompositeData heapData =
                    (javax.management.openmbean.CompositeData) mbsc.getAttribute(memoryName, "HeapMemoryUsage");
            long heapUsed = (Long) heapData.get("used");
            long heapMax = (Long) heapData.get("max");
            long heapCommitted = (Long) heapData.get("committed");

            // Non-Heap Memory
            javax.management.openmbean.CompositeData nonHeapData =
                    (javax.management.openmbean.CompositeData) mbsc.getAttribute(memoryName, "NonHeapMemoryUsage");
            long nonHeapUsed = (Long) nonHeapData.get("used");

            // GC
            long totalGcCount = 0;
            long totalGcTime = 0;
            Set<ObjectName> gcNames = mbsc.queryNames(
                    new ObjectName(ManagementFactory.GARBAGE_COLLECTOR_MXBEAN_DOMAIN_TYPE + ",*"), null);
            for (ObjectName gcName : gcNames) {
                Long count = (Long) mbsc.getAttribute(gcName, "CollectionCount");
                Long time = (Long) mbsc.getAttribute(gcName, "CollectionTime");
                if (count != null && count >= 0) totalGcCount += count;
                if (time != null && time >= 0) totalGcTime += time;
            }

            // Threads
            ObjectName threadName = new ObjectName(ManagementFactory.THREAD_MXBEAN_NAME);
            int threadCount = (Integer) mbsc.getAttribute(threadName, "ThreadCount");

            return new ResourceSnapshot(
                    Instant.now(), -1, -1,  // CPU/RSS는 OSHI에서
                    heapUsed, heapMax, heapCommitted,
                    nonHeapUsed, totalGcCount, totalGcTime, threadCount
            );
        } catch (Exception e) {
            log.warn("JMX collection failed on port {}: {}", jmxPort, e.getMessage());
            connected = false; // 다음 수집 시 재연결 시도
            return null;
        }
    }

    @Override
    public void close() {
        try {
            if (connector != null) {
                connector.close();
            }
        } catch (Exception e) {
            log.debug("Error closing JMX connector: {}", e.getMessage());
        }
        connected = false;
    }
}
