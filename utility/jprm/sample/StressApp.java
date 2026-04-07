import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * JPRM 테스트용 — CPU 및 메모리 부하를 발생시키는 샘플 애플리케이션.
 *
 * 사용법: java StressApp [duration_seconds] [mode]
 *   mode: cpu | memory | both (default: both)
 *   duration: 실행 시간 초 (default: 60)
 */
public class StressApp {

    private static final Random random = new Random();
    private static volatile boolean running = true;

    public static void main(String[] args) throws InterruptedException {
        int duration = args.length > 0 ? Integer.parseInt(args[0]) : 60;
        String mode = args.length > 1 ? args[1] : "both";

        System.out.println("=== JPRM StressApp ===");
        System.out.println("Mode: " + mode);
        System.out.println("Duration: " + duration + "s");
        System.out.println("PID: " + ProcessHandle.current().pid());

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            running = false;
            System.out.println("StressApp shutting down...");
        }));

        long endTime = System.currentTimeMillis() + (duration * 1000L);

        // Memory stress thread
        Thread memThread = null;
        if ("memory".equals(mode) || "both".equals(mode)) {
            memThread = Thread.startVirtualThread(() -> memoryStress(endTime));
        }

        // CPU stress thread
        Thread cpuThread = null;
        if ("cpu".equals(mode) || "both".equals(mode)) {
            cpuThread = Thread.startVirtualThread(() -> cpuStress(endTime));
        }

        // Status printer
        while (running && System.currentTimeMillis() < endTime) {
            Runtime rt = Runtime.getRuntime();
            long used = (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024);
            long max = rt.maxMemory() / (1024 * 1024);
            System.out.printf("[%ds] Heap: %d/%d MB, Threads: %d%n",
                    (endTime - System.currentTimeMillis()) / 1000,
                    used, max, Thread.activeCount());
            Thread.sleep(5000);
        }

        running = false;
        System.out.println("StressApp completed.");
    }

    private static void cpuStress(long endTime) {
        System.out.println("CPU stress started");
        while (running && System.currentTimeMillis() < endTime) {
            // 50% duty cycle: 100ms work, 100ms sleep
            long workEnd = System.currentTimeMillis() + 100;
            while (System.currentTimeMillis() < workEnd) {
                Math.sqrt(random.nextDouble() * 1_000_000);
            }
            try { Thread.sleep(100); } catch (InterruptedException e) { break; }
        }
    }

    @SuppressWarnings("MismatchedQueryAndUpdateOfCollection")
    private static void memoryStress(long endTime) {
        System.out.println("Memory stress started");
        List<byte[]> blocks = new ArrayList<>();
        try {
            while (running && System.currentTimeMillis() < endTime) {
                // 매 2초마다 1MB 할당
                blocks.add(new byte[1024 * 1024]);
                Thread.sleep(2000);

                // 20MB 초과 시 절반 해제 (톱니파 패턴)
                if (blocks.size() > 20) {
                    int halfSize = blocks.size() / 2;
                    blocks.subList(0, halfSize).clear();
                    System.gc();
                }
            }
        } catch (InterruptedException e) {
            // shutdown
        }
    }
}
