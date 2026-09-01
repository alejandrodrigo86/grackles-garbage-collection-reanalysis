"""
Script: collect_model_results.py
Pipeline stage: 2. Primary analysis
Analytical purpose: Combine primary-model estimates, diagnostics, bootstrap results, and leave-
one-day-out summaries into a compact machine-readable result object.
Inputs: .codex_work/issue4/model_output/primary*.csv and model_estimates.csv
Outputs: .codex_work/issue4/model_results.json
Run-order position: 07
Key scientific assumption: No models are fit here; values are collected from the executed R
outputs without recomputation.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

import csv
import json
from pathlib import Path


# --- Project locations and reproducible configuration ---
ROOT = Path.cwd()
MODEL_OUTPUT = ROOT / ".codex_work" / "issue4" / "model_output"
OUTPUT = ROOT / ".codex_work" / "issue4" / "model_results.json"


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


estimates = read_csv("model_estimates.csv")
diagnostics = read_csv("primary_tweedie_diagnostics.csv")
fixed_effects = read_csv("primary_fixed_effects.csv")
smooth_terms = read_csv("primary_smooth_terms.csv")
bootstrap_summary = read_csv("primary_day_bootstrap_summary.csv")
leave_one_out_summary = read_csv("primary_leave_one_day_out_summary.csv")

primary = next(row for row in estimates if row["analysis"] == "Primary 30-minute model")
diagnostic_map = {row["metric"]: row["value"] for row in diagnostics}
bootstrap_map = {row["metric"]: row["value"] for row in bootstrap_summary}
leave_one_out_map = {row["metric"]: row["value"] for row in leave_one_out_summary}

payload = {
    "primary": primary,
    "estimates": estimates,
    "diagnostics": diagnostics,
    "fixed_effects": fixed_effects,
    "smooth_terms": smooth_terms,
    "bootstrap": bootstrap_summary,
    "leave_one_day_out": leave_one_out_summary,
    "headline": (
        f"Adjusted post-collection rate ratio {primary['rate_ratio']:.2f} "
        f"(95% CI {primary['ci_low']:.2f}–{primary['ci_high']:.2f}; "
        f"p = {primary['p_value']:.3f})."
    ),
    "interpretation": (
        "The estimated association is positive, but the interval includes both a modest decrease "
        "and a substantial increase. The data therefore do not resolve whether garbage collection "
        "changed foraging activity, although the direction is consistent across all declared checks."
    ),
    "diagnostic_summary": {
        "observed_zero_intervals": diagnostic_map["Observed zero intervals"],
        "expected_zero_intervals": diagnostic_map["Expected zero intervals"],
        "tweedie_power": diagnostic_map["Tweedie power parameter"],
        "maximum_absolute_gradient": diagnostic_map["Maximum absolute gradient"],
        "bootstrap_ci_low": bootstrap_map["Bootstrap 2.5th percentile"],
        "bootstrap_ci_high": bootstrap_map["Bootstrap 97.5th percentile"],
        "bootstrap_positive_fraction": bootstrap_map["Proportion of rate ratios above 1"],
        "leave_one_out_min": leave_one_out_map["Minimum rate ratio"],
        "leave_one_out_max": leave_one_out_map["Maximum rate ratio"],
        "leave_one_out_positive_fits": leave_one_out_map["Fits with rate ratio above 1"],
    },
    "software": {
        "R": "4.4.1",
        "mgcv": "1.9-1",
        "nlme": "3.1-164",
    },
}

OUTPUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps(payload["diagnostic_summary"], indent=2))
