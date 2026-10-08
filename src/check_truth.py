"""
check_truth.py

Tests the cleaning step. generate_raw.py saved the clean version of every
idea in data/truth/ideas_truth.csv before adding the defects. This script
compares clean_ideas with that file, field by field.

If the cleaning rules are right, every field matches. Anything that does
not match is printed, so a broken rule shows up at once.

Run from the repository root:
    python src/check_truth.py
"""

import csv
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "data" / "cost_reduction.db"
TRUTH = ROOT / "data" / "truth" / "ideas_truth.csv"

# field in the truth file -> how to compare it with clean_ideas
FIELDS = {
    "supplier_code": str, "proposal_name": str, "responsible": str,
    "buyer": str, "areas": str, "vehicle": str, "part_number": str,
    "current_cost": float, "new_cost": float, "annual_volume": int,
    "status": str, "submission_date": str, "planned_date": str, "actual_date": str,
}


def same(kind, a, b):
    if a in ("", None) and b in ("", None):
        return True
    if a in ("", None) or b in ("", None):
        return False
    if kind is float:
        return abs(float(a) - float(b)) < 0.005
    return kind(a) == kind(b)


def main():
    with open(TRUTH, encoding="utf-8") as fh:
        truth = {r["idea_id"]: r for r in csv.DictReader(fh)}

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    clean = {r["idea_id"]: dict(r) for r in con.execute("SELECT * FROM clean_ideas")}
    con.close()

    generated = [k for k in clean if k.startswith("NOID-")]
    missing = [k for k in truth if k not in clean]
    extra = [k for k in clean if k not in truth and not k.startswith("NOID-")]

    mismatches = []
    for idea_id, t in truth.items():
        c = clean.get(idea_id)
        if c is None:
            continue
        for field, kind in FIELDS.items():
            if not same(kind, t[field], c[field]):
                mismatches.append((idea_id, field, t[field], c[field]))

    print(f"ideas in truth:              {len(truth)}")
    print(f"ideas in clean_ideas:        {len(clean)}")
    print(f"  kept with a generated key: {len(generated)}")
    print(f"truth ideas not found:       {len(missing)}")
    print(f"unexpected ideas:            {len(extra)}")
    print(f"field mismatches:            {len(mismatches)}")
    for m in mismatches[:20]:
        print("  ", m)

    ok = not extra and not mismatches and len(missing) == len(generated)
    print("\nRESULT:", "PASS" if ok else "CHECK THE ROWS ABOVE")


if __name__ == "__main__":
    main()
