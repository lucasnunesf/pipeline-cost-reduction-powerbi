"""Business rules in sql/03_model.sql and sql/04_views.sql."""

import pytest

from conftest import build

AS_OF = "2026-12-31"   # params.as_of_date


def fact(**overrides):
    con = build([overrides])
    return dict(con.execute("SELECT * FROM fact_idea").fetchone())


def test_open_idea_past_its_planned_date_is_delayed():
    idea = fact(status="Approved", planned_date="2026-12-01")
    assert idea["is_delayed"] == 1
    assert idea["days_late"] == 30


def test_open_idea_planned_after_the_reference_date_is_not_delayed():
    assert fact(status="Approved", planned_date="2027-01-15")["is_delayed"] == 0


@pytest.mark.parametrize("status", ["Implemented", "Cancelled"])
def test_closed_ideas_are_never_delayed(status):
    idea = fact(status=status, planned_date="2026-06-01", actual_date="2026-07-01")
    assert idea["is_delayed"] == 0


def test_implemented_saving_counts_in_the_month_it_went_live():
    idea = fact(status="Implemented", actual_date="2026-08-17")
    assert idea["saving_month"] == "2026-08-01"


def test_fiscal_calendar_runs_april_to_march():
    con = build([{}])
    row = lambda d: dict(con.execute("SELECT * FROM dim_calendar WHERE date = ?", (d,)).fetchone())
    assert (row("2026-04-01")["fiscal_year"], row("2026-04-01")["fiscal_month_no"]) == ("FY2026", 1)
    assert (row("2027-03-31")["fiscal_year"], row("2027-03-31")["fiscal_month_no"]) == ("FY2026", 12)
    assert row("2026-12-15")["fiscal_quarter"] == "Q3"


def test_late_idea_is_forecast_in_the_month_after_the_reference_date():
    con = build([{"status": "Approved", "planned_date": "2026-06-01", "current_cost": "10",
                  "new_cost": "9", "annual_volume": "1000"}])
    by_month = {r["month_start"]: r["forecast_cum_k"] for r in con.execute("SELECT * FROM vw_fy_cumulative")}
    assert by_month["2026-12-01"] == 0
    assert by_month["2027-01-01"] == pytest.approx(1.0)


def test_vehicle_page_and_fiscal_year_page_expect_the_same_saving():
    # Two pages of the same report answer "how much will we deliver this
    # fiscal year?". An idea planned after March 2027 cannot count on one
    # page and not on the other.
    con = build([
        {"idea_id": "CR-S001-001", "status": "Implemented", "actual_date": "2026-08-10"},
        {"idea_id": "CR-S001-002", "status": "Approved", "planned_date": "2027-02-01",
         "part_number": "PN-2"},
        {"idea_id": "CR-S001-003", "status": "Under study", "planned_date": "2027-06-01",
         "part_number": "PN-3"},   # after the fiscal year ends
    ])
    vehicle = con.execute(
        "SELECT SUM(implemented_k + approved_k + under_study_k) FROM vw_vehicle_status"
    ).fetchone()[0]
    fiscal = con.execute(
        "SELECT forecast_cum_k FROM vw_fy_cumulative WHERE fiscal_month_no = 12"
    ).fetchone()[0]
    assert vehicle == pytest.approx(fiscal)
    assert fiscal == pytest.approx(10.0)   # two of the three ideas, 5.0 each
