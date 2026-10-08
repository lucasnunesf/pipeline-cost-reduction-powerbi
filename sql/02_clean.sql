-- 02_clean.sql
-- Turns the staging tables (text, as typed) into clean, typed tables.
--
--   work_ideas_parsed   every staging row, with each value converted
--   work_ideas_keyed    + the idea key and the duplicate ranking
--   clean_idea_area     one row per idea and area involved
--   clean_ideas         one row per idea, no duplicates
--   clean_targets       one row per vehicle and month
--   dq_issues           every problem found, and what was done about it
--
-- Nothing is deleted from staging: any clean value can be compared with
-- what was typed, using source_file and source_row.


-- ------------------------------------------------------------------ 1. parse
DROP TABLE IF EXISTS work_ideas_parsed;

CREATE TABLE work_ideas_parsed AS
WITH stripped AS (
    SELECT
        s.*,
        -- numbers: remove currency signs, units and spaces
        REPLACE(REPLACE(REPLACE(TRIM(s.current_cost), '$', ''), 'USD', ''), ' ', '') AS cur_s,
        REPLACE(REPLACE(REPLACE(TRIM(s.new_cost),     '$', ''), 'USD', ''), ' ', '') AS new_s,
        REPLACE(REPLACE(LOWER(TRIM(s.annual_volume)), 'pcs', ''), ' ', '')         AS vol_s,
        -- dates: "30.07.26" and "30/07/26" are the same format
        REPLACE(TRIM(s.submission_date), '.', '/') AS sub_s,
        REPLACE(TRIM(s.planned_date),    '.', '/') AS pla_s,
        REPLACE(TRIM(s.actual_date),     '.', '/') AS act_s,
        REPLACE(TRIM(s.last_update_raw), '.', '/') AS upd_s
    FROM stg_supplier_ideas s
),
normalized AS (
    SELECT
        st.*,
        -- money: when both separators appear, the last one is the decimal
        --   "1.250,00" -> "1250.00"   "1,250.00" -> "1250.00"   "12,40" -> "12.40"
        CASE
            WHEN INSTR(cur_s, ',') > 0 AND INSTR(cur_s, '.') > 0 THEN
                CASE WHEN INSTR(cur_s, ',') > INSTR(cur_s, '.')
                     THEN REPLACE(REPLACE(cur_s, '.', ''), ',', '.')
                     ELSE REPLACE(cur_s, ',', '') END
            WHEN INSTR(cur_s, ',') > 0 THEN REPLACE(cur_s, ',', '.')
            ELSE cur_s
        END AS cur_n,
        CASE
            WHEN INSTR(new_s, ',') > 0 AND INSTR(new_s, '.') > 0 THEN
                CASE WHEN INSTR(new_s, ',') > INSTR(new_s, '.')
                     THEN REPLACE(REPLACE(new_s, '.', ''), ',', '.')
                     ELSE REPLACE(new_s, ',', '') END
            WHEN INSTR(new_s, ',') > 0 THEN REPLACE(new_s, ',', '.')
            ELSE new_s
        END AS new_n,
        -- volume is a whole number: every separator is a thousands separator
        REPLACE(REPLACE(
            CASE WHEN vol_s GLOB '*.0' THEN SUBSTR(vol_s, 1, LENGTH(vol_s) - 2) ELSE vol_s END,
        '.', ''), ',', '') AS vol_n,
        -- dates: ISO stays; everything else is read day first
        CASE
            WHEN sub_s GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN sub_s
            WHEN sub_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'
                THEN SUBSTR(sub_s, 7, 4) || '-' || SUBSTR(sub_s, 4, 2) || '-' || SUBSTR(sub_s, 1, 2)
            WHEN sub_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9]'
                THEN '20' || SUBSTR(sub_s, 7, 2) || '-' || SUBSTR(sub_s, 4, 2) || '-' || SUBSTR(sub_s, 1, 2)
        END AS sub_d,
        CASE
            WHEN pla_s GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN pla_s
            WHEN pla_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'
                THEN SUBSTR(pla_s, 7, 4) || '-' || SUBSTR(pla_s, 4, 2) || '-' || SUBSTR(pla_s, 1, 2)
            WHEN pla_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9]'
                THEN '20' || SUBSTR(pla_s, 7, 2) || '-' || SUBSTR(pla_s, 4, 2) || '-' || SUBSTR(pla_s, 1, 2)
        END AS pla_d,
        CASE
            WHEN act_s GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN act_s
            WHEN act_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'
                THEN SUBSTR(act_s, 7, 4) || '-' || SUBSTR(act_s, 4, 2) || '-' || SUBSTR(act_s, 1, 2)
            WHEN act_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9]'
                THEN '20' || SUBSTR(act_s, 7, 2) || '-' || SUBSTR(act_s, 4, 2) || '-' || SUBSTR(act_s, 1, 2)
        END AS act_d,
        CASE
            WHEN upd_s GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN upd_s
            WHEN upd_s GLOB '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'
                THEN SUBSTR(upd_s, 7, 4) || '-' || SUBSTR(upd_s, 4, 2) || '-' || SUBSTR(upd_s, 1, 2)
        END AS upd_d
    FROM stripped st
)
SELECT
    n.source_file,
    n.source_row,
    TRIM(n.supplier_code)                       AS file_supplier_code,
    TRIM(n.supplier_raw)                        AS supplier_raw,
    TRIM(n.commodity_group)                     AS commodity_group,
    DATE(n.upd_d)                               AS last_update,
    NULLIF(TRIM(n.idea_id), '')                 AS idea_id_raw,
    TRIM(n.proposal_name)                       AS proposal_name,
    TRIM(n.description)                         AS description,
    TRIM(n.responsible)                         AS responsible,
    -- buyer and vehicle: keep the number, rebuild the name ("B2" -> "Buyer 2")
    CASE WHEN SUBSTR(TRIM(n.buyer), -1) GLOB '[0-9]'
         THEN 'Buyer ' || SUBSTR(TRIM(n.buyer), -1) END        AS buyer,
    CASE WHEN SUBSTR(TRIM(n.vehicle), -1) GLOB '[0-9]'
         THEN 'Vehicle ' || SUBSTR(TRIM(n.vehicle), -1) END    AS vehicle,
    -- areas: one separator for all
    REPLACE(REPLACE(TRIM(n.areas), '/', ';'), ',', ';')         AS areas_norm,
    TRIM(n.part_number)                         AS part_number,
    -- a value that still has letters after cleaning is unreadable: NULL
    CASE WHEN n.cur_n = '' OR n.cur_n GLOB '*[^0-9.]*' THEN NULL
         ELSE CAST(n.cur_n AS REAL) END         AS current_cost,
    CASE WHEN n.new_n = '' OR n.new_n GLOB '*[^0-9.]*' THEN NULL
         ELSE CAST(n.new_n AS REAL) END         AS new_cost,
    CASE WHEN n.vol_n = '' OR n.vol_n GLOB '*[^0-9]*' THEN NULL
         ELSE CAST(n.vol_n AS INTEGER) END      AS annual_volume,
    COALESCE(m.status, 'Unknown')               AS status,
    DATE(n.sub_d)                               AS submission_date,
    DATE(n.pla_d)                               AS planned_date,
    DATE(n.act_d)                               AS actual_date,
    TRIM(n.comments)                            AS comments,
    -- raw values, kept to report what was fixed
    n.buyer           AS buyer_raw,
    n.vehicle         AS vehicle_raw,
    n.status          AS status_raw,
    n.current_cost    AS current_cost_raw,
    n.new_cost        AS new_cost_raw,
    n.annual_volume   AS annual_volume_raw,
    n.submission_date AS submission_date_raw,
    n.planned_date    AS planned_date_raw,
    n.actual_date     AS actual_date_raw,
    n.annual_saving_in_file
