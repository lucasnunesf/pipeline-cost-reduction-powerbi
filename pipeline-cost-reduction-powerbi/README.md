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
    │  load              read every file as it is, keep the file name on each row
    ▼
staging tables
    │
    │  clean             standardize names, dates, numbers and status,
    │                    remove duplicates, recalculate savings
    ▼
clean tables
    │
    │  model (SQL)       fact table of ideas + dimensions (supplier, buyer,
    │                    vehicle, fiscal calendar April–March) + targets
    ▼
reporting views      business rules: delayed ideas, real vs. paper saving,
    │                    accumulated saving vs. target
    ▼
Power BI
```

## Design choices

- **Delayed is a rule, not a status.** An idea is delayed when its planned date has passed and it is not implemented. Nobody has to remember to update it.
- **Calculated columns from the source are not trusted.** Suppliers can type over the formulas, so savings are recalculated from cost and volume.
- **Every row keeps its source file.** Any number in the dashboard can be traced back to the workbook it came from.

## How to run

```bash
pip install -r requirements.txt
python src/generate_raw.py
```

## Layout

```
templates/supplier_template.xlsx   the template every supplier fills in
src/generate_raw.py                creates the synthetic source files
data/                              generated files (not versioned)
```

## Status

- [x] Problem and supplier template defined
- [x] Synthetic source files with realistic defects
- [ ] Load all files into staging
- [ ] Cleaning and standardization
- [ ] Data model and reporting views in SQL
- [ ] Power BI dashboard and screenshots
- [ ] Insights written up
