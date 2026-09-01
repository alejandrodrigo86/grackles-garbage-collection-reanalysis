"""
Script: collect_displacement_results.py
Pipeline stage: 4. Agonistic displacement analysis
Analytical purpose: Combine model, direction, phase, family-profile, bootstrap, and leave-one-
day-out outputs into a single result object.
Inputs: .codex_work/issue4/model_output/displacement*.csv; displacement_profile_30min.json;
decomposition_results.json
Outputs: .codex_work/issue4/displacement_results.json
Run-order position: 17
Key scientific assumption: Interpretation remains patch-level because individual birds were not
marked.
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


def bootstrap_summary(values):
    values = np.asarray([value for value in values if np.isfinite(value)], dtype=float)
    return {
        "successful_fits": int(values.size),
        "median": float(np.median(values)),
        "ci_low": float(np.quantile(values, 0.025)),
        "ci_high": float(np.quantile(values, 0.975)),
        "fraction_above_one": float(np.mean(values > 1)),
        "minimum": float(np.min(values)),
        "maximum": float(np.max(values)),
    }


model_estimates = [
    typed_row(row)
    for row in read_csv(MODEL_DIR / "displacement_model_estimates.csv")
]
directional_tests = [
    typed_row(row)
    for row in read_csv(MODEL_DIR / "displacement_directional_models.csv")
]
phase_summary = [
    typed_row(row)
    for row in read_csv(MODEL_DIR / "displacement_phase_summary.csv")
]
family_profile = [
    typed_row(row)
    for row in read_csv(MODEL_DIR / "displacement_family_profile.csv")
]
loo_summary = [
    typed_row(row)
    for row in read_csv(MODEL_DIR / "displacement_leave_one_day_out_summary.csv")
]

bootstrap_files = sorted(
    MODEL_DIR.glob("displacement_bootstrap_*.csv"),
    key=lambda path: int(path.stem.rsplit("_", 1)[1]),
)
bootstrap_rows = []
for path in bootstrap_files:
    bootstrap_rows.extend(read_csv(path))

camera_values = []
opportunity_values = []
complete_errors = []
for row in bootstrap_rows:
    if row["camera_rate_ratio"]:
        camera_values.append(float(row["camera_rate_ratio"]))
    if row["opportunity_adjusted_rate_ratio"]:
        opportunity_values.append(float(row["opportunity_adjusted_rate_ratio"]))
    if row["error"]:
        complete_errors.append(row["error"])

profile = json.loads((WORK_DIR / "displacement_profile_30min.json").read_text(encoding="utf-8"))
decomposition = json.loads((WORK_DIR / "decomposition_results.json").read_text(encoding="utf-8"))

lookup = {row["analysis"]: row for row in model_estimates}
camera_result = lookup["Total displacement per camera exposure"]
opportunity_result = lookup["Opportunity-adjusted displacement rate"]
foraging_result = lookup["Displacement rate during foraging"]

payload = {
    "profile": profile,
    "phase_summary": phase_summary,
    "model_estimates": model_estimates,
    "family_profile": family_profile,
    "directional_tests": directional_tests,
    "bootstrap": {
        "replicates_requested": len(bootstrap_rows),
        "errors": complete_errors,
        "camera": bootstrap_summary(camera_values),
        "opportunity_adjusted": bootstrap_summary(opportunity_values),
    },
    "leave_one_day_out": loo_summary,
    "interpretation": {
        "camera_rate_ratio": camera_result["effect_ratio"],
        "opportunity_adjusted_rate_ratio": opportunity_result["effect_ratio"],
        "foraging_exposure_rate_ratio": foraging_result["effect_ratio"],
        "attendance_rate_ratio": decomposition["attendance"]["effect_ratio"],
        "camera_to_opportunity_log_attenuation_fraction": float(
            1
            - np.log(opportunity_result["effect_ratio"])
            / np.log(camera_result["effect_ratio"])
        ),
        "plain_language": (
            "The central post-collection estimate falls from 1.48 per camera time to "
            "1.20 per focal-visible time. The remaining rate estimate is imprecise and "
            "compatible with a substantial decrease or increase. The data do not show "
            "that displacement activity increased beyond focal-presence opportunity."
        ),
    },
}

(WORK_DIR / "displacement_results.json").write_text(
    json.dumps(payload, indent=2), encoding="utf-8"
)
print(json.dumps(payload["bootstrap"], indent=2))
print(json.dumps(payload["interpretation"], indent=2))