FROM normalized n
LEFT JOIN map_status m
       ON m.raw_status = LOWER(TRIM(n.status));


-- ------------------------------------------------------------------ 2. keys and duplicates
DROP TABLE IF EXISTS work_ideas_keyed;

CREATE TABLE work_ideas_keyed AS
WITH keyed AS (
    SELECT
        p.*,
        -- an ID left blank is recovered from another copy of the same idea
        -- (same part number and proposal name); if there is none, a key is generated
        COALESCE(
            p.idea_id_raw,
            (SELECT c.idea_id_raw
               FROM work_ideas_parsed c
              WHERE c.idea_id_raw IS NOT NULL
                AND c.part_number = p.part_number
                AND c.proposal_name = p.proposal_name
              LIMIT 1),
            'NOID-' || p.file_supplier_code || '-' || p.source_row
        ) AS idea_id
    FROM work_ideas_parsed p
),
owned AS (
    SELECT
        k.*,
        -- the supplier that owns the idea is the code inside the ID: CR-S071-004 -> S071
        CASE WHEN k.idea_id LIKE 'CR-%-%'
             THEN SUBSTR(k.idea_id, 4, INSTR(SUBSTR(k.idea_id, 4), '-') - 1)
             ELSE k.file_supplier_code END AS owner_code
    FROM keyed k
)
SELECT
    o.*,
    -- keep one row per idea: first the owner's own file, then the most recent file
    ROW_NUMBER() OVER (
        PARTITION BY o.idea_id
        ORDER BY (o.file_supplier_code = o.owner_code) DESC,
                 o.last_update DESC,
                 o.source_file,
                 o.source_row
    ) AS copy_rank
