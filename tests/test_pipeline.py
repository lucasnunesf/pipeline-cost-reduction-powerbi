"""End to end: generate the 150 files, load, clean, model, check against the truth."""

import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def run(folder, *args):
    result = subprocess.run([sys.executable, *args], cwd=folder, capture_output=True, text=True)
    return result


@pytest.fixture(scope="module")
def project(tmp_path_factory):
    folder = tmp_path_factory.mktemp("project")
    for name in ("src", "sql", "templates"):
        shutil.copytree(ROOT / name, folder / name)
    result = run(folder, "src/run_pipeline.py", "--generate")
    assert result.returncode == 0, result.stdout + result.stderr
    return folder, result.stdout


def query(folder, sql):
    with sqlite3.connect(folder / "data" / "cost_reduction.db") as con:
        return con.execute(sql).fetchall()


def test_every_file_is_read(project):
    folder, out = project
    assert "150 supplier files read (6 with no ideas), 960 idea rows" in out


def test_cleaning_recovers_every_idea_from_the_truth_file(project):
    folder, out = project
    assert "field mismatches:            0" in out
    assert "RESULT: PASS" in out
    assert query(folder, "SELECT COUNT(*) FROM clean_ideas") == [(912,)]


def test_every_kept_row_can_be_traced_to_its_file(project):
    folder, _ = project
    assert query(folder, "SELECT COUNT(*) FROM fact_idea WHERE source_file IS NULL OR source_row IS NULL") == [(0,)]


def test_data_quality_log_has_every_category(project):
    folder, _ = project
    counts = dict(query(folder, "SELECT category, COUNT(*) FROM dq_issues GROUP BY category"))
    assert counts["Duplicate"] == 48
    assert counts["Saving overwritten"] == 47
    assert counts["Empty file"] == 6


def test_rerun_gives_the_same_numbers(project):
    folder, _ = project
    before = query(folder, "SELECT * FROM vw_overview")
    assert run(folder, "src/run_pipeline.py").returncode == 0
    assert query(folder, "SELECT * FROM vw_overview") == before


def test_broken_cleaning_rule_stops_the_pipeline(project, tmp_path):
    folder, _ = project
    broken = tmp_path / "broken"
    for name in ("src", "sql", "templates", "data"):
        shutil.copytree(folder / name, broken / name)
    # Break the status mapping: 'aprovado' no longer maps to Approved.
    sql = broken / "sql" / "01_mappings.sql"
    sql.write_text(sql.read_text().replace("('aprovado',                    'Approved'),", ""))
    result = run(broken, "src/run_pipeline.py")
    assert result.returncode != 0
    assert "CHECK THE ROWS ABOVE" in result.stdout
    assert "Stopped: check_truth.py failed." in result.stderr + result.stdout
