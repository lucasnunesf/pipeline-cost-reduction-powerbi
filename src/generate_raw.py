"""
generate_raw.py

Creates the synthetic source data for the project:

  data/raw/Group N/Supplier XXX - Saving Proposals.xlsx   one workbook per supplier
  data/raw/targets.xlsx                                    savings target from finance
  data/truth/ideas_truth.csv                               the clean answer, used later
                                                           to check the cleaning step

Every supplier file is a copy of templates/supplier_template.xlsx filled with
random ideas. On purpose, the files carry the defects found in real
hand-filled spreadsheets (see DEFECTS below), so the pipeline has real
cleaning work to do.

Run from the repository root:
    python src/generate_raw.py
"""

import csv
import random
import shutil
from datetime import date, timedelta
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font

# ---------------------------------------------------------------- settings
SEED = 42                       # same seed = same files every run
N_SUPPLIERS = 150
GROUPS = ["Group 1", "Group 2", "Group 3", "Group 4"]
BUYERS = ["Buyer 1", "Buyer 2", "Buyer 3", "Buyer 4"]
VEHICLES = ["Vehicle 1", "Vehicle 2", "Vehicle 3", "Vehicle 4", "Vehicle 5"]
AREAS = ["Engineering", "Quality", "Logistics", "Production", "Purchasing"]

FY_START = date(2026, 4, 1)     # fiscal year: April to March
FY_END = date(2027, 3, 31)
AS_OF = date(2026, 12, 31)      # "today" for the data: files were last collected here

# How often each defect happens (0.10 = 10% of the cases)
DEFECTS = {
    "supplier_name_variant": 0.20,  # "SUPPLIER 001 ", "Supplier 1", "Suppl. 001"
    "header_date_as_text": 0.20,    # last update typed as text
    "text_spaces": 0.10,            # leading / trailing spaces in text cells
    "buyer_variant": 0.15,          # "buyer 2", "Buyer2", "B2"
    "vehicle_variant": 0.15,        # "VEH 3", "vehicle3"
    "status_variant": 0.30,         # "approved", "Aprovado", "APPROVED "
    "areas_separator": 0.40,        # "/" or "," instead of ";"
    "date_as_text": 0.30,           # dates typed as text in mixed formats
    "number_as_text": 0.25,         # "12,40", "$12.40", "48.000"
    "missing_idea_id": 0.02,        # ID left blank
    "duplicate_in_file": 0.03,      # same row pasted twice in one file
    "duplicate_other_file": 0.02,   # same idea copied into another supplier file
    "overwritten_formula": 0.05,    # saving typed by hand over the formula
    "blank_rows": 0.30,             # file has empty rows in the middle
    "empty_file": 0.05,             # supplier sent the template with no ideas
}

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "templates" / "supplier_template.xlsx"
RAW = ROOT / "data" / "raw"
TRUTH = ROOT / "data" / "truth"

FIRST_ROW = 8   # first data row in the template
STATUS_WEIGHTS = {"Proposed": 15, "Under study": 20, "Approved": 25,
                  "Implemented": 35, "Cancelled": 5}

ACTIONS = ["Change packaging of", "Reduce wall thickness of", "Localize production of",
           "Combine parts in", "Change material of", "Optimize transport route for",
           "Standardize fasteners in", "Remove paint layer from", "Reduce scrap in",
           "Increase batch size of"]
PARTS = ["door panel", "seat frame", "mounting bracket", "wire harness", "bumper beam",
         "dashboard support", "exhaust clamp", "brake hose", "mirror housing",
         "fuel line", "radiator support", "floor carpet"]
PEOPLE = ["A. Lima", "B. Santos", "C. Rocha", "D. Alves", "E. Costa", "F. Melo",
          "G. Pires", "H. Dias", "I. Moura", "J. Souza", "K. Reis", "L. Nunes"]

rng = random.Random(SEED)


def chance(defect):
    return rng.random() < DEFECTS[defect]


