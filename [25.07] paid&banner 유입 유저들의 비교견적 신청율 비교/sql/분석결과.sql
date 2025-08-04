SET start_date = DATE('2025-07-22');
SET end_date = DATE('2025-07-29');

WITH

user_master AS (    -- 1. PCID 별 대표 userid 부여하는 로직 (해당 기간동안 계속 비회원이면 비회원, 해당기간동안 한번이라도 로그인하면 최초 로그인 한 userid 로 부여)
    SELECT
        DISTINCT PCID,
        FIRST_VALUE(USERID) IGNORE NULLS OVER (PARTITION BY PCID ORDER BY BASE_DATE) AS pcid_userid     -- user id 는 이거로 쓰면 됨
        -- ROW_NUMBER() OVER (PARTITION BY PCID ORDER BY BASE_DATE) AS rn,
    FROM
        ENCAR.LOGS_MART.USER_MASTER_ALL
    WHERE
        1=1
        AND base_date BETWEEN $start_date AND $end_date
),
        -- AND PCID = '00008A2F79A64BC2842177950D43FDF8' -> 아주 좋은 예시.

user AS (           -- 1-1.
    SELECT
        ID,             -- 비회원용 부여 id = 'qlry'
        USER_STATUS,    -- 회원/탈퇴/휴면/이용정지/삭제 등등...
        GRADE,
        -- 딜러 / 유저 / 비회원 구분하는 로직
        CASE 
            WHEN GRADE IN ('0', '2')                THEN 'dealer'
            WHEN GRADE = '1' AND ID != 'qlry'       THEN 'member'
            WHEN GRADE = '1' AND ID = 'qlry'        THEN 'non_member'
            ELSE 'Out' END AS user_type,
        
        -- 비회원일 경우 join_dt 삭제하는 로직
        CASE
            WHEN GRADE = '1' AND ID = 'qlry'        THEN NULL
            ELSE JOIN_DT END AS JOIN_DT,
    FROM
        ENCAR.LOGS_MART.ENCAR_USER
    WHERE
        1=1
),

user_base AS (      -- 1-3. 최종 user 정보 정리 테이블
    SELECT
        t1.PCID,
        t1.pcid_userid,
        t2.JOIN_DT,
        CASE
            WHEN t2.user_type IS NOT NULL THEN t2.user_type
            WHEN t2.user_type IS NULL THEN 'non_member' END AS user_type,
    FROM
        user_master AS t1
        LEFT JOIN user AS t2 ON t1.pcid_userid = t2.id
    WHERE
        1=1
),

-- 최종 설명 1. PCID 별 user id 부여 및 딜러/유저 구분

external_user AS (  -- 2. MKT 관련 external 여부 확인하는 테이블 조건은 해당 기간동안의 가장 첫 SOURCE 값이 external / organic / internal 중 해당 하는 값으로 분류
    SELECT
        DISTINCT PCID,
        FIRST_VALUE(SOURCE) IGNORE NULLS OVER (PARTITION BY PCID ORDER BY BASE_DATE) AS FIRST_SOURCE     -- user id 는 이거로 쓰면 됨
    FROM
        ENCAR.LOGS_MART.USER_ATTRIBUTION_PERIOD
    WHERE
        1=1
        AND PERIOD_TYPE = 'd10'                                 -- 외부유입 기여 10일
        AND SOURCE = 'external'
        AND BASE_DATE BETWEEN $start_date AND $end_date
),

user_final AS (     -- 3. (1+2) 최종 테이블 - PCID <- userid, usertype, external 여부 붙인 최종 테이블
    SELECT
        t1.PCID,
        t1.pcid_userid,
        t1.user_type,
        t1.JOIN_DT,
        CASE
            WHEN t2.FIRST_SOURCE IS NOT NULL THEN t2.FIRST_SOURCE
            ELSE 'organic' END AS SOURCE                                -- external 이 아닌 PCID 는 모두 organic
    FROM
        user_base AS t1
        LEFT JOIN external_user AS t2 ON t2.PCID = t1.PCID
),

-- user_base = external_user 의 총 PCID 카운트는 정확히 동일 너무 좋다.


log_base AS (                   -- 1. log 원천
    SELECT
        t1.BASE_DATE,
        t1.EVENTTIME,
        t1.PCID,
        t1.SCREENNAME,
        t1.EVENTTYPE,
        t1.EVENTNAME,
        t1.EVENTNAMEGROUP,
        t1.STATUS,
        t1.BEF_SCREENNAME,
        t1.BEF_BOARD,
        t1.BEF_EVENTNAMEGROUP,
        t1.HIT,
        t1.ATTRIBUTES,
        t1.ESTIMATEID,
        t1.OS_TYPE,
        t1.OS_DETAIL,
        
        t2.pcid_userid,
        t2.user_type,
        t2.JOIN_DT,
        t2.SOURCE,
        
        
    FROM
        ENCAR.ANALYSIS_MART.ESTIMATE_SESSION_STAGE AS t1
        LEFT JOIN user_final AS t2 ON t2.PCID = t1.PCID
    WHERE
        1=1
        AND BASE_DATE BETWEEN $start_date AND $end_date
),