FROM owned o;


-- ------------------------------------------------------------------ 3. areas (one row per idea and area)
DROP TABLE IF EXISTS clean_idea_area;

CREATE TABLE clean_idea_area (
    idea_id  TEXT NOT NULL,
    area     TEXT NOT NULL,
    PRIMARY KEY (idea_id, area)
);

INSERT INTO clean_idea_area (idea_id, area)
WITH RECURSIVE split(idea_id, part, rest) AS (
    SELECT idea_id, '', areas_norm || ';'
      FROM work_ideas_keyed
     WHERE copy_rank = 1 AND areas_norm IS NOT NULL
    UNION ALL
    SELECT idea_id,
           TRIM(SUBSTR(rest, 1, INSTR(rest, ';') - 1)),
           SUBSTR(rest, INSTR(rest, ';') + 1)
      FROM split
     WHERE rest <> ''
)
SELECT DISTINCT
       idea_id,
       UPPER(SUBSTR(part, 1, 1)) || LOWER(SUBSTR(part, 2))   -- "engineering" -> "Engineering"
  FROM split
 WHERE part <> '';


-- ------------------------------------------------------------------ 4. clean ideas
DROP TABLE IF EXISTS clean_ideas;

CREATE TABLE clean_ideas (
    idea_id            TEXT PRIMARY KEY,
    supplier_code      TEXT NOT NULL,
    supplier           TEXT NOT NULL,
    commodity_group    TEXT,
    proposal_name      TEXT,
    description        TEXT,
    responsible        TEXT,
    buyer              TEXT,
    areas              TEXT,
    vehicle            TEXT,
    part_number        TEXT,
    current_cost       REAL,      -- USD per unit
    new_cost           REAL,      -- USD per unit
    reduction_per_unit REAL,      -- USD per unit
    reduction_pct      REAL,      -- 0.05 = 5%
    annual_volume      INTEGER,
    annual_saving_k    REAL,      -- USD thousands, recalculated here
    status             TEXT NOT NULL,
    submission_date    TEXT,      -- ISO date
    planned_date       TEXT,
    actual_date        TEXT,
    comments           TEXT,
    source_file        TEXT NOT NULL,
    source_row         INTEGER NOT NULL
);

INSERT INTO clean_ideas
SELECT
    k.idea_id,
    k.owner_code,
    'Supplier ' || SUBSTR(k.owner_code, 2),
    k.commodity_group,
    k.proposal_name,
    k.description,
    k.responsible,
    k.buyer,
    (SELECT GROUP_CONCAT(area, '; ')
       FROM (SELECT area FROM clean_idea_area a WHERE a.idea_id = k.idea_id ORDER BY area)),
    k.vehicle,
    k.part_number,
    k.current_cost,
    k.new_cost,
    ROUND(k.current_cost - k.new_cost, 4),
    ROUND((k.current_cost - k.new_cost) / NULLIF(k.current_cost, 0), 4),
    k.annual_volume,
    ROUND((k.current_cost - k.new_cost) * k.annual_volume / 1000.0, 3),
    k.status,
    k.submission_date,
    k.planned_date,
    k.actual_date,
    k.comments,
    k.source_file,
    k.source_row
FROM work_ideas_keyed k
WHERE k.copy_rank = 1;


-- ------------------------------------------------------------------ 5. targets
DROP TABLE IF EXISTS clean_targets;

CREATE TABLE clean_targets (
    vehicle      TEXT NOT NULL,
    month_start  TEXT NOT NULL,   -- first day of the month, ISO
    target_k     REAL NOT NULL,   -- USD thousands
    PRIMARY KEY (vehicle, month_start)
);

INSERT INTO clean_targets (vehicle, month_start, target_k)
SELECT
    'Vehicle ' || SUBSTR(TRIM(vehicle_raw), -1),
    -- "Apr-26" -> "2026-04-01"
    '20' || SUBSTR(TRIM(month_raw), 5, 2) || '-' ||
    PRINTF('%02d', (INSTR('JanFebMarAprMayJunJulAugSepOctNovDec', SUBSTR(TRIM(month_raw), 1, 3)) + 2) / 3)
    || '-01',
    CAST(target_raw AS REAL)
FROM stg_targets
WHERE TRIM(month_raw) <> 'Total';     -- totals are recalculated, never loaded


-- ------------------------------------------------------------------ 6. data quality report
DROP TABLE IF EXISTS dq_issues;