# ---------------------------------------------------------------- clean data
def make_idea(code, seq, buyer):
    """One idea, with clean values. This is the 'truth'."""
    action, part = rng.choice(ACTIONS), rng.choice(PARTS)
    status = rng.choices(list(STATUS_WEIGHTS), weights=STATUS_WEIGHTS.values())[0]

    submitted = FY_START + timedelta(days=rng.randint(0, (AS_OF - FY_START).days))
    planned = submitted + timedelta(days=rng.randint(30, 180))
    actual = None
    if status == "Implemented":
        actual = planned + timedelta(days=rng.randint(-20, 60))
        if actual > AS_OF:          # not in production yet, so still only approved
            status, actual = "Approved", None

    current = round(rng.uniform(0.5, 40), 2)
    new = round(current * (1 - rng.uniform(0.01, 0.06)), 2)

    return {
        "idea_id": f"CR-{code}-{seq:03d}",
        "proposal_name": f"{action} {part}",
        "description": f"{action} the {part} to lower the unit price",
        "responsible": rng.choice(PEOPLE),
        "buyer": buyer,
        "areas": "; ".join(sorted(rng.sample(AREAS, rng.randint(1, 3)))),
        "vehicle": rng.choice(VEHICLES),
        "part_number": f"PN-{rng.randint(10000, 99999)}",
        "current_cost": current,
        "new_cost": new,
        "annual_volume": rng.randrange(1000, 50000, 500),
        "status": status,
        "submission_date": submitted,
        "planned_date": planned,
        "actual_date": actual,
    }


# ---------------------------------------------------------------- defects
def messy_text(value):
    if value and chance("text_spaces"):
        return rng.choice([" ", "  ", ""]) + value + rng.choice([" ", "  "])
    return value


def messy_date(d):
    if d is None or not chance("date_as_text"):
        return d
    return d.strftime(rng.choice(["%d/%m/%Y", "%Y-%m-%d", "%d.%m.%y", "%d/%m/%y"]))


def messy_money(x):
    if not chance("number_as_text"):
        return x
    br = f"{x:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")  # 1.250,00
    return rng.choice([br, f"${x:,.2f}", f"{x:.2f} USD"])


def messy_volume(n):
    if not chance("number_as_text"):
        return n
    return rng.choice([f"{n:,}".replace(",", "."), f"{n:,}", f"{n} pcs"])


def messy_buyer(b):
    if not chance("buyer_variant"):
        return messy_text(b)
    num = b.split()[-1]
    return rng.choice([b.lower(), f"Buyer{num}", f"B{num}", b.upper()])


def messy_vehicle(v):
    if not chance("vehicle_variant"):
        return messy_text(v)
    num = v.split()[-1]
    return rng.choice([f"VEH {num}", f"vehicle{num}", f"V{num}", v.upper()])


STATUS_VARIANTS = {
    "Proposed": ["proposed", "Proposta", "PROPOSED", "New"],
    "Under study": ["under study", "Under Study", "Em estudo", "In study"],
    "Approved": ["approved", "Aprovado", "APPROVED ", "Approved - waiting supplier"],
    "Implemented": ["implemented", "Implementado", "Done", "IMPLEMENTED"],
    "Cancelled": ["canceled", "Cancelado", "cancelled", "Dropped"],
}


def messy_status(s):
    return rng.choice(STATUS_VARIANTS[s]) if chance("status_variant") else s


def messy_areas(a):
    if not chance("areas_separator"):
        return a
    sep = rng.choice([" / ", ", ", ",", "/"])
    parts = a.split("; ")
    if rng.random() < 0.5:
        parts = [p.lower() for p in parts]
    return sep.join(parts)


def messy_supplier(name, code):
    if not chance("supplier_name_variant"):
        return name
    num = code[1:]
    return rng.choice([f"SUPPLIER {num} ", f"Supplier {int(num)}", f"Suppl. {num}",
                       f"supplier {num}"])


# ---------------------------------------------------------------- writing
def write_row(ws, r, idea):
    """Write one idea into row r, applying the cell-level defects."""
    values = {
        "A": idea["idea_id"] if not chance("missing_idea_id") else None,
        "B": messy_text(idea["proposal_name"]),
        "C": idea["description"],
        "D": messy_text(idea["responsible"]),
        "E": messy_buyer(idea["buyer"]),
        "F": messy_areas(idea["areas"]),
        "G": messy_vehicle(idea["vehicle"]),
        "H": idea["part_number"],
        "I": messy_money(idea["current_cost"]),
        "J": messy_money(idea["new_cost"]),
        "M": messy_volume(idea["annual_volume"]),
        "O": messy_status(idea["status"]),
        "P": messy_date(idea["submission_date"]),
        "Q": messy_date(idea["planned_date"]),
        "R": messy_date(idea["actual_date"]),
    }
    for col, v in values.items():
        ws[f"{col}{r}"] = v
    if chance("overwritten_formula"):           # someone typed over the formula
        ws[f"N{r}"] = round(rng.uniform(1, 80), 1)


