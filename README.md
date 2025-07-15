업무 성격별 파일 디렉토리 및 파일 구성

# 1. AB test
예상 파일 리스트
1. 실험 결과.sql            -> 해당 AB test 의 총 기간 동안의 Group 별 결과 값
2. 실험 결과(daily).sql     -> 해당 AB test 의 총 기간 동안의 Group 별 결과 값 Daily
3. 통계 검정.ipynb          -> 위 sql 로 나온 그룹별 실험 결과 지표에 대한 통계 검정
4. Wiki.pdf               -> AB test 최종 리포트




-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------



### 📌 Git 브랜치 네이밍 규칙 (for 데이터 분석가)

- 형식: <prefix>/<업무명>-<간단설명>
- 예시: `analysis/user-retention`, `report/june-kpi`, `abtest/cta-button`

#### ✅ 추천 prefix
- `analysis/` : 분석 업무
- `abtest/` : 실험 분석
- `report/` : 리포트/대시보드
- `experiment/` : 임시 실험용
- `modeling/` : 모델 개발
- `etl/` : 데이터 전처리
- `visualize/` : 시각화 개선
- `docs/` : 문서 업데이트

| Prefix        | 용도               | 예시                                                       |
| ------------- | ---------------- | -------------------------------------------------------- |
| `analysis/`   | 데이터 분석 작업        | `analysis/churn-patterns`, `analysis/search-behavior`    |
| `abtest/`     | A/B 테스트 관련 분석    | `abtest/estimate-entry-cvr`, `abtest/home-banner`        |
| `report/`     | 정기 보고서, 대시보드 제작  | `report/weekly-sales`, `report/kpi-june`                 |
| `experiment/` | 실험적 분석 or 임시 코드  | `experiment/new-segmentation`, `experiment/scatter-test` |
| `modeling/`   | 모델링 관련 작업        | `modeling/price-prediction`, `modeling/user-score-v2`    |
| `etl/`        | 데이터 추출/정제 스크립트   | `etl/clean-user-tags`, `etl/merge-raw-logs`              |
| `visualize/`  | 시각화, 대시보드 개선     | `visualize/funnel-update`, `visualize/heatmap-campaign`  |
| `docs/`       | 분석 문서, README 정리 | `docs/update-methodology`, `docs/add-metric-guide`       |



파일트리 예시)

data-analysis-project/
├── README.md                      # 프로젝트 개요
├── requirements.txt              # 필요한 패키지 리스트
├── .gitignore                    # Git에 올리지 않을 파일 설정
├── notebooks/                    # Jupyter (ipynb) 파일
│   ├── abtest/
│   │   ├── abtest_cvr_july.ipynb
│   │   └── abtest_entry_test.ipynb
│   ├── eda/
│   │   └── user_behavior_eda.ipynb
│   └── modeling/
│       └── churn_model_xgb.ipynb
├── scripts/                      # Python 분석/전처리 스크립트
│   ├── etl/
│   │   ├── clean_raw_logs.py
│   │   └── merge_events.py
│   ├── analysis/
│   │   └── retention_analysis.py
│   └── viz/
│       └── plot_conversion_funnel.py
├── reports/                      # 보고서 PDF, 슬라이드, 이미지
│   ├── weekly/
│   │   └── weekly_report_2025w28.pdf
│   ├── monthly/
│   │   └── july_report.pdf
│   └── figures/
│       └── funnel_cvr_comparison.png
├── dashboards/                   # Tableau, PowerBI 등 추출파일
│   └── tableau/
│       └── monthly_dashboard.twbx
├── data/                         # 샘플 데이터 or SQL export
│   ├── raw/
│   │   └── raw_events.csv
│   └── processed/
│       └── user_summary.parquet
├── sql/                          # 분석용 쿼리 정리
│   ├── abtest/
│   │   └── estimate_conversion_cvr.sql
│   └── cohort/
│       └── monthly_retention.sql
└── docs/                         # 분석가이드, 용어정의 등 문서
    ├── metric_definitions.md
    └── abtest_guide.md
