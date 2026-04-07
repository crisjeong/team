package com.jprm.web;

import oshi.SystemInfo;
import oshi.hardware.CentralProcessor;
import oshi.hardware.GlobalMemory;
import oshi.hardware.HardwareAbstractionLayer;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 시스템 정보 API.
 */
@RestController
@RequestMapping("/api/system")
public class SystemController {

    @GetMapping
    public Map<String, Object> getSystemInfo() {
        SystemInfo si = new SystemInfo();
        HardwareAbstractionLayer hal = si.getHardware();
        CentralProcessor cpu = hal.getProcessor();
        GlobalMemory memory = hal.getMemory();

        return Map.of(
                "os", si.getOperatingSystem().toString(),
                "cpuName", cpu.getProcessorIdentifier().getName(),
                "cpuCores", cpu.getLogicalProcessorCount(),
                "totalMemoryMB", memory.getTotal() / (1024 * 1024),
                "availableMemoryMB", memory.getAvailable() / (1024 * 1024),
                "jdkVersion", System.getProperty("java.version"),
                "jdkVendor", System.getProperty("java.vendor")
        );
    }
}