CREATE TABLE dq_issues (
    source_file  TEXT NOT NULL,
    source_row   INTEGER,          -- NULL for file-level issues
    idea_id      TEXT,
    category     TEXT NOT NULL,
    detail       TEXT,
    action       TEXT NOT NULL
);

INSERT INTO dq_issues
-- file level
SELECT source_file, NULL, NULL, 'Empty file', 'Template sent with no ideas', 'Nothing loaded'
  FROM stg_load_log
 WHERE rows_loaded = 0 AND source_file LIKE 'Group%'

UNION ALL
SELECT DISTINCT source_file, NULL, NULL, 'Supplier name',
       'Written as "' || supplier_raw || '"', 'Name taken from the supplier code'
  FROM work_ideas_parsed
 WHERE supplier_raw <> 'Supplier ' || SUBSTR(file_supplier_code, 2)

-- duplicates
UNION ALL
SELECT source_file, source_row, idea_id, 'Duplicate',
       CASE WHEN file_supplier_code <> owner_code
            THEN 'Idea of ' || owner_code || ' copied into this file'
            ELSE 'Same idea twice in the file' END,
       'Removed'
  FROM work_ideas_keyed
 WHERE copy_rank > 1

-- the rest only for the rows that were kept
UNION ALL
SELECT source_file, source_row, idea_id, 'Missing ID', NULL,
       CASE WHEN idea_id LIKE 'NOID-%' THEN 'Kept with a generated key'
            ELSE 'Recovered from another copy of the idea' END
  FROM work_ideas_keyed
 WHERE idea_id_raw IS NULL AND copy_rank = 1

UNION ALL
SELECT source_file, source_row, idea_id, 'Status',
       'Written as "' || COALESCE(status_raw, '') || '"',
       CASE WHEN status = 'Unknown' THEN 'Kept as Unknown' ELSE 'Mapped to ' || status END
  FROM work_ideas_keyed
 WHERE copy_rank = 1 AND (status_raw IS NULL OR status_raw <> status)

UNION ALL
SELECT source_file, source_row, idea_id, 'Buyer / vehicle',
       'Written as "' || buyer_raw || '"', 'Mapped to ' || COALESCE(buyer, 'nothing')
  FROM work_ideas_keyed
 WHERE copy_rank = 1 AND buyer_raw IS NOT buyer

UNION ALL
SELECT source_file, source_row, idea_id, 'Buyer / vehicle',
       'Written as "' || vehicle_raw || '"', 'Mapped to ' || COALESCE(vehicle, 'nothing')
  FROM work_ideas_keyed
 WHERE copy_rank = 1 AND vehicle_raw IS NOT vehicle

UNION ALL
SELECT source_file, source_row, idea_id, 'Number format',
       'Typed as "' || current_cost_raw || '" / "' || new_cost_raw || '" / "' || annual_volume_raw || '"',
       'Converted'
  FROM work_ideas_keyed
 WHERE copy_rank = 1
   AND (current_cost_raw GLOB '*[^0-9.]*' OR new_cost_raw GLOB '*[^0-9.]*'
        OR annual_volume_raw GLOB '*[^0-9]*')

UNION ALL
SELECT source_file, source_row, idea_id, 'Date format', 'Date typed as text', 'Converted, day first'
  FROM work_ideas_keyed
 WHERE copy_rank = 1
   AND (   (submission_date_raw IS NOT NULL AND submission_date_raw NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')
        OR (planned_date_raw    IS NOT NULL AND planned_date_raw    NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')
        OR (actual_date_raw     IS NOT NULL AND actual_date_raw     NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'))

UNION ALL
SELECT source_file, source_row, idea_id, 'Saving overwritten',
       'Typed ' || annual_saving_in_file || ' over the formula', 'Recalculated from cost and volume'
  FROM work_ideas_keyed
 WHERE copy_rank = 1 AND annual_saving_in_file NOT LIKE '=%'

UNION ALL
SELECT source_file, source_row, idea_id, 'Unreadable value',
       'A cost, volume or date could not be read', 'Left empty'
  FROM work_ideas_keyed
 WHERE copy_rank = 1
   AND (   (current_cost IS NULL AND current_cost_raw IS NOT NULL)
        OR (new_cost IS NULL AND new_cost_raw IS NOT NULL)
        OR (annual_volume IS NULL AND annual_volume_raw IS NOT NULL)
        OR (submission_date IS NULL AND submission_date_raw IS NOT NULL)
        OR (planned_date IS NULL AND planned_date_raw IS NOT NULL)
        OR (actual_date IS NULL AND actual_date_raw IS NOT NULL));
