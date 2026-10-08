-- 04_views.sql
-- Business rules for the dashboard, one view per report page.
-- Values in USD thousands. The fiscal year and reference date come from params.


-- ------------------------------------------------------------------ 1. Overview
-- One row: how many ideas, where they are, how many are late.
DROP VIEW IF EXISTS vw_overview;

CREATE VIEW vw_overview AS
SELECT
    COUNT(*)                                             AS total_ideas,
    SUM(status = 'Proposed')                             AS proposed,
    SUM(status = 'Under study')                          AS under_study,
    SUM(status = 'Approved')                             AS approved,
    SUM(status = 'Implemented')                          AS implemented,
    SUM(status = 'Cancelled')                            AS cancelled,
    SUM(is_delayed)                                      AS delayed,
    ROUND(SUM(CASE WHEN status = 'Implemented' THEN annual_saving_k END), 1) AS implemented_saving_k,
    ROUND(SUM(CASE WHEN is_open = 1 THEN annual_saving_k END), 1)            AS open_saving_k,
    ROUND(SUM(CASE WHEN is_delayed = 1 THEN annual_saving_k END), 1)         AS delayed_saving_k
FROM fact_idea;


-- ------------------------------------------------------------------ 2. Status by vehicle
-- Per vehicle: what is real, what is only on paper, and the gap to the target.
DROP VIEW IF EXISTS vw_vehicle_status;

CREATE VIEW vw_vehicle_status AS
WITH fy_target AS (
    SELECT t.vehicle, SUM(t.target_k) AS target_k
      FROM fact_target t, params p
     WHERE t.month_start BETWEEN p.fy_start AND p.fy_end
     GROUP BY t.vehicle
),
saving AS (
    SELECT
        vehicle,
        SUM(CASE WHEN status = 'Implemented' THEN annual_saving_k ELSE 0 END) AS implemented_k,
        SUM(CASE WHEN status = 'Approved'    THEN annual_saving_k ELSE 0 END) AS approved_k,
        SUM(CASE WHEN status = 'Under study' THEN annual_saving_k ELSE 0 END) AS under_study_k,
        SUM(CASE WHEN status = 'Proposed'    THEN annual_saving_k ELSE 0 END) AS proposed_k
      FROM fact_idea
     GROUP BY vehicle
)
SELECT
    t.vehicle,
    ROUND(t.target_k, 1)                                         AS target_k,
    ROUND(COALESCE(s.implemented_k, 0), 1)                       AS implemented_k,
    ROUND(COALESCE(s.approved_k, 0), 1)                          AS approved_k,
    ROUND(COALESCE(s.under_study_k, 0), 1)                       AS under_study_k,
    ROUND(COALESCE(s.proposed_k, 0), 1)                          AS proposed_k,
    -- what is still missing even if everything approved and under study is delivered
    ROUND(MAX(t.target_k - COALESCE(s.implemented_k, 0)
                         - COALESCE(s.approved_k, 0)
                         - COALESCE(s.under_study_k, 0), 0), 1) AS remaining_gap_k,
    ROUND(COALESCE(s.implemented_k, 0) / t.target_k, 3)          AS implemented_pct_of_target
FROM fy_target t
LEFT JOIN saving s ON s.vehicle = t.vehicle;


-- ------------------------------------------------------------------ 3. Fiscal year, month by month
-- Accumulated target, accumulated implemented saving, and a forecast:
-- implemented + approved + under study, each open idea counted in its planned month.
-- An open idea already late cannot be delivered in the past, so it is counted
-- in the month after the reference date. Ideas planned after the fiscal year are left out.
DROP VIEW IF EXISTS vw_fy_cumulative;

CREATE VIEW vw_fy_cumulative AS
WITH months AS (
    SELECT DISTINCT c.month_start, c.month_label, c.fiscal_month_no
      FROM dim_calendar c, params p
     WHERE c.date BETWEEN p.fy_start AND p.fy_end
),
target AS (
    SELECT month_start, SUM(target_k) AS target_k FROM fact_target GROUP BY month_start
),
implemented AS (
    SELECT saving_month AS month_start, SUM(annual_saving_k) AS implemented_k
      FROM fact_idea
     WHERE status = 'Implemented'
     GROUP BY saving_month
),
expected AS (
    SELECT
        CASE WHEN f.planned_date < p.as_of_date
             THEN STRFTIME('%Y-%m-01', DATE(p.as_of_date, '+1 month'))
             ELSE STRFTIME('%Y-%m-01', f.planned_date) END AS month_start,
        SUM(f.annual_saving_k) AS expected_k
      FROM fact_idea f, params p
     WHERE f.status IN ('Approved', 'Under study')
     GROUP BY 1
)
SELECT
    m.month_start,
    m.month_label,
    m.fiscal_month_no,
    ROUND(COALESCE(t.target_k, 0), 1)                                         AS target_k,
    ROUND(SUM(COALESCE(t.target_k, 0)) OVER w, 1)                             AS target_cum_k,
    ROUND(COALESCE(i.implemented_k, 0), 1)                                    AS implemented_k,
    ROUND(SUM(COALESCE(i.implemented_k, 0)) OVER w, 1)                        AS implemented_cum_k,
    ROUND(SUM(COALESCE(i.implemented_k, 0) + COALESCE(e.expected_k, 0)) OVER w, 1) AS forecast_cum_k
