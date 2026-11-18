"""
Create the fake input files.

At work, every supplier sent its cost reduction ideas in its own Excel file,
all from the same template. This script builds files that look like that:

  data/supplier_files/Supplier 001.xlsx ... Supplier 150.xlsx   one per supplier
  data/targets.xlsx                                              monthly target per vehicle

Like the real files, they were filled by hand, so some cells have mistakes:
numbers typed as text, dates as text, names and status written in different
ways, blank rows and the same idea copied into two files.

All names are invented. Files were collected on 31 Dec 2026, so ideas
planned after that date are not implemented yet. The random seed is fixed, so the files are the same
every time. Values are in USD thousands.

Run:  python scripts/generate_data.py
"""

import random
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

random.seed(42)
DATA = Path(__file__).resolve().parent.parent / "data"
FILES = DATA / "supplier_files"
FILES.mkdir(parents=True, exist_ok=True)

VEHICLES = ["Vehicle 1", "Vehicle 2", "Vehicle 3", "Vehicle 4", "Vehicle 5"]
BUYERS = [f"Buyer {i}" for i in range(1, 9)]
STATUSES = ["Proposed", "Under study", "Approved", "Implemented", "Cancelled"]
STATUS_WEIGHTS = [15, 20, 25, 35, 5]
IDEAS = ["Change packaging", "Reduce wall thickness", "Localize production",
         "Combine parts", "Change material", "Optimize transport route",
         "Standardize fasteners", "Reduce scrap"]
FY_START = date(2026, 4, 1)          # fiscal year: April 2026 to March 2027
AS_OF = date(2026, 12, 31)           # the day the files were collected


def messy(value, kind):
    """Sometimes write a value the way a person would type it by hand."""
    if random.random() > 0.2:
        return value
    if kind == "text":
        return random.choice([value.upper(), value.lower(), f" {value} "])
    if kind == "number":
        return f"{value:.2f}".replace(".", ",")          # "12,50" as text
    if kind == "date":
        return value.strftime("%d/%m/%Y")                # date typed as text
    return value


copied = []
idea_no = 0
for s in range(1, 151):
    supplier = f"Supplier {s:03d}"
    buyer = random.choice(BUYERS)
    rows = []
    for _ in range(random.randint(3, 9)):
        idea_no += 1
        planned = FY_START + timedelta(days=random.randint(0, 364))
        status = random.choices(STATUSES, STATUS_WEIGHTS)[0]
        if status == "Implemented" and planned > AS_OF:
            status = random.choice(["Approved", "Under study"])   # not implemented yet
        row = {
            "Idea ID": f"CR-{idea_no:04d}",
            "Supplier": messy(supplier, "text"),
            "Buyer": messy(buyer, "text"),
            "Vehicle": random.choice(VEHICLES),
            "Idea": f"{random.choice(IDEAS)} of part {random.randint(100, 999)}",
            "Status": messy(status, "text"),
            "Saving (USD k)": messy(round(random.uniform(2, 60), 2), "number"),
            "Planned date": messy(planned, "date"),
        }
        rows.append(row)
        if random.random() < 0.03:
            copied.append(row)                         # this idea will be copied into another file
    if random.random() < 0.3:
        rows.insert(random.randint(0, len(rows)), {})  # a blank row in the middle
    if copied and random.random() < 0.15:
        rows.append(copied.pop())                      # an idea copied from another supplier's file
    pd.DataFrame(rows).to_excel(FILES / f"{supplier}.xlsx", index=False)

# Monthly target per vehicle, set by finance for the fiscal year
targets = []
for v in VEHICLES:
    yearly = random.randint(4000, 5500)
    for m in range(12):
        month = (pd.Timestamp(FY_START) + pd.DateOffset(months=m)).strftime("%Y-%m")
        targets.append({"Vehicle": v, "Month": month, "Target (USD k)": round(yearly / 12, 2)})
pd.DataFrame(targets).to_excel(DATA / "targets.xlsx", index=False)

print(f"150 supplier files and the target file written to {DATA}")
