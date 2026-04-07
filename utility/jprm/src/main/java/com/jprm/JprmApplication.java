package com.jprm;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * JPRM — Java Process Resource Monitor.
 *
 * JAR를 실행하고 CPU/메모리를 실시간 모니터링하는 웹 대시보드 도구.
 */
@SpringBootApplication
public class JprmApplication {

    public static void main(String[] args) {
        SpringApplication.run(JprmApplication.class, args);
    }
}
