"""
Join the 150 supplier files into one clean table, load it into SQL and
export the views for Power BI.

Steps:
  1. Read every Excel file in data/supplier_files with pandas.
  2. Clean what people typed by hand:
     - names and status in different ways  -> one spelling
     - numbers typed as text ("12,50")      -> numbers
     - dates typed as text ("05/09/2026")   -> dates
     - blank rows                           -> removed
     - the same idea in two files           -> kept once
  3. Load the ideas and the targets into a SQLite database (cost_reduction.db).
  4. Create the views (sql/views.sql).
  5. Save each view as a CSV in output/ for Power BI.

Run:  python scripts/consolidate.py
"""

import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DATA, SQL, OUTPUT = ROOT / "data", ROOT / "sql", ROOT / "output"
DB = ROOT / "cost_reduction.db"

# 1. Read all supplier files
files = sorted((DATA / "supplier_files").glob("*.xlsx"))
ideas = pd.concat([pd.read_excel(f, dtype=str).assign(source_file=f.name) for f in files])
rows_read = len(ideas)

# 2. Clean
ideas = ideas.dropna(subset=["Idea ID"])                                   # blank rows
for col in ["Supplier", "Buyer", "Status"]:
    ideas[col] = ideas[col].str.strip().str.capitalize()                   # " SUPPLIER 001 " -> "Supplier 001"
ideas["Saving (USD k)"] = pd.to_numeric(ideas["Saving (USD k)"].str.replace(",", "."))
ideas["Planned date"] = ideas["Planned date"].apply(lambda d: pd.to_datetime(d, dayfirst="/" in d))  # "/" = typed as day/month/year
ideas = ideas.drop_duplicates(subset="Idea ID", keep="first")              # copied ideas

ideas = ideas.rename(columns={
    "Idea ID": "idea_id", "Supplier": "supplier", "Buyer": "buyer", "Vehicle": "vehicle",
    "Idea": "idea", "Status": "status", "Saving (USD k)": "saving_k", "Planned date": "planned_date",
})
ideas["planned_date"] = ideas["planned_date"].dt.strftime("%Y-%m-%d")

targets = pd.read_excel(DATA / "targets.xlsx").rename(
    columns={"Vehicle": "vehicle", "Month": "month", "Target (USD k)": "target_k"})

# 3 and 4. Load SQL and create the views
with sqlite3.connect(DB) as con:
    ideas.to_sql("ideas", con, if_exists="replace", index=False)
    targets.to_sql("targets", con, if_exists="replace", index=False)
    con.executescript((SQL / "views.sql").read_text())

    # 5. Export for Power BI
    OUTPUT.mkdir(exist_ok=True)
    for view in ["v_status_summary", "v_by_vehicle", "v_fiscal_year", "v_by_buyer", "v_by_supplier"]:
        df = pd.read_sql(f"SELECT * FROM {view}", con)
        df.to_csv(OUTPUT / f"{view.removeprefix('v_')}.csv", index=False)
        print(f"{view}: {len(df)} rows")

print(f"{len(files)} files, {rows_read} rows read, {len(ideas)} ideas after cleaning")
