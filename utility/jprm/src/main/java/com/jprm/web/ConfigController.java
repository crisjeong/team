package com.jprm.web;

import com.jprm.config.JprmProperties;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 설정 관리 REST API — 임계값 및 알림 설정을 동적으로 변경.
 */
@RestController
@RequestMapping("/api/config")
public class ConfigController {

    private final JprmProperties props;

    public ConfigController(JprmProperties props) {
        this.props = props;
    }

    /** 현재 임계값 설정 조회 */
    @GetMapping("/threshold")
    public Map<String, Object> getThresholdConfig() {
        var t = props.getThreshold();
        return Map.of(
                "cpuPercent", t.getCpuPercent(),
                "heapPercent", t.getHeapPercent(),
                "rssMb", t.getRssMb()
        );
    }

    /** 임계값 설정 변경 */
    @PutMapping("/threshold")
    public ResponseEntity<Map<String, Object>> updateThreshold(@RequestBody Map<String, Object> body) {
        var t = props.getThreshold();
        if (body.containsKey("cpuPercent")) {
            t.setCpuPercent(((Number) body.get("cpuPercent")).doubleValue());
        }
        if (body.containsKey("heapPercent")) {
            t.setHeapPercent(((Number) body.get("heapPercent")).doubleValue());
        }
        if (body.containsKey("rssMb")) {
            t.setRssMb(((Number) body.get("rssMb")).longValue());
        }
        return ResponseEntity.ok(getThresholdConfig());
    }

    /** 현재 알림 설정 조회 */
    @GetMapping("/notification")
    public Map<String, Object> getNotificationConfig() {
        var n = props.getNotification();
        var e = n.getEmail();
        return Map.of(
                "enabled", n.isEnabled(),
                "cooldownSeconds", n.getCooldownSeconds(),
                "email", Map.of(
                        "enabled", e.isEnabled(),
                        "from", e.getFrom(),
                        "to", e.getTo(),
                        "subjectPrefix", e.getSubjectPrefix()
                )
        );
    }

    /** 알림 설정 변경 */
    @PutMapping("/notification")
    public ResponseEntity<Map<String, Object>> updateNotification(@RequestBody Map<String, Object> body) {
        var n = props.getNotification();
        if (body.containsKey("enabled")) {
            n.setEnabled((Boolean) body.get("enabled"));
        }
        if (body.containsKey("cooldownSeconds")) {
            n.setCooldownSeconds(((Number) body.get("cooldownSeconds")).intValue());
        }
        @SuppressWarnings("unchecked")
        var emailMap = (Map<String, Object>) body.get("email");
        if (emailMap != null) {
            var e = n.getEmail();
            if (emailMap.containsKey("enabled")) {
                e.setEnabled((Boolean) emailMap.get("enabled"));
            }
            if (emailMap.containsKey("from")) {
                e.setFrom((String) emailMap.get("from"));
            }
            if (emailMap.containsKey("to")) {
                @SuppressWarnings("unchecked")
                var to = (java.util.List<String>) emailMap.get("to");
                e.setTo(to);
            }
            if (emailMap.containsKey("subjectPrefix")) {
                e.setSubjectPrefix((String) emailMap.get("subjectPrefix"));
            }
        }
        return ResponseEntity.ok(getNotificationConfig());
    }
}
