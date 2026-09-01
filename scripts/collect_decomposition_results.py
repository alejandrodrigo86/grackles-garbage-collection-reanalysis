"""
Script: collect_decomposition_results.py
Pipeline stage: 3. Attendance/intensity decomposition
Analytical purpose: Collect decomposition estimates, profiles, diagnostics, cluster bootstrap,
and leave-one-day-out results into one JSON result object.
Inputs: .codex_work/issue4/model_output/decomposition*.csv and model_results.json
Outputs: .codex_work/issue4/decomposition_results.json
Run-order position: 11
Key scientific assumption: This reporting step does not modify model estimates.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

import csv
import json
import math
from pathlib import Path


# --- Project locations and reproducible configuration ---
ROOT = Path.cwd()
WORK = ROOT / ".codex_work" / "issue4"
MODEL_OUTPUT = WORK / "model_output"
OUTPUT = WORK / "decomposition_results.json"


def typed(value):
    if value == "":
        return None
    try:
        return float(value)
    except ValueError:
        return value


def read_csv(name):
    with (MODEL_OUTPUT / name).open(newline="", encoding="utf-8-sig") as stream:
        return [{key: typed(value) for key, value in row.items()} for row in csv.DictReader(stream)]


estimates = read_csv("decomposition_estimates.csv")
profiles = read_csv("decomposition_profiles.csv")
diagnostics = read_csv("decomposition_diagnostics.csv")
bootstrap = read_csv("decomposition_day_bootstrap_summary.csv")
leave_one_out = read_csv("decomposition_leave_one_day_out_summary.csv")
total_results = json.loads((WORK / "model_results.json").read_text(encoding="utf-8"))

attendance = next(row for row in estimates if row["analysis"] == "Attendance primary 30-minute")
intensity = next(row for row in estimates if row["analysis"] == "Intensity primary 30-minute")
fractional = next(row for row in estimates if row["analysis"] == "Intensity fractional-logit sensitivity")
attendance_bootstrap = next(row for row in bootstrap if row["mechanism"] == "Patch attendance")
intensity_bootstrap = next(row for row in bootstrap if row["mechanism"] == "Conditional foraging intensity")
product_bootstrap = next(row for row in bootstrap if row["mechanism"] == "Attendance × intensity")
attendance_loo = next(row for row in leave_one_out if row["mechanism"] == "Patch attendance")
intensity_loo = next(row for row in leave_one_out if row["mechanism"] == "Conditional foraging intensity")
product_loo = next(row for row in leave_one_out if row["mechanism"] == "Attendance × intensity")

combined_log = attendance["estimate_log"] + intensity["estimate_log"]
combined_ratio = math.exp(combined_log)
attendance_log_share = attendance["estimate_log"] / combined_log if combined_log else None

payload = {
    "attendance": attendance,
    "intensity": intensity,
    "fractional_logit": fractional,
    "estimates": estimates,
    "profiles": profiles,
    "diagnostics": diagnostics,
    "bootstrap": bootstrap,
    "leave_one_day_out": leave_one_out,
    "combined": {
        "product_ratio": combined_ratio,
        "total_primary_ratio": total_results["primary"]["rate_ratio"],
        "attendance_log_share": attendance_log_share,
        "bootstrap_ci_low": product_bootstrap["ci_low"],
        "bootstrap_ci_high": product_bootstrap["ci_high"],
        "bootstrap_fraction_above_one": product_bootstrap["fraction_above_one"],
        "leave_one_out_min": product_loo["minimum_ratio"],
        "leave_one_out_max": product_loo["maximum_ratio"],
        "leave_one_out_positive": product_loo["fits_above_one"],
    },
    "stability": {
        "attendance_bootstrap_ci_low": attendance_bootstrap["ci_low"],
        "attendance_bootstrap_ci_high": attendance_bootstrap["ci_high"],
        "attendance_bootstrap_fraction_above_one": attendance_bootstrap["fraction_above_one"],
        "intensity_bootstrap_ci_low": intensity_bootstrap["ci_low"],
        "intensity_bootstrap_ci_high": intensity_bootstrap["ci_high"],
        "intensity_bootstrap_fraction_above_one": intensity_bootstrap["fraction_above_one"],
        "attendance_loo_min": attendance_loo["minimum_ratio"],
        "attendance_loo_max": attendance_loo["maximum_ratio"],
        "attendance_loo_positive": attendance_loo["fits_above_one"],
        "intensity_loo_min": intensity_loo["minimum_ratio"],
        "intensity_loo_max": intensity_loo["maximum_ratio"],
        "intensity_loo_positive": intensity_loo["fits_above_one"],
    },
    "headline": (
        f"The positive post-collection estimate is concentrated in patch attendance "
        f"(RR {attendance['effect_ratio']:.2f}, 95% CI {attendance['ci_low']:.2f}–{attendance['ci_high']:.2f}), "
        f"not conditional foraging intensity "
        f"(RR {intensity['effect_ratio']:.2f}, 95% CI {intensity['ci_low']:.2f}–{intensity['ci_high']:.2f})."
    ),
    "interpretation": (
        "The data are most consistent with grackles spending more time present at the patch after collection, "
        "while allocating approximately the same fraction of their visible time to foraging. Attendance remains "
        "imprecisely estimated, so this is a mechanistic pattern rather than a demonstrated effect."
    ),
}

OUTPUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps({"headline": payload["headline"], "combined": payload["combined"], "stability": payload["stability"]}, indent=2))
