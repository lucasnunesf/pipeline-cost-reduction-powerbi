-- Five views, one per dashboard page. Each one becomes a CSV for Power BI.
-- Values in USD thousands. Fiscal year: April 2026 to March 2027.

-- 1. How many ideas and how much saving in each status.
DROP VIEW IF EXISTS v_status_summary;
CREATE VIEW v_status_summary AS
SELECT
    status,
    COUNT(*)                AS ideas,
    ROUND(SUM(saving_k), 1) AS saving_k
FROM ideas
GROUP BY status;


-- 2. By vehicle: what is real, what is only approved or under study,
--    and the gap still missing to reach the target.
DROP VIEW IF EXISTS v_by_vehicle;
CREATE VIEW v_by_vehicle AS
WITH saving AS (
    SELECT
        vehicle,
        SUM(CASE WHEN status = 'Implemented' THEN saving_k ELSE 0 END) AS implemented_k,
        SUM(CASE WHEN status = 'Approved'    THEN saving_k ELSE 0 END) AS approved_k,
        SUM(CASE WHEN status = 'Under study' THEN saving_k ELSE 0 END) AS under_study_k
    FROM ideas
    GROUP BY vehicle
),
target AS (
    SELECT vehicle, SUM(target_k) AS target_k
    FROM targets
    GROUP BY vehicle
)
SELECT
    s.vehicle,
    ROUND(s.implemented_k, 1) AS implemented_k,
    ROUND(s.approved_k, 1)    AS approved_k,
    ROUND(s.under_study_k, 1) AS under_study_k,
    ROUND(t.target_k, 1)      AS target_k,
    ROUND(MAX(t.target_k - s.implemented_k - s.approved_k - s.under_study_k, 0), 1) AS gap_k
FROM saving s
JOIN target t ON t.vehicle = s.vehicle;


-- 3. Fiscal year month by month: saving implemented and target,
--    each one added up from April (running total).
DROP VIEW IF EXISTS v_fiscal_year;
CREATE VIEW v_fiscal_year AS
WITH monthly_target AS (
    SELECT month, SUM(target_k) AS target_k
    FROM targets
    GROUP BY month
),
monthly_saving AS (
    SELECT substr(planned_date, 1, 7) AS month, SUM(saving_k) AS implemented_k
    FROM ideas
    WHERE status = 'Implemented'
    GROUP BY month
)
SELECT
    t.month,
    ROUND(COALESCE(s.implemented_k, 0), 1) AS implemented_k,
    ROUND(SUM(COALESCE(s.implemented_k, 0)) OVER (ORDER BY t.month), 1) AS implemented_cumulative_k,
    ROUND(SUM(t.target_k) OVER (ORDER BY t.month), 1)                   AS target_cumulative_k
FROM monthly_target t
LEFT JOIN monthly_saving s ON s.month = t.month;


-- 4. Saving implemented by buyer.
DROP VIEW IF EXISTS v_by_buyer;
CREATE VIEW v_by_buyer AS
SELECT buyer, COUNT(*) AS ideas, ROUND(SUM(saving_k), 1) AS implemented_k
FROM ideas
WHERE status = 'Implemented'
GROUP BY buyer;


-- 5. Saving implemented by supplier.
DROP VIEW IF EXISTS v_by_supplier;
CREATE VIEW v_by_supplier AS
SELECT supplier, COUNT(*) AS ideas, ROUND(SUM(saving_k), 1) AS implemented_k
FROM ideas
WHERE status = 'Implemented'
GROUP BY supplier;
