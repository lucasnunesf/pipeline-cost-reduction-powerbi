-- 01_mappings.sql
-- Lookup tables used by the cleaning step.
-- Adding a new spelling is one INSERT here, not a change in the cleaning logic.

DROP TABLE IF EXISTS map_status;

CREATE TABLE map_status (
    raw_status  TEXT PRIMARY KEY,   -- lower case, no spaces around
    status      TEXT NOT NULL
);

INSERT INTO map_status (raw_status, status) VALUES
    ('proposed',                    'Proposed'),
    ('proposta',                    'Proposed'),
    ('new',                         'Proposed'),
    ('under study',                 'Under study'),
    ('in study',                    'Under study'),
    ('em estudo',                   'Under study'),
    ('approved',                    'Approved'),
    ('aprovado',                    'Approved'),
    ('approved - waiting supplier', 'Approved'),
    ('implemented',                 'Implemented'),
    ('implementado',                'Implemented'),
    ('done',                        'Implemented'),
    ('cancelled',                   'Cancelled'),
    ('canceled',                    'Cancelled'),
    ('cancelado',                   'Cancelled'),
    ('dropped',                     'Cancelled');


DROP TABLE IF EXISTS dim_status;

CREATE TABLE dim_status (
    status      TEXT PRIMARY KEY,
    step_order  INTEGER NOT NULL,   -- order of the steps in the funnel
    is_open     INTEGER NOT NULL    -- 1 = still expected to deliver saving
);

INSERT INTO dim_status (status, step_order, is_open) VALUES
    ('Proposed',    1, 1),
    ('Under study', 2, 1),
    ('Approved',    3, 1),
    ('Implemented', 4, 0),
    ('Cancelled',   5, 0),
    ('Unknown',     9, 1);
