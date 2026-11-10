import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

import load_raw  # noqa: E402

SQL_FILES = sorted((ROOT / "sql").glob("*.sql"))

# One clean idea row, as load_raw.py would land it (all text). Tests change
# only the fields they care about.
BASE_ROW = {
    "source_file": "Group 1/Supplier 001 - Saving Proposals.xlsx",
    "source_row": 8,
    "supplier_raw": "Supplier 001",
    "supplier_code": "S001",
    "commodity_group": "Group 1",
    "last_update_raw": "2026-12-01",
    "idea_id": "CR-S001-001",
    "proposal_name": "Change material of bracket",
    "description": "",
    "responsible": "A. Lima",
    "buyer": "Buyer 1",
    "areas": "Engineering; Quality",
    "vehicle": "Vehicle 1",
    "part_number": "PN-10000",
    "current_cost": "10.0",
    "new_cost": "9.5",
    "annual_volume": "10000",
    "annual_saving_in_file": "=(I8-J8)*M8/1000",
    "status": "Approved",
    "submission_date": "2026-05-01",
    "planned_date": "2026-09-01",
    "actual_date": None,
    "comments": None,
}


def build(rows, targets=(("Vehicle 1", "Apr-26", "100"),)):
    """Land the given rows in an in-memory staging area, run every sql/ file,
    and return the connection. This is the same SQL the pipeline runs."""
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    load_raw.create_tables(con)

    for i, overrides in enumerate(rows):
        row = {**BASE_ROW, "source_row": 8 + i, **overrides}
        names = list(row)
        con.execute(
            f"INSERT INTO stg_supplier_ideas ({', '.join(names)}) "
            f"VALUES ({', '.join('?' for _ in names)})",
            [row[n] for n in names],
        )
    files = {r.get("source_file", BASE_ROW["source_file"]) for r in rows} or {BASE_ROW["source_file"]}
    for f in files:
        con.execute("INSERT INTO stg_load_log VALUES (?, 1, '2026-12-31')", (f,))
    for vehicle, month, value in targets:
        con.execute("INSERT INTO stg_targets VALUES ('targets.xlsx', ?, ?, ?)",
                    (vehicle, month, value))

    for path in SQL_FILES:
        con.executescript(path.read_text(encoding="utf-8"))
    return con


@pytest.fixture
def one(request):
    """Build with a single row and return that idea from clean_ideas."""
    def _one(**overrides):
        con = build([overrides])
        return dict(con.execute("SELECT * FROM clean_ideas").fetchone())
    return _one
