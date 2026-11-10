"""Cleaning rules in sql/02_clean.sql, one defect at a time."""

import pytest

from conftest import build


@pytest.mark.parametrize("typed, expected", [
    ("12.40", 12.40),
    ("12,40", 12.40),          # Brazilian decimal comma
    ("1.250,00", 1250.00),     # Brazilian thousands and decimals
    ("$1,250.00", 1250.00),    # US format with currency sign
    ("12.40 USD", 12.40),
])
def test_money_typed_as_text(one, typed, expected):
    assert one(current_cost=typed)["current_cost"] == pytest.approx(expected)


@pytest.mark.parametrize("typed, expected", [
    ("48000", 48000), ("48.000", 48000), ("48,000", 48000),
    ("16000 pcs", 16000), ("16000.0", 16000),
])
def test_volume_typed_as_text(one, typed, expected):
    assert one(annual_volume=typed)["annual_volume"] == expected


@pytest.mark.parametrize("typed", ["2026-07-30", "30/07/2026", "30/07/26", "30.07.26"])
def test_dates_are_read_day_first(one, typed):
    assert one(planned_date=typed)["planned_date"] == "2026-07-30"


@pytest.mark.parametrize("typed, expected", [
    ("aprovado", "Approved"), ("APPROVED ", "Approved"),
    ("Approved - waiting supplier", "Approved"), ("Em estudo", "Under study"),
    ("Done", "Implemented"), ("Dropped", "Cancelled"),
    ("something new", "Unknown"),   # unmapped: kept, not dropped
])
def test_status_spellings(one, typed, expected):
    assert one(status=typed)["status"] == expected


@pytest.mark.parametrize("typed", ["B2", "buyer 2", "Buyer2", "BUYER 2", " Buyer 2 "])
def test_buyer_spellings(one, typed):
    assert one(buyer=typed)["buyer"] == "Buyer 2"


def test_areas_are_split_whatever_the_separator(one):
    idea = one(areas="engineering / Quality,logistics")
    assert idea["areas"] == "Engineering; Logistics; Quality"


def test_saving_is_recalculated_not_trusted(one):
    idea = one(current_cost="10", new_cost="9", annual_volume="2000",
               annual_saving_in_file="55.5")
    assert idea["annual_saving_k"] == pytest.approx(2.0)   # (10 - 9) * 2000 / 1000


def test_overwritten_formula_is_logged():
    con = build([{"annual_saving_in_file": "55.5"}])
    issue = con.execute("SELECT * FROM dq_issues WHERE category = 'Saving overwritten'").fetchone()
    assert issue["action"] == "Recalculated from cost and volume"


def test_idea_copied_into_another_file_keeps_the_owners_copy():
    con = build([
        {"source_file": "Group 1/Supplier 002 - Saving Proposals.xlsx",
         "supplier_code": "S002", "supplier_raw": "Supplier 002",
         "last_update_raw": "2026-12-30"},          # newer, but not the owner
        {},                                          # S001's own file
    ])
    rows = con.execute("SELECT supplier_code, source_file FROM clean_ideas").fetchall()
    assert len(rows) == 1
    assert rows[0]["supplier_code"] == "S001"
    assert "Supplier 001" in rows[0]["source_file"]


def test_same_idea_twice_in_one_file_is_kept_once():
    con = build([{}, {}])
    assert con.execute("SELECT COUNT(*) FROM clean_ideas").fetchone()[0] == 1
    assert con.execute("SELECT COUNT(*) FROM dq_issues WHERE category = 'Duplicate'").fetchone()[0] == 1


def test_missing_id_is_recovered_from_another_copy():
    con = build([
        {},
        {"idea_id": None, "source_file": "Group 1/Supplier 001 - Saving Proposals.xlsx"},
    ])
    assert [r[0] for r in con.execute("SELECT idea_id FROM clean_ideas")] == ["CR-S001-001"]


def test_missing_id_with_no_copy_gets_a_generated_key(one):
    assert one(idea_id=None, proposal_name="Unique idea")["idea_id"] == "NOID-S001-8"


def test_supplier_name_comes_from_the_code_not_the_header(one):
    assert one(supplier_raw="SUPPL. 001 ")["supplier"] == "Supplier 001"