def clear_example_row(ws):
    """The template ships with an example in row 8. Remove it (keep formulas)."""
    for col in "ABCDEFGHIJMOPQRS":
        cell = ws[f"{col}{FIRST_ROW}"]
        cell.value = None
        cell.font = Font(name="Arial", color="0000FF")


def build_supplier_files():
    if RAW.exists():
        shutil.rmtree(RAW)
    truth = []
    files = []                                  # (path, ws rows to copy later)

    for i in range(1, N_SUPPLIERS + 1):
        code = f"S{i:03d}"
        name = f"Supplier {i:03d}"
        group = rng.choice(GROUPS)
        buyer = rng.choice(BUYERS)              # each supplier has one main buyer

        n_ideas = 0 if chance("empty_file") else rng.randint(1, 12)
        ideas = [make_idea(code, s, buyer) for s in range(1, n_ideas + 1)]
        for idea in ideas:
            truth.append({"supplier_code": code, "supplier": name, "group": group, **idea})

        # rows as they will appear in the file: duplicates and blank rows added
        rows = []
        for idea in ideas:
            rows.append(idea)
            if chance("duplicate_in_file"):
                rows.append(idea)
        if rows and chance("blank_rows"):
            for _ in range(rng.randint(1, 3)):
                rows.insert(rng.randint(0, len(rows)), None)

        last_update = AS_OF - timedelta(days=rng.randint(0, 60))
        files.append({"code": code, "name": name, "group": group, "rows": rows,
                      "last_update": last_update})

    # some ideas get copied into another supplier file of the same group
    for f in files:
        for idea in [r for r in f["rows"] if r]:
            if chance("duplicate_other_file"):
                others = [o for o in files if o["group"] == f["group"] and o is not f]
                if others:
                    rng.choice(others)["rows"].append(idea)

    for f in files:
        wb = load_workbook(TEMPLATE)
        ws = wb["Proposals"]
        clear_example_row(ws)
        ws["B3"] = messy_supplier(f["name"], f["code"])
        ws["E3"] = f["code"]
        ws["B4"] = f["group"]
        lu = f["last_update"]
        ws["E4"] = lu.strftime("%d/%m/%Y") if chance("header_date_as_text") else lu

        for offset, idea in enumerate(f["rows"]):
            if idea:
                write_row(ws, FIRST_ROW + offset, idea)

        folder = RAW / f["group"]
        folder.mkdir(parents=True, exist_ok=True)
        wb.save(folder / f"{f['name']} - Saving Proposals.xlsx")

    return truth


def build_targets(truth):
    """Finance target per vehicle and fiscal month, in USD thousands.
    Wide layout (one column per month), the way finance usually sends it."""
    months = []
    d = FY_START
    while d <= FY_END:
        months.append(d)
        d = date(d.year + (d.month == 12), d.month % 12 + 1, 1)

    # target = a bit below everything the ideas could deliver, so the year is tight
    potential = {v: 0.0 for v in VEHICLES}
    for t in truth:
        if t["status"] != "Cancelled":
            potential[t["vehicle"]] += (t["current_cost"] - t["new_cost"]) * t["annual_volume"] / 1000

    wb = Workbook()
    ws = wb.active
    ws.title = "Targets"
    ws["A1"] = "Cost reduction target FY2026 (USD K)"
    ws.append([])
    ws.append(["Vehicle"] + [m.strftime("%b-%y") for m in months] + ["Total"])
    for v in VEHICLES:
        yearly = potential[v] * rng.uniform(0.85, 1.0)
        weights = [rng.uniform(0.6, 1.4) for _ in months]
        monthly = [round(yearly * w / sum(weights), 1) for w in weights]
        ws.append([v] + monthly + [round(sum(monthly), 1)])
    wb.save(RAW / "targets.xlsx")


def write_truth(truth):
    TRUTH.mkdir(parents=True, exist_ok=True)
    with open(TRUTH / "ideas_truth.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(truth[0]))
        w.writeheader()
        w.writerows(truth)


if __name__ == "__main__":
    truth = build_supplier_files()
    build_targets(truth)
    write_truth(truth)
    n_files = len(list(RAW.rglob("Supplier*.xlsx")))
    print(f"{n_files} supplier files, {len(truth)} ideas, targets.xlsx -> {RAW}")
