package com.jprm.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * JPRM 커스텀 설정 프로퍼티.
 */
@Component
@ConfigurationProperties(prefix = "jprm")
public class JprmProperties {

    private final Monitoring monitoring = new Monitoring();
    private final Threshold threshold = new Threshold();
    private final Jmx jmx = new Jmx();
    private final Notification notification = new Notification();

    public Monitoring getMonitoring() { return monitoring; }
    public Threshold getThreshold() { return threshold; }
    public Jmx getJmx() { return jmx; }
    public Notification getNotification() { return notification; }

    public static class Monitoring {
        private int intervalMs = 1000;
        private int maxDataPoints = 3600;

        public int getIntervalMs() { return intervalMs; }
        public void setIntervalMs(int intervalMs) { this.intervalMs = intervalMs; }
        public int getMaxDataPoints() { return maxDataPoints; }
        public void setMaxDataPoints(int maxDataPoints) { this.maxDataPoints = maxDataPoints; }
    }

    public static class Threshold {
        private double cpuPercent = 90.0;
        private double heapPercent = 85.0;
        private long rssMb = 0;

        public double getCpuPercent() { return cpuPercent; }
        public void setCpuPercent(double cpuPercent) { this.cpuPercent = cpuPercent; }
        public double getHeapPercent() { return heapPercent; }
        public void setHeapPercent(double heapPercent) { this.heapPercent = heapPercent; }
        public long getRssMb() { return rssMb; }
        public void setRssMb(long rssMb) { this.rssMb = rssMb; }
    }

    public static class Jmx {
        private boolean enabled = true;
        private int portRangeStart = 9010;
        private int portRangeEnd = 9099;

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }
        public int getPortRangeStart() { return portRangeStart; }
        public void setPortRangeStart(int portRangeStart) { this.portRangeStart = portRangeStart; }
        public int getPortRangeEnd() { return portRangeEnd; }
        public void setPortRangeEnd(int portRangeEnd) { this.portRangeEnd = portRangeEnd; }
    }

    public static class Notification {
        private boolean enabled = false;
        private int cooldownSeconds = 300; // 동일 알람 쿨다운 (5분)

        private final Email email = new Email();

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }
        public int getCooldownSeconds() { return cooldownSeconds; }
        public void setCooldownSeconds(int cooldownSeconds) { this.cooldownSeconds = cooldownSeconds; }
        public Email getEmail() { return email; }

        public static class Email {
            private boolean enabled = false;
            private String from = "jprm@localhost";
            private List<String> to = new ArrayList<>();
            private String subjectPrefix = "[JPRM Alert]";

            public boolean isEnabled() { return enabled; }
            public void setEnabled(boolean enabled) { this.enabled = enabled; }
            public String getFrom() { return from; }
            public void setFrom(String from) { this.from = from; }
            public List<String> getTo() { return to; }
            public void setTo(List<String> to) { this.to = to; }
            public String getSubjectPrefix() { return subjectPrefix; }
            public void setSubjectPrefix(String subjectPrefix) { this.subjectPrefix = subjectPrefix; }
        }
    }
}
