"""
Script: collect_time_decay_results.py
Pipeline stage: 5. Time-since-collection analysis
Analytical purpose: Collect profiles, model estimates, contrasts, diagnostics, bootstrap chunks,
and leave-one-day-out results into a compact result object.
Inputs: .codex_work/issue4/model_output/time_decay*.csv
Outputs: .codex_work/issue4/time_decay_results.json
Run-order position: 22
Key scientific assumption: No new inferential calculation is introduced during result
collection.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

import csv
import json
from pathlib import Path

import numpy as np


# --- Project locations and reproducible configuration ---
ROOT = Path.cwd()
WORK_DIR = ROOT / ".codex_work" / "issue4"
MODEL_DIR = WORK_DIR / "model_output"


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def typed_row(row):
    result = {}
    for key, value in row.items():
        if value == "":
            result[key] = None
            continue
        if value in {"TRUE", "FALSE"}:
            result[key] = value == "TRUE"
            continue
        try:
            result[key] = float(value)
        except (TypeError, ValueError):
            result[key] = value
    return result


def bootstrap_summary(values, direction):
    values = np.asarray([value for value in values if np.isfinite(value)], dtype=float)
    return {
        "successful_fits": int(values.size),
        "median": float(np.median(values)),
        "ci_low": float(np.quantile(values, 0.025)),
        "ci_high": float(np.quantile(values, 0.975)),
        "direction_fraction": float(np.mean(values < 1 if direction == "below" else values > 1)),
        "minimum": float(np.min(values)),
        "maximum": float(np.max(values)),
    }


profile = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_profile.csv")]
profile_diagnostics = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_diagnostics.csv")]
model_estimates = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_model_estimates.csv")]
window_estimates = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_window_estimates.csv")]
linear_contrasts = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_linear_contrasts.csv")]
model_comparison = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_model_comparison.csv")]
confounding = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_confounding.csv")]
model_diagnostics = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_model_diagnostics.csv")]
smooth_terms = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_smooth_terms.csv")]
loo_summary = [typed_row(row) for row in read_csv(MODEL_DIR / "time_decay_leave_one_day_out_summary.csv")]

bootstrap_files = sorted(
    MODEL_DIR.glob("time_decay_bootstrap_*.csv"),
    key=lambda path: int(path.stem.rsplit("_", 1)[1]),
)
bootstrap_rows = []
for path in bootstrap_files:
    bootstrap_rows.extend(read_csv(path))

hourly_values = []
immediate_values = []
errors = []
for row in bootstrap_rows:
    if row["hourly_rate_ratio"]:
        hourly_values.append(float(row["hourly_rate_ratio"]))
    if row["immediate_rate_ratio"]:
        immediate_values.append(float(row["immediate_rate_ratio"]))
    if row["error"]:
        errors.append(row["error"])

lookup = {row["analysis"]: row for row in model_estimates}
primary = lookup["Linear post-collection decay"]
immediate = lookup["Immediate post-collection level"]
first_six = lookup["Linear decay limited to first 6 hours"]
smooth_term = next(
    row for row in smooth_terms
    if row["term"] == "s(post_collection_hours):post_collection"
)
clock_correlation = next(
    row["value"] for row in confounding
    if row["metric"] == "Clock-hour / elapsed-time correlation"
)
clock_vif = next(
    row["value"] for row in confounding
    if row["metric"] == "Approximate VIF from weighted R-squared"
)

payload = {
    "profile": profile,
    "profile_diagnostics": profile_diagnostics,
    "model_estimates": model_estimates,
    "window_estimates": window_estimates,
    "linear_contrasts": linear_contrasts,
    "model_comparison": model_comparison,
    "confounding": confounding,
    "model_diagnostics": model_diagnostics,
    "smooth_term": smooth_term,
    "bootstrap": {
        "replicates_requested": len(bootstrap_rows),
        "errors": errors,
        "hourly_decay": bootstrap_summary(hourly_values, "below"),
        "immediate_level": bootstrap_summary(immediate_values, "above"),
    },
    "leave_one_day_out": loo_summary,
    "interpretation": {
        "hourly_rate_ratio": primary["effect_ratio"],
        "hourly_percent_decline": 100 * (1 - primary["effect_ratio"]),
        "immediate_rate_ratio": immediate["effect_ratio"],
        "central_return_to_baseline_hours": -immediate["estimate_log"] / primary["estimate_log"],
        "first_six_hour_rate_ratio": first_six["effect_ratio"],
        "clock_time_correlation": clock_correlation,
        "clock_time_vif": clock_vif,
        "plain_language": (
            "The fitted post-collection foraging association declines by about 14% per hour, "
            "with an initially elevated estimate that approaches the pre-collection level after "
            "roughly four hours. The pattern is robust to interval width, observer adjustment, "
            "clock-spline flexibility, and removal of individual days, but is weaker when the "
            "analysis is restricted to the first six hours. Elapsed time remains strongly "
            "correlated with clock time, so the pattern is consistent with a temporary food pulse "
            "rather than proof of resource depletion."
        ),
    },
}

(WORK_DIR / "time_decay_results.json").write_text(
    json.dumps(payload, indent=2), encoding="utf-8"
)
print(json.dumps(payload["bootstrap"], indent=2))
print(json.dumps(payload["interpretation"], indent=2))
