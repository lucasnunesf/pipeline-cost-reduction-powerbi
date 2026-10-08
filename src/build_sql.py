"""
build_sql.py

Runs every file in sql/ in name order (01_, 02_, ...) against the database.
All cleaning and business rules live in those SQL files; this script only
executes them.

Run from the repository root:
    python src/build_sql.py
"""

import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL = ROOT / "sql"
DB = ROOT / "data" / "cost_reduction.db"


def main():
    if not DB.exists():
        raise SystemExit("Database not found. Run src/load_raw.py first.")

    con = sqlite3.connect(DB)
    for path in sorted(SQL.glob("*.sql")):
        con.executescript(path.read_text(encoding="utf-8"))
        print(f"ran {path.name}")
    con.commit()

    for table in ["clean_ideas", "clean_idea_area", "clean_targets", "dq_issues"]:
        n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:<16} {n:>5} rows")
    con.close()


if __name__ == "__main__":
    main()
