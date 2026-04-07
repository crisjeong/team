package com.jprm.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;
import com.jprm.web.MetricsWebSocketHandler;

/**
 * WebSocket 설정 — /ws/metrics 엔드포인트 등록.
 */
@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    private final MetricsWebSocketHandler metricsHandler;

    public WebSocketConfig(MetricsWebSocketHandler metricsHandler) {
        this.metricsHandler = metricsHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(metricsHandler, "/ws/metrics")
                .setAllowedOrigins("*");
    }
}
