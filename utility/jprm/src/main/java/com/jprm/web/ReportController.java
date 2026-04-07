package com.jprm.web;

import com.jprm.report.ReportService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * 리포트 다운로드 엔드포인트.
 */
@RestController
@RequestMapping("/api/processes/{id}/report")
public class ReportController {

    private final ReportService reportService;

    public ReportController(ReportService reportService) {
        this.reportService = reportService;
    }

    @GetMapping
    public ResponseEntity<byte[]> downloadReport(
            @PathVariable String id,
            @RequestParam(defaultValue = "json") String format) {
        try {
            return switch (format.toLowerCase()) {
                case "csv" -> {
                    String csv = reportService.generateCsvReport(id);
                    yield ResponseEntity.ok()
                            .header(HttpHeaders.CONTENT_DISPOSITION,
                                    "attachment; filename=jprm-report-" + id + ".csv")
                            .contentType(MediaType.parseMediaType("text/csv"))
                            .body(csv.getBytes());
                }
                default -> {
                    String json = reportService.generateJsonReport(id);
                    yield ResponseEntity.ok()
                            .header(HttpHeaders.CONTENT_DISPOSITION,
                                    "attachment; filename=jprm-report-" + id + ".json")
                            .contentType(MediaType.APPLICATION_JSON)
                            .body(json.getBytes());
                }
            };
        } catch (Exception e) {
            return ResponseEntity.notFound().build();
        }
    }
}
