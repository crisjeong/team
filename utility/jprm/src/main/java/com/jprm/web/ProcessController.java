package com.jprm.web;

import com.jprm.model.ResourceSnapshot;
import com.jprm.model.dto.AttachRequest;
import com.jprm.model.dto.ProcessInfo;
import com.jprm.model.dto.RunRequest;
import com.jprm.service.ProcessMonitorService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * 프로세스 관리 REST API 컨트롤러.
 */
@RestController
@RequestMapping("/api/processes")
public class ProcessController {

    private final ProcessMonitorService service;

    public ProcessController(ProcessMonitorService service) {
        this.service = service;
    }

    /** 전체 프로세스 목록 */
    @GetMapping
    public List<ProcessInfo> listProcesses() {
        return service.getAllProcesses();
    }

    /** 특정 프로세스 상세 */
    @GetMapping("/{id}")
    public ResponseEntity<ProcessInfo> getProcess(@PathVariable String id) {
        ProcessInfo info = service.getProcess(id);
        if (info == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(info);
    }

    /** 시계열 데이터 */
    @GetMapping("/{id}/metrics")
    public ResponseEntity<List<ResourceSnapshot>> getMetrics(@PathVariable String id) {
        List<ResourceSnapshot> series = service.getTimeSeries(id);
        return ResponseEntity.ok(series);
    }

    /** JAR 실행 추가 */
    @PostMapping("/run")
    public ResponseEntity<ProcessInfo> runJar(@RequestBody RunRequest request) {
        try {
            ProcessInfo info = service.launchAndMonitor(
                    request.jarPath(), request.jvmOpts(), request.args(), request.label());
            return ResponseEntity.status(HttpStatus.CREATED).body(info);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    /** 기존 PID Attach */
    @PostMapping("/attach")
    public ResponseEntity<ProcessInfo> attachProcess(@RequestBody AttachRequest request) {
        try {
            ProcessInfo info = service.attachAndMonitor(request.pid(), request.label());
            return ResponseEntity.status(HttpStatus.CREATED).body(info);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    /** 프로세스 중지 */
    @PostMapping("/{id}/stop")
    public ResponseEntity<Map<String, String>> stopProcess(@PathVariable String id) {
        boolean stopped = service.stopProcess(id);
        if (!stopped) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(Map.of("status", "stopped"));
    }
}
