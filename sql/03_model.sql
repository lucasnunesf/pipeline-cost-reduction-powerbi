-- 03_model.sql
-- Star model read by Power BI.
--
--   params         reference date and fiscal year of the data
--   dim_calendar   one row per day, with fiscal year (April to March)
--   dim_supplier   dim_buyer   dim_vehicle   (dim_status is in 01_mappings.sql)
--   fact_idea      one row per idea, with the delay rule applied
--   fact_target    one row per vehicle and month


-- ------------------------------------------------------------------ parameters
DROP TABLE IF EXISTS params;

CREATE TABLE params (
    as_of_date      TEXT NOT NULL,   -- the day the supplier files were collected
    fy_start        TEXT NOT NULL,   -- first day of the fiscal year shown
    fy_end          TEXT NOT NULL
);

-- Changing the reference date is one line here: every rule below follows it.
INSERT INTO params VALUES ('2026-12-31', '2026-04-01', '2027-03-31');


-- ------------------------------------------------------------------ calendar
DROP TABLE IF EXISTS dim_calendar;

CREATE TABLE dim_calendar (
    date             TEXT PRIMARY KEY,
    month_start      TEXT NOT NULL,
    month_label      TEXT NOT NULL,   -- "Apr-26"
    calendar_year    INTEGER NOT NULL,
    calendar_month   INTEGER NOT NULL,
    fiscal_year      TEXT NOT NULL,   -- "FY2026" = April 2026 to March 2027
    fiscal_month_no  INTEGER NOT NULL,-- 1 = April ... 12 = March
    fiscal_quarter   TEXT NOT NULL    -- "Q1" = April to June
);

INSERT INTO dim_calendar
WITH RECURSIVE days(d) AS (
    SELECT '2026-01-01'
    UNION ALL
    SELECT DATE(d, '+1 day') FROM days WHERE d < '2027-12-31'
)
SELECT
    d,
    STRFTIME('%Y-%m-01', d),
    SUBSTR('JanFebMarAprMayJunJulAugSepOctNovDec', (CAST(STRFTIME('%m', d) AS INTEGER) - 1) * 3 + 1, 3)
        || '-' || SUBSTR(STRFTIME('%Y', d), 3, 2),
    CAST(STRFTIME('%Y', d) AS INTEGER),
    CAST(STRFTIME('%m', d) AS INTEGER),
    -- April or later belongs to the fiscal year that starts this calendar year
    'FY' || (CAST(STRFTIME('%Y', d) AS INTEGER) - (CAST(STRFTIME('%m', d) AS INTEGER) < 4)),
    (CAST(STRFTIME('%m', d) AS INTEGER) + 8) % 12 + 1,
    'Q' || (((CAST(STRFTIME('%m', d) AS INTEGER) + 8) % 12) / 3 + 1)
FROM days;


-- ------------------------------------------------------------------ dimensions
DROP TABLE IF EXISTS dim_supplier;

CREATE TABLE dim_supplier (
    supplier_code    TEXT PRIMARY KEY,
    supplier         TEXT NOT NULL,
    commodity_group  TEXT
);

INSERT INTO dim_supplier
SELECT supplier_code, MIN(supplier), MIN(commodity_group)
  FROM clean_ideas
 GROUP BY supplier_code;


DROP TABLE IF EXISTS dim_buyer;

CREATE TABLE dim_buyer (buyer TEXT PRIMARY KEY);

INSERT INTO dim_buyer
SELECT DISTINCT buyer FROM clean_ideas WHERE buyer IS NOT NULL;


DROP TABLE IF EXISTS dim_vehicle;

CREATE TABLE dim_vehicle (vehicle TEXT PRIMARY KEY);

INSERT INTO dim_vehicle
SELECT vehicle FROM clean_ideas WHERE vehicle IS NOT NULL
UNION
SELECT vehicle FROM clean_targets;


-- ------------------------------------------------------------------ facts
DROP TABLE IF EXISTS fact_idea;

CREATE TABLE fact_idea (
    idea_id             TEXT PRIMARY KEY,
    supplier_code       TEXT NOT NULL,
    buyer               TEXT,
    vehicle             TEXT,
    status              TEXT NOT NULL,
    proposal_name       TEXT,
    annual_saving_k     REAL,
    submission_date     TEXT,
    planned_date        TEXT,
    actual_date         TEXT,
    -- the saving counts in full in the month the idea was implemented
    saving_month        TEXT,
    is_open             INTEGER NOT NULL,  -- 1 = still expected to deliver
    is_delayed          INTEGER NOT NULL,  -- 1 = planned date passed, not implemented
    days_late           INTEGER,
    source_file         TEXT NOT NULL,
    source_row          INTEGER NOT NULL
);

INSERT INTO fact_idea
SELECT
    c.idea_id,
    c.supplier_code,
    c.buyer,
    c.vehicle,
    c.status,
    c.proposal_name,
    c.annual_saving_k,
    c.submission_date,
    c.planned_date,
    c.actual_date,
    CASE WHEN c.status = 'Implemented' THEN STRFTIME('%Y-%m-01', c.actual_date) END,
    s.is_open,
    -- DELAYED RULE: still open and the planned date is before the reference date.
    -- "Delayed" is never typed by anyone; it is always calculated here.
    CASE WHEN s.is_open = 1 AND c.planned_date < p.as_of_date THEN 1 ELSE 0 END,
    CASE WHEN s.is_open = 1 AND c.planned_date < p.as_of_date
         THEN CAST(JULIANDAY(p.as_of_date) - JULIANDAY(c.planned_date) AS INTEGER) END,
    c.source_file,
    c.source_row
FROM clean_ideas c
JOIN dim_status s ON s.status = c.status
CROSS JOIN params p;


DROP TABLE IF EXISTS fact_target;

CREATE TABLE fact_target (
    vehicle      TEXT NOT NULL,
    month_start  TEXT NOT NULL,
    target_k     REAL NOT NULL,
    PRIMARY KEY (vehicle, month_start)
);

INSERT INTO fact_target
SELECT vehicle, month_start, target_k FROM clean_targets;
