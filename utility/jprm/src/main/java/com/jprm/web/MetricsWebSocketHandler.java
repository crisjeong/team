package com.jprm.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jprm.model.ResourceSnapshot;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * WebSocket 핸들러 — 실시간 메트릭을 연결된 모든 브라우저에 push.
 */
@Component
public class MetricsWebSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(MetricsWebSocketHandler.class);
    private final Set<WebSocketSession> sessions = ConcurrentHashMap.newKeySet();
    private final ObjectMapper objectMapper;

    public MetricsWebSocketHandler(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        sessions.add(session);
        log.info("WebSocket connected: {}", session.getId());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        sessions.remove(session);
        log.info("WebSocket disconnected: {} ({})", session.getId(), status);
    }

    /**
     * 특정 프로세스의 메트릭을 모든 연결된 클라이언트에 전송한다.
     */
    public void broadcastMetric(String processId, ResourceSnapshot snapshot) {
        if (sessions.isEmpty()) return;

        try {
            Map<String, Object> payload = Map.of(
                    "type", "metric",
                    "processId", processId,
                    "data", snapshot
            );
            String json = objectMapper.writeValueAsString(payload);
            TextMessage message = new TextMessage(json);

            for (WebSocketSession session : sessions) {
                if (session.isOpen()) {
                    try {
                        synchronized (session) {
                            session.sendMessage(message);
                        }
                    } catch (Exception e) {
                        log.debug("Failed to send to session {}: {}", session.getId(), e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Failed to serialize metric payload: {}", e.getMessage());
        }
    }

    /**
     * 프로세스 상태 변경을 알린다.
     */
    public void broadcastStatusChange(String processId, String status) {
        if (sessions.isEmpty()) return;

        try {
            Map<String, Object> payload = Map.of(
                    "type", "status",
                    "processId", processId,
                    "status", status
            );
            String json = objectMapper.writeValueAsString(payload);
            TextMessage message = new TextMessage(json);

            for (WebSocketSession session : sessions) {
                if (session.isOpen()) {
                    try {
                        synchronized (session) {
                            session.sendMessage(message);
                        }
                    } catch (Exception e) {
                        log.debug("WS send error: {}", e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Failed to serialize status payload: {}", e.getMessage());
        }
    }

    /**
     * 임계값 초과 알림을 모든 클라이언트에 전송한다.
     */
    public void broadcastAlert(String processId, java.util.List<com.jprm.model.ThresholdEvent> events) {
        if (sessions.isEmpty() || events.isEmpty()) return;

        try {
            java.util.Map<String, Object> payload = java.util.Map.of(
                    "type", "alert",
                    "processId", processId,
                    "events", events
            );
            String json = objectMapper.writeValueAsString(payload);
            TextMessage message = new TextMessage(json);

            for (WebSocketSession session : sessions) {
                if (session.isOpen()) {
                    try {
                        synchronized (session) {
                            session.sendMessage(message);
                        }
                    } catch (Exception e) {
                        log.debug("WS alert send error: {}", e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Failed to serialize alert payload: {}", e.getMessage());
        }
    }
}
