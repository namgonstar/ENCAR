-- AB test 결과 분석 쿼리 (platform 에 따라 서로다른 컬럼에 들어오는 것을 통합하여 처리 하는 쿼리)
-- Mobile : ABTEST 컬럼
-- App : TESTTYPE 컬럼

-- MW 내차팔기 홈 디폴트 랜딩 AB test 
-- AB test 실험 참여된 시점 이후부터 모든 이벤트에 해당 컬럼으로 덮어 씌운 뒤 진행 -> 이유는 특정 페이지에서만 AB test 컬럼이 들어온다고 함. 그래서 정작 봐야하는 이벤트에 AB test 컬럼이 없기 때문에 이렇게 후처리로 진행.
-- 이 쿼리로 할 경우 원래 데이터(ver.1) 보다 -0.5% 정도 의 모수 차이가 남.

SET abtestId = 'ab_685cd44042161e1e5fb4245c';           -- 분석 대상 AB test ID
SET start_date = '2025-06-30';                          -- 분석 시작일
SET end_date = '2025-07-07';                            -- 분석 종료일
-- SET end_date = '2025-06-30';                            -- 분석 종료일

WITH 

log_base AS (

    SELECT
        BASE_DATE,
        EVENTTIME,
        PCID,
        ABTEST,
        TESTTYPE,
        SCREENNAME,
        EVENTTYPE,
        EVENTNAME,
        EVENTNAMEGROUP,
        BOARD,
        STATUS,
        OS_TYPE,
        OS_DETAIL,
        NULLIF(TRIM(f.value::STRING), '') AS ABTEST_SPLIT,
        SPLIT_PART(ABTEST_SPLIT, '_', 1) || '_' || SPLIT_PART(ABTEST_SPLIT, '_', 2) AS ABTEST_ID,
        SPLIT_PART(ABTEST_SPLIT, '_', 3) AS ABTEST_GROUP,
    FROM
        ENCAR.LOGS.ENLOG_ENCAR AS t1,
        LATERAL FLATTEN(input => SPLIT(t1.ABTEST, ',')) AS f
    WHERE
        1=1
        AND BASE_DATE BETWEEN $start_date AND $end_date
        AND OS_TYPE = 'mw'
        -- AND NOT (ess.OS_TYPE = 'app' AND ess.OS_DETAIL = 'ios')
),

mw_test_join_dt AS (        -- PCID 별 ABTEST 실험 최초참여시간 GROUP (Mobile web)

    SELECT
        PCID,
        EVENTTIME AS TEST_JOIN_DT,
        ABTEST_ID,
        ABTEST_GROUP,
    FROM
        log_base
    WHERE
        1=1
        AND ABTEST_ID = $abtestId
        AND OS_TYPE IN ('mw', 'pc')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY PCID ORDER BY EVENTTIME) = 1        -- 최초 실험 참여시점의 행만 가져오는 로직
),

app_test_join_dt AS (         -- PCID 별 ABTEST 실험 최초참여시간 GROUP (App)

    SELECT
        PCID,
        EVENTTIME AS TEST_JOIN_DT,
        $abtestId AS ABTEST_ID,
        TESTTYPE AS ABTEST_GROUP,
    FROM
        log_base
    WHERE
        1=1
        AND OS_TYPE = 'app'
        AND TESTTYPE IS NOT NULL
        AND TESTTYPE != ''
    QUALIFY ROW_NUMBER() OVER (PARTITION BY PCID ORDER BY EVENTTIME) = 1                -- 최초 실험 참여시점의 행만 가져오는 로직
),

totl_test_join_dt AS (
    SELECT * FROM mw_test_join_dt
    UNION ALL
    SELECT * FROM app_test_join_dt
),

prep AS (
    SELECT
        t1.PCID,
        t1.BASE_DATE,
        t1.SCREENNAME,
        t1.EVENTTYPE,
        t1.EVENTNAME,
        t1.EVENTNAMEGROUP,
        t1.BOARD,
        t1.STATUS,
        t1.OS_TYPE,
        t1.OS_DETAIL,
        t2.ABTEST_ID,
        t2.ABTEST_GROUP,
    FROM
        log_base AS t1
        LEFT JOIN totl_test_join_dt AS t2 ON t1.PCID = t2.PCID AND t1.EVENTTIME >= t2.TEST_JOIN_DT
    WHERE
        1=1
        AND t2.ABTEST_ID IS NOT NULL
)

SELECT
    ABTEST_ID,
    MIN(BASE_DATE) AS START_DATE,
    MAX(BASE_DATE) AS END_DATE,
    OS_TYPE,
    ABTEST_GROUP,
    -- OS_DETAIL,
    -- BASE_DATE,
    
    COUNT(DISTINCT PCID) AS TOTAL_PCID,
    COUNT(PCID) AS TOTAL_EVENT,

    -- 내차팔기 영역
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '엔카홈' AND BOARD ='내차팔기' THEN PCID END) AS SELL_HOME,       -- 내차팔기 퍼널 1 - 번호판 조회
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '비교견적신청_소유자확인' THEN PCID END) AS CHECK_OWNER,              -- 내차팔기 퍼널 2- 소유자 확인
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '비교견적신청_정보확인중' THEN PCID END) AS TRY_MYGARAGE,              -- 내차팔기 퍼널 3- 내차고 등록 시도
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '엔카홈' AND BOARD = '내차고' AND STATUS = '정보입력중' THEN PCID END) AS MYCAR_HOME_ING,
    -- -- 비교견적 신청 완료 이벤트
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME IN ('비교견적신청_신청완료', '비교견적신청_프로신청완료', '비교견적플러스신청_신청완료') THEN PCID END) AS ESTIMATE_COMPLETE,


    -- 내차사기 영역
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '엔카홈' AND BOARD ='내차사기' THEN PCID END) AS BUY_HOME,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '검색'                      THEN PCID END) AS SEARCH_HOME,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '차량상세'                   THEN PCID END) AS CAR_DETAIL,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '차량상세' AND EVENTNAME  IN ('문의하기', '엔카를통해구매하기') THEN PCID END) AS CAR_DETAIL_CONTACT,
    
FROM
    prep
WHERE
    1=1
    -- AND ABTEST_ID1 = $abtestId
GROUP BY
    ALL
ORDER BY
    ABTEST_GROUP
;

-- 위 쿼리 결과값 
-- ABTEST_ID	START_DATE	END_DATE	OS_TYPE	ABTEST_GROUP	TOTAL_PCID	TOTAL_EVENT	SELL_HOME	CHECK_OWNER	TRY_MYGARAGE	MYCAR_HOME_ING	ESTIMATE_COMPLETE	BUY_HOME	SEARCH_HOME	CAR_DETAIL	CAR_DETAIL_CONTACT
-- ab_685cd44042161e1e5fb4245c	2025-06-30	2025-07-07	mw	A	385312	277322522	32007	8339	7152	6582	631	309623	336439	283457	6711
-- ab_685cd44042161e1e5fb4245c	2025-06-30	2025-07-07	mw	B	42586	30418540	40703	2240	1711	1535	71	32054	35679	30606	725