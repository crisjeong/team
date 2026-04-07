package com.jprm.notification;

import com.jprm.config.JprmProperties;
import com.jprm.model.ThresholdEvent;
import com.jprm.process.ProcessManager;
import com.jprm.model.MonitoredProcess;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 임계값 초과 시 이메일 알림을 전송하는 서비스.
 * 쿨다운 로직으로 동일 알림 반복 전송을 방지한다.
 */
@Service
public class EmailNotificationService {

    private static final Logger log = LoggerFactory.getLogger(EmailNotificationService.class);
    private static final DateTimeFormatter TIME_FMT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault());

    private final JavaMailSender mailSender;
    private final JprmProperties props;
    private final ProcessManager processManager;

    // 쿨다운 관리: "processId:metricType" → 마지막 전송 시각
    private final Map<String, Instant> lastNotified = new ConcurrentHashMap<>();

    public EmailNotificationService(JavaMailSender mailSender, JprmProperties props,
                                     ProcessManager processManager) {
        this.mailSender = mailSender;
        this.props = props;
        this.processManager = processManager;
    }

    /**
     * 임계값 초과 이벤트 리스트를 받아 이메일을 전송한다.
     * 쿨다운 기간 내 동일 유형 알림은 무시한다.
     */
    public void notify(List<ThresholdEvent> events) {
        if (!isEnabled() || events.isEmpty()) return;

        for (ThresholdEvent event : events) {
            String key = event.processId() + ":" + event.metricType();

            // 쿨다운 체크
            Instant lastSent = lastNotified.get(key);
            int cooldown = props.getNotification().getCooldownSeconds();
            if (lastSent != null && Instant.now().isBefore(lastSent.plusSeconds(cooldown))) {
                log.debug("Notification cooldown active for {}, skipping", key);
                continue;
            }

            try {
                sendEmail(event);
                lastNotified.put(key, Instant.now());
                log.info("📧 Alert email sent: {} {} {:.1f} > {:.1f}",
                        event.processId(), event.metricType(),
                        event.actualValue(), event.thresholdValue());
            } catch (Exception e) {
                log.error("Failed to send alert email for {}: {}", key, e.getMessage());
            }
        }
    }

    private void sendEmail(ThresholdEvent event) throws MessagingException {
        JprmProperties.Notification.Email emailConfig = props.getNotification().getEmail();
        List<String> recipients = emailConfig.getTo();
        if (recipients.isEmpty()) {
            log.warn("No email recipients configured, skipping notification");
            return;
        }

        MonitoredProcess proc = processManager.getProcess(event.processId());
        String processLabel = proc != null ? proc.getLabel() : event.processId();
        long pid = proc != null ? proc.getPid() : -1;

        String subject = String.format("%s %s - %s Threshold Exceeded",
                emailConfig.getSubjectPrefix(), processLabel, event.metricType());

        String htmlBody = buildHtmlBody(event, processLabel, pid);

        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
        helper.setFrom(emailConfig.getFrom());
        helper.setTo(recipients.toArray(new String[0]));
        helper.setSubject(subject);
        helper.setText(htmlBody, true);

        mailSender.send(message);
    }

    private String buildHtmlBody(ThresholdEvent event, String processLabel, long pid) {
        String metricUnit = switch (event.metricType()) {
            case "CPU" -> "%";
            case "HEAP" -> "%";
            case "RSS" -> " MB";
            default -> "";
        };

        String severityColor = event.actualValue() > event.thresholdValue() * 1.2 ? "#e74c3c" : "#f39c12";

        return """
                <!DOCTYPE html>
                <html>
                <head><meta charset="UTF-8"></head>
                <body style="font-family:'Segoe UI',Arial,sans-serif; background:#f5f5f5; padding:20px;">
                  <div style="max-width:600px; margin:0 auto; background:#fff; border-radius:12px; overflow:hidden; box-shadow:0 2px 12px rgba(0,0,0,0.1);">
                    <!-- Header -->
                    <div style="background:#1e293b; padding:24px 32px; color:#fff;">
                      <h1 style="margin:0; font-size:20px;">⚠️ JPRM Alert</h1>
                      <p style="margin:4px 0 0; color:#94a3b8; font-size:13px;">Java Process Resource Monitor — Threshold Violation</p>
                    </div>
                    <!-- Body -->
                    <div style="padding:32px;">
                      <table style="width:100%%; border-collapse:collapse; font-size:14px;">
                        <tr>
                          <td style="padding:10px 0; color:#64748b; width:140px;">Process</td>
                          <td style="padding:10px 0; font-weight:600;">%s (PID: %d)</td>
                        </tr>
                        <tr>
                          <td style="padding:10px 0; color:#64748b;">Metric</td>
                          <td style="padding:10px 0; font-weight:600;">%s</td>
                        </tr>
                        <tr>
                          <td style="padding:10px 0; color:#64748b;">Current Value</td>
                          <td style="padding:10px 0;">
                            <span style="background:%s; color:#fff; padding:4px 12px; border-radius:6px; font-weight:700; font-size:16px;">
                              %.1f%s
                            </span>
                          </td>
                        </tr>
                        <tr>
                          <td style="padding:10px 0; color:#64748b;">Threshold</td>
                          <td style="padding:10px 0; font-weight:500;">%.1f%s</td>
                        </tr>
                        <tr>
                          <td style="padding:10px 0; color:#64748b;">Time</td>
                          <td style="padding:10px 0;">%s</td>
                        </tr>
                      </table>
                    </div>
                    <!-- Footer -->
                    <div style="background:#f8fafc; padding:16px 32px; border-top:1px solid #e2e8f0; color:#94a3b8; font-size:12px;">
                      Sent by JPRM v1.0 · <a href="http://localhost:8080" style="color:#3b82f6;">Open Dashboard</a>
                    </div>
                  </div>
                </body>
                </html>
                """.formatted(
                processLabel, pid,
                event.metricType(),
                severityColor,
                event.actualValue(), metricUnit,
                event.thresholdValue(), metricUnit,
                TIME_FMT.format(event.timestamp())
        );
    }

    public boolean isEnabled() {
        return props.getNotification().isEnabled()
                && props.getNotification().getEmail().isEnabled();
    }
}
