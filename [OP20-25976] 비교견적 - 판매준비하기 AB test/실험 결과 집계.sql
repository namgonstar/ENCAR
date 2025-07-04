-- AB test 결과 분석 쿼리 (platform 에 따라 서로다른 컬럼에 들어오는 것을 통합하여 처리 하는 쿼리)
-- Mobile : ABTEST 컬럼
-- App : TESTTYPE 컬럼

-- 판매준비하기 AB test 쿼리 ver.2
-- AB test 실험 참여된 시점 이후부터 모든 이벤트에 해당 컬럼으로 덮어 씌운 뒤 진행 -> 이유는 특정 페이지에서만 AB test 컬럼이 들어온다고 함. 그래서 정작 봐야하는 이벤트에 AB test 컬럼이 없기 때문에 이렇게 후처리로 진행.
-- 이 쿼리로 할 경우 원래 데이터(ver.1) 보다 -0.5% 정도 의 모수 차이가 남.

SET abtestId = 'ab_6821560d42161e1e5fb42456';           -- 분석 대상 AB test ID
SET start_date = '2025-05-13';                          -- 분석 시작일
SET end_date = '2025-06-23';                            -- 분석 종료일

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
        STATUS,
        OS_TYPE,
        OS_DETAIL,
        NULLIF(TRIM(f.value::STRING), '') AS ABTEST_SPLIT,
        SPLIT_PART(ABTEST_SPLIT, '_', 1) || '_' || SPLIT_PART(ABTEST_SPLIT, '_', 2) AS ABTEST_ID,
        SPLIT_PART(ABTEST_SPLIT, '_', 3) AS ABTEST_GROUP,
    FROM
        ENCAR.ANALYSIS_MART.ESTIMATE_SESSION_STAGE AS ess,
        LATERAL FLATTEN(input => SPLIT(ess.ABTEST, ',')) AS f
    WHERE
        1=1
        AND BASE_DATE BETWEEN $start_date AND $end_date
        AND NOT (ess.OS_TYPE = 'app' AND ess.OS_DETAIL = 'ios')         -- App-ios 는 전부 Group A에만 분배된 이슈 발견되었기 때문에 이는 제외하려고 함
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
        t1.STATUS,
        t1.OS_TYPE,
        t1.OS_DETAIL,
        t2.ABTEST_ID,
        t2.ABTEST_GROUP
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
    ABTEST_GROUP,
    -- BASE_DATE,
    COUNT(DISTINCT PCID) AS CNT_TOTAL_PCID,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '내차고_엔카홈' THEN PCID END) AS CNT_MYCAR_HOME,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '내차고_엔카홈' AND STATUS = '정보입력중' THEN PCID END) AS CNT_MYCAR_HOME_ING,
    
    -- 비교견적 신청 클릭 이벤트
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '내차고_엔카홈' AND EVENTNAME IN ('비교견적신청', '내차가격알아보기') THEN PCID END) AS CNT_ESTIMATE_CLICK_TOTAL,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '내차고_엔카홈' AND EVENTNAME = '비교견적신청' THEN PCID END) AS CNT_ESTIMATE_CLICK1,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '내차고_엔카홈' AND EVENTNAME = '내차가격알아보기' THEN PCID END) AS CNT_ESTIMATE_CLICK2,

    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '내차고_엔카홈' AND EVENTNAME = '시작하기' AND EVENTNAMEGROUP = '경매방식' THEN PCID END) AS CNT_ESTIMATE_FINAL_CLICK,
    


    -- CNT 0으로 찍히는 이벤트

    -- 판매진입하기 진입율
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '비교견적판매준비하기' THEN PCID END) AS CNT_READY_TO_SELL,
    -- 판매준비하기 작성 완료율
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME LIKE '비교견적판매준비하기%' AND EVENTNAME = '등록완료' THEN PCID END) AS CNT_READY_TO_SELL_CONFIRM,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '비교견적판매준비하기_희망가입력' AND EVENTNAME = '등록완료' THEN PCID END) AS CNT_PRICE_CONFIRM,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '비교견적판매준비하기_사진' AND EVENTNAME = '등록완료' THEN PCID END) AS CNT_PHOTO_CONFIRM,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '비교견적판매준비하기_차량정보' AND EVENTNAME = '등록완료' THEN PCID END) AS CNT_INFO_CONFIRM,
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '비교견적판매준비하기_견적첨부' AND EVENTNAME = '등록완료' THEN PCID END) AS CNT_ESTIMATE_CONFIRM,

    
    
    -- 비교견적 신청 클릭 이벤트    
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'CLICK' AND SCREENNAME = '비교견적판매준비하기' AND EVENTNAME = '비교견적신청' THEN PCID END) AS CNT_ESTIMATE_CLICK,

    -- 비교견적 신청 완료 이벤트
    COUNT(DISTINCT CASE WHEN EVENTTYPE = 'VIEW' AND SCREENNAME IN ('비교견적신청_신청완료', '비교견적신청_프로신청완료', '비교견적플러스신청_신청완료') THEN PCID END) AS CNT_ESTIMATE_COMPLETE,    
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