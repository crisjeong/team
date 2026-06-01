/**
 * OHT 통신 스레드에서의 HexUtils 적용 예시
 * 
 * 기존 String.format() 코드와 Lookup Table 대안 코드를 비교합니다.
 */
public class OhtCommThreadExample {

    private static final org.slf4j.Logger logger =
            org.slf4j.LoggerFactory.getLogger(OhtCommThreadExample.class);

    // ================================================================
    //  ❌ 기존 코드 (String.format 사용)
    // ================================================================
    public void onPacketReceived_BEFORE(byte[] data) {
        // 30바이트 패킷을 10바이트씩 나눠서 hex 로깅
        for (int offset = 0; offset < data.length; offset += 10) {
            StringBuilder sb = new StringBuilder();
            int end = Math.min(offset + 10, data.length);
            for (int i = offset; i < end; i++) {
                sb.append(String.format("%02X ", data[i]));
                // ↑ 바이트마다: regex 파싱 + 7~8개 임시 객체 생성
                //   30바이트 패킷 → 30회 호출 → ~210개 임시 객체
            }
            logger.debug(sb.toString());
        }
    }

    // ================================================================
    //  ✅ 개선 코드 방법 1: 한번에 포맷된 문자열 생성
    // ================================================================
    public void onPacketReceived_AFTER_v1(byte[] data) {
        // Guard Clause: 로그 레벨이 DEBUG가 아니면 즉시 리턴
        // → 프로덕션(INFO 레벨)에서는 CPU 사용 0%
        if (!logger.isDebugEnabled()) {
            return;
        }

        // 30바이트를 10바이트 단위로 정렬된 hex string으로 변환
        // 내부에서 Lookup Table 사용 → 임시 객체 최소화
        String hexDump = HexUtils.toFormattedHex(data, 10);
        logger.debug("Received packet:\n{}", hexDump);

        // 출력 예:
        // Received packet:
        // 0A 1B 2C 3D 4E 5F 6A 7B 8C 9D
        // AA BB CC DD EE FF 00 11 22 33
        // 44 55 66 77 88 99
    }

    // ================================================================
    //  ✅ 개선 코드 방법 2: 기존 라인별 로깅 패턴 유지
    //     (기존 로그 포맷과 완전히 동일한 출력을 원할 경우)
    // ================================================================
    public void onPacketReceived_AFTER_v2(byte[] data) {
        if (!logger.isDebugEnabled()) {
            return;
        }

        // Consumer 콜백으로 10바이트씩 라인별 로깅
        HexUtils.forEachHexLine(data, 10, hexLine -> {
            logger.debug(hexLine);
        });

        // 출력 예: (기존과 동일한 라인 단위 출력)
        // 0A 1B 2C 3D 4E 5F 6A 7B 8C 9D
        // AA BB CC DD EE FF 00 11 22 33
        // 44 55 66 77 88 99
    }

    // ================================================================
    //  ✅ 개선 코드 방법 3: 가장 간결한 방식
    //     (별도 유틸 없이 인라인으로 적용 가능)
    // ================================================================

    // 클래스 레벨 상수 (1회만 생성, 모든 스레드에서 공유)
    private static final char[] HEX = "0123456789ABCDEF".toCharArray();

    public void onPacketReceived_AFTER_v3(byte[] data) {
        if (!logger.isDebugEnabled()) {
            return;
        }

        for (int offset = 0; offset < data.length; offset += 10) {
            int end = Math.min(offset + 10, data.length);
            int len = end - offset;

            // char 배열에 직접 hex 문자 기록 → String.format() 완전 제거
            char[] buf = new char[len * 3 - 1];
            for (int i = 0; i < len; i++) {
                int v = data[offset + i] & 0xFF;
                int pos = i * 3;
                buf[pos]     = HEX[v >>> 4];
                buf[pos + 1] = HEX[v & 0x0F];
                if (i < len - 1) {
                    buf[pos + 2] = ' ';
                }
            }
            logger.debug(new String(buf));
        }
    }
}