FROM months m
LEFT JOIN target t      ON t.month_start = m.month_start
LEFT JOIN implemented i ON i.month_start = m.month_start
LEFT JOIN expected e    ON e.month_start = m.month_start
WINDOW w AS (ORDER BY m.month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);


-- ------------------------------------------------------------------ 4. Buyers and suppliers
-- Who is delivering, and who has a lot open or late.
DROP VIEW IF EXISTS vw_buyer_ranking;

CREATE VIEW vw_buyer_ranking AS
SELECT
    buyer,
    COUNT(*)                                                               AS ideas,
    SUM(status = 'Implemented')                                            AS implemented_ideas,
    SUM(is_delayed)                                                        AS delayed_ideas,
    ROUND(SUM(CASE WHEN status = 'Implemented' THEN annual_saving_k ELSE 0 END), 1) AS implemented_k,
    ROUND(SUM(CASE WHEN is_open = 1 THEN annual_saving_k ELSE 0 END), 1)            AS open_k,
    RANK() OVER (ORDER BY SUM(CASE WHEN status = 'Implemented' THEN annual_saving_k ELSE 0 END) DESC) AS rank_implemented
FROM fact_idea
GROUP BY buyer;


DROP VIEW IF EXISTS vw_supplier_ranking;

CREATE VIEW vw_supplier_ranking AS
SELECT
    d.supplier_code,
    d.supplier,
    d.commodity_group,
    COUNT(*)                                                               AS ideas,
    SUM(f.status = 'Implemented')                                          AS implemented_ideas,
    SUM(f.is_delayed)                                                      AS delayed_ideas,
    ROUND(SUM(CASE WHEN f.status = 'Implemented' THEN f.annual_saving_k ELSE 0 END), 1) AS implemented_k,
    ROUND(SUM(CASE WHEN f.is_open = 1 THEN f.annual_saving_k ELSE 0 END), 1)            AS open_k,
    RANK() OVER (ORDER BY SUM(CASE WHEN f.status = 'Implemented' THEN f.annual_saving_k ELSE 0 END) DESC) AS rank_implemented
FROM fact_idea f
JOIN dim_supplier d ON d.supplier_code = f.supplier_code
GROUP BY d.supplier_code, d.supplier, d.commodity_group;


-- ------------------------------------------------------------------ 5. Data quality by supplier file
-- Which supplier files needed the most fixing. Not in the original report:
-- it turns the cleaning work into something the buyers can act on.
DROP VIEW IF EXISTS vw_dq_by_file;

CREATE VIEW vw_dq_by_file AS
WITH rows_in_file AS (
    SELECT source_file, COUNT(*) AS rows_loaded
      FROM stg_supplier_ideas
     GROUP BY source_file
)
SELECT
    q.source_file,
    'S' || SUBSTR(q.source_file, INSTR(q.source_file, 'Supplier ') + 9, 3) AS supplier_code,
    COALESCE(r.rows_loaded, 0)                         AS rows_loaded,
    COUNT(*)                                           AS issues,
    SUM(q.category = 'Duplicate')                      AS duplicates,
    SUM(q.category = 'Missing ID')                     AS missing_ids,
    SUM(q.category IN ('Number format', 'Date format')) AS format_issues,
    SUM(q.category IN ('Status', 'Buyer / vehicle', 'Supplier name')) AS naming_issues,
    SUM(q.category = 'Saving overwritten')             AS overwritten_formulas,
    SUM(q.category = 'Unreadable value')               AS unreadable_values,
    ROUND(1.0 * COUNT(*) / NULLIF(r.rows_loaded, 0), 2) AS issues_per_row
FROM dq_issues q
LEFT JOIN rows_in_file r ON r.source_file = q.source_file
GROUP BY q.source_file;
