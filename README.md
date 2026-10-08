# Cost Reduction Pipeline

A Python and SQL pipeline that consolidates cost reduction ideas from 150 supplier Excel files into one clean model, so the programme can be followed in a single Power BI dashboard.

> **About this project:** this is a case study based on a problem I found while working in procurement at a car manufacturer: tracking cost reduction ideas spread across 100+ supplier Excel files. The solution here is my own design of how it could be done with a proper data pipeline. It is not the system used at the company, and all data is synthetic.

🚧 **Work in progress.** See [Status](#status) for what is done and what is next.

## The problem

Every supplier sends their cost reduction ideas in an Excel file. All files use the same template, but there are more than 100 of them, and they are updated during the whole year.

To know how the programme is going, someone has to open the files one by one and add everything by hand. It takes days, and it has to be done every month.

Questions the team cannot answer fast:

- How many ideas do we have, and where are they stuck?
- How much saving is already real, and how much is only on paper?
- Are we going to reach the target this fiscal year?
- Which vehicles, buyers and suppliers are delivering?

## The data

Two sources, both synthetic:

| Source | Owned by | What it holds |
|---|---|---|
| 150 supplier workbooks, in 4 commodity groups | Suppliers | cost reduction ideas, one row per idea |
| `targets.xlsx` | Finance | savings target per vehicle and fiscal month |

Each supplier workbook is a copy of [`templates/supplier_template.xlsx`](templates/supplier_template.xlsx). The generated files carry the defects found in real hand-filled spreadsheets:

- supplier, buyer and vehicle names written in different ways
- dates and numbers typed as text, in Brazilian and US formats
- status written differently by each person ("Approved", "aprovado", "APPROVED ")
- blank rows, the same idea pasted twice, and ideas copied into another supplier's file
- calculated columns overwritten by hand

## How it works

```
150 supplier files + targets.xlsx
    │
    │  generate_raw.py   create the synthetic files with realistic defects
    ▼
data/raw/
    │
    │  load_raw.py       read every file as it is, keep the file and row on each record
    ▼
staging tables (SQLite)
    │
    │  02_clean.sql      standardize names, dates, numbers and status,
    │                    remove duplicates, recalculate savings,
    │                    log every problem in dq_issues
    ▼
clean tables (+ check_truth.py: compare with the original clean data)
    │
    │  03_model.sql      star model: fact_idea + fact_target, dimensions for
    │                    supplier, buyer, vehicle, status and a fiscal calendar
    ▼
04_views.sql         business rules, one view per report page
    │
    ▼
Power BI
```

## Design choices

- **Staging keeps the data exactly as typed.** Every value lands as text, with the file and row it came from. Fixing happens in a separate step, so it is always possible to compare the original with the cleaned value.
- **Delayed is a rule, not a status.** An idea is delayed when its planned date has passed and it is not implemented. Nobody has to remember to update it.
- **Calculated columns from the source are not trusted.** Suppliers can type over the formulas, so savings are recalculated from cost and volume.
- **Implemented saving counts in the month of implementation.** The full annual saving of an idea goes to the month it went into production, the same way the programme is reported.
- **One reference date for the whole model.** "Delayed" and "open" are calculated against the date the files were collected (`params` table), not today's date, so the numbers do not change by themselves.
- **Every row keeps its source file.** Any number in the dashboard can be traced back to the workbook it came from.

## Cleaning results

All the cleaning is done in SQL ([`sql/02_clean.sql`](sql/02_clean.sql)). Every problem found is written to a `dq_issues` table with the file, the row and what was done about it.

On the current synthetic data:

| What was found | Rows | What the pipeline did |
|---|---:|---|
| Costs or volumes typed as text ("12,40", "$50.58", "16000 pcs") | 568 | Converted |
| Dates typed as text, in mixed formats | 381 | Converted, read day first |
| Buyer or vehicle written in a non-standard way | 440 | Mapped to the standard name |
| Status written in a non-standard way (25 spellings for 5 statuses) | 262 | Mapped with the `map_status` table |
| Same idea twice, or copied into another supplier's file | 48 | Removed, keeping the owner's copy |
| Saving typed over the formula | 47 | Recalculated from cost and volume |
| Supplier name written differently in the file header | 18 | Name taken from the supplier code |
| Idea with no ID | 13 | 1 recovered from another copy, 12 kept with a generated key |
| Supplier sent the template with no ideas | 6 | Nothing loaded |

**How the cleaning is tested:** before adding the defects, `generate_raw.py` saves the clean version of every idea. `check_truth.py` compares the pipeline result with it, field by field. Current result: 912 of 912 ideas recovered, 0 field mismatches.

## Data model

```
dim_supplier ─┐                     ┌─ dim_calendar (fiscal year April–March)
dim_buyer ────┼──── fact_idea ──────┤
dim_status ───┘     (one row per    └─ dim_vehicle ──── fact_target
                     idea)                              (vehicle × month)
```

| View | Report page | Question it answers |
|---|---|---|
| `vw_overview` | Overview | How many ideas, where they are, how many are late |
| `vw_vehicle_status` | Status by vehicle | What is real, what is only on paper, and the gap to the target |
| `vw_fy_cumulative` | Fiscal year | Accumulated target vs. implemented saving vs. forecast |
| `vw_buyer_ranking`, `vw_supplier_ranking` | Buyers and suppliers | Who is delivering, who has a lot open or late |
| `vw_dq_by_file` | Data quality | Which supplier files needed the most fixing |

The forecast in `vw_fy_cumulative` adds every approved or under-study idea in its planned month. An idea that is already late cannot be delivered in the past, so it is counted in the month after the reference date.

## How to run

```bash
pip install -r requirements.txt
python src/run_pipeline.py --generate
```

`run_pipeline.py` runs every step in order and stops at the first one that fails. Without `--generate`, it reuses the source files already in `data/raw/`. Each step can also be run on its own:

```bash
python src/generate_raw.py   # create the synthetic source files
python src/load_raw.py       # land them in data/cost_reduction.db
python src/build_sql.py      # run the SQL files: cleaning, model and views
python src/check_truth.py    # test the cleaning against the original data
```

## Layout

```
templates/supplier_template.xlsx   the template every supplier fills in
src/generate_raw.py                creates the synthetic source files
src/load_raw.py                    loads every file into SQLite staging tables, as typed
src/build_sql.py                   runs the SQL files in order
src/check_truth.py                 tests the cleaning against the original clean data
src/run_pipeline.py                runs all the steps in order
sql/01_mappings.sql                lookup tables (status spellings, status order)
sql/02_clean.sql                   cleaning rules and data quality log
sql/03_model.sql                   star model: facts, dimensions, fiscal calendar
sql/04_views.sql                   business rules and reporting views
data/                              generated files (not versioned)
```

## Status

- [x] Problem and supplier template defined
- [x] Synthetic source files with realistic defects
- [x] Load all files into staging
- [x] Cleaning and standardization in SQL, tested against the original data
- [x] Data model and reporting views in SQL
- [ ] Power BI dashboard and screenshots
- [ ] Insights written up
