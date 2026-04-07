package com.jprm.model;

/**
 * 모니터링 대상 프로세스의 상태.
 */
public enum ProcessStatus {
    /** 프로세스가 실행 중이고 모니터링 활성 */
    RUNNING,
    /** 사용자에 의해 중지됨 */
    STOPPED,
    /** 프로세스가 자연 종료됨 */
    EXITED,
    /** 프로세스 시작 실패 */
    FAILED
}