log_with_flags AS (             -- 2. log 원천 -> row별 특정 액션 여부 1,0 부여
    SELECT 
        PCID,
        SOURCE,
        USER_TYPE,
        OS_TYPE,
        OS_DETAIL,
        
        -- 이벤트 1.        내차팔기 홈
        MAX(CASE 
            WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '내차팔기_엔카홈'
            THEN 1 ELSE 0 END) AS is_sell_home,

        -- 이벤트 2. 배너 -> 내차팔기 홈
        MAX(CASE 
            WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '내차팔기_엔카홈' AND HIT = 'indextop'     --  → 상단배너 클릭으로 들어온 진입한 경우엔 hit값이 indextop 으로 찍힘
            THEN 1 ELSE 0 END) AS is_banner_to_sell_home,

        -- 이벤트 3. 내차고 등록 완료 여부
        MAX(CASE 
            WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '내차고_엔카홈'
                 AND BEF_SCREENNAME IN (
                    '비교견적신청_정보확인중','비교견적신청_커피이벤트','비교견적신청_제조사수기선택','비교견적신청_화물제조사',
                    '비교견적신청_세부등급','비교견적신청_등급','비교견적신청_화물적재용량','비교견적신청_변속기','비교견적신청_연료',
                    '비교견적신청_화물변속기','비교견적신청_기타옵션','비교견적신청_화물등급','비교견적신청_형식연도수기선택',
                    '비교견적신청_화물모델연도','비교견적신청_화물모델','비교견적신청_화물세부형식','비교견적신청_화물승용선택',
                    '비교견적신청_화물형식','비교견적신청_등급수기선택','비교견적신청_리스','비교견적신청_세부모델수기선택',
                    '비교견적신청_세부등급수기선택','비교견적신청_모델수기선택','비교견적신청_화물연료','비교견적신청_모델',
                    '비교견적신청_연식수기선택','비교견적신청_화물적재규격','비교견적신청_화물연식'
                 )
            THEN 1 ELSE 0 END) AS is_mygarage_complete,

        -- 이벤트 4. 판매준비하기 진입 여부
        MAX(CASE
            WHEN EVENTTYPE = 'VIEW' AND SCREENNAME = '비교견적판매준비하기' THEN 1 ELSE 0 END) AS is_ready_to_sell,

        -- 이벤트 5. 빅교견적 신청 완료 여부
        MAX(CASE 
            WHEN EVENTTYPE = 'VIEW' AND SCREENNAME IN ('비교견적_신청완료', '비교견적신청_프로신청완료', '비교견적플러스신청_신청완료')
            THEN 1 ELSE 0 END) AS is_estimate_complete,
    FROM log_base
    GROUP BY
        ALL
),

prep AS (
    SELECT
        SOURCE,
        COUNT(DISTINCT PCID) AS CNT_PCID,
        COUNT(DISTINCT CASE WHEN is_sell_home = 1 THEN PCID END) AS SELL_HOME,
        COUNT(DISTINCT CASE WHEN is_sell_home = 1 AND is_mygarage_complete = 1 THEN PCID END) AS MYGARAGE_COMPLETE,
        COUNT(DISTINCT CASE WHEN is_sell_home = 1 AND is_mygarage_complete = 1 AND is_estimate_complete = 1 THEN PCID END) AS ESTIMATE_COMPLETE,
        -- COUNT(DISTINCT CASE WHEN is_mygarage_complete = 1 AND is_ready_to_sell = 1 THEN PCID END) AS READY_TO_SELL,
        
        -- 배너 클릭을 통해 내차팔기 홈 진입한 유저
        COUNT(DISTINCT CASE WHEN is_banner_to_sell_home = 1 THEN PCID END) AS BANNER_TO_SELL_HOME,
        COUNT(DISTINCT CASE WHEN is_banner_to_sell_home = 1 AND is_mygarage_complete = 1 THEN PCID END) AS BANNER_TO_MYGARAGE_COMPLETE,
        COUNT(DISTINCT CASE WHEN is_banner_to_sell_home = 1 AND is_mygarage_complete = 1 AND is_estimate_complete = 1 THEN PCID END) AS BANNER_TO_ESTIMATE_COMPLETE,
        -- COUNT(DISTINCT CASE WHEN is_banner_to_sell_home = 1 AND is_mygarage_complete = 1 AND is_ready_to_sell = 1 THEN PCID END) AS BANNER_TO_READY_TO_SELL,
    FROM
        log_with_flags
    WHERE
        1=1
        AND user_type NOT IN ('Out', 'dealer')        -- 탈퇴 및 딜러 유저 제외
    GROUP BY 
        GROUPING SETS ((SOURCE), ())
)

SELECT
    $start_date,
    $end_date,
    *
FROM
    prep
ORDER BY
    SOURCE
;