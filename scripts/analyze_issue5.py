"""
Script: analyze_issue5.py
Pipeline stage: 1. Data reconstruction
Analytical purpose: Summarize interval structure, dispersion, zero frequencies, recording
coverage, daily replication, and candidate outcome distributions before formal modelling.
Inputs: .codex_work/issue4/interval_data.json
Outputs: .codex_work/issue4/issue5_diagnostics.json
Run-order position: 03
Key scientific assumption: Diagnostics describe the reconstructed observations and guide model-
family choice; they are not inferential tests.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


# --- Project locations and reproducible configuration ---
ROOT = Path.cwd()
WORK = ROOT / ".codex_work" / "issue4"


def sample_variance(values):
    return statistics.variance(values) if len(values) > 1 else 0.0


def quantile(sorted_values, probability):
    if not sorted_values:
        return None
    position = (len(sorted_values) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return sorted_values[lower]
    fraction = position - lower
    return sorted_values[lower] * (1 - fraction) + sorted_values[upper] * fraction


def skewness(values):
    n = len(values)
    if n < 3:
        return None
    mean = statistics.mean(values)
    sd = statistics.stdev(values)
    if sd == 0:
        return 0.0
    third = sum(((value - mean) / sd) ** 3 for value in values)
    return n * third / ((n - 1) * (n - 2))


def summarize(values):
    ordered = sorted(values)
    positive = [value for value in ordered if value > 0]
    mean = statistics.mean(values)
    variance = sample_variance(values)
    result = {
        "n": len(values),
        "mean": mean,
        "variance": variance,
        "variance_to_mean": variance / mean if mean else None,
        "zero_n": sum(value == 0 for value in values),
        "zero_fraction": sum(value == 0 for value in values) / len(values),
        "q25": quantile(ordered, 0.25),
        "median": quantile(ordered, 0.5),
        "q75": quantile(ordered, 0.75),
        "max": max(values),
    }
    if positive:
        positive_mean = statistics.mean(positive)
        positive_sd = statistics.stdev(positive) if len(positive) > 1 else 0.0
        result["positive"] = {
            "n": len(positive),
            "mean": positive_mean,
            "median": quantile(positive, 0.5),
            "sd": positive_sd,
            "cv": positive_sd / positive_mean if positive_mean else None,
            "skewness": skewness(positive),
            "max": max(positive),
        }
    return result


def poisson_log_likelihood(counts, mean):
    return sum(value * math.log(mean) - mean - math.lgamma(value + 1) for value in counts)


def nb_log_likelihood(counts, mean, alpha):
    # NB2 parameterization: Var(Y) = mu + alpha * mu^2.
    size = 1.0 / alpha
    probability = size / (size + mean)
    return sum(
        math.lgamma(value + size)
        - math.lgamma(size)
        - math.lgamma(value + 1)
        + size * math.log(probability)
        + value * math.log1p(-probability)
        for value in counts
    )


def maximize_nb_alpha(counts, mean):
    # Golden-section search over log(alpha), adequate for the intercept-only diagnostic.
    lower = math.log(1e-5)
    upper = math.log(100.0)
    ratio = (math.sqrt(5) - 1) / 2
    c = upper - ratio * (upper - lower)
    d = lower + ratio * (upper - lower)
    fc = nb_log_likelihood(counts, mean, math.exp(c))
    fd = nb_log_likelihood(counts, mean, math.exp(d))
    for _ in range(250):
        if fc > fd:
            upper = d
            d = c
            fd = fc
            c = upper - ratio * (upper - lower)
            fc = nb_log_likelihood(counts, mean, math.exp(c))
        else:
            lower = c
            c = d
            fc = fd
            d = lower + ratio * (upper - lower)
            fd = nb_log_likelihood(counts, mean, math.exp(d))
    optimum = (lower + upper) / 2
    alpha = math.exp(optimum)
    return alpha, nb_log_likelihood(counts, mean, alpha)


def pearson(x_values, y_values):
    if len(x_values) < 2:
        return None
    x_mean = statistics.mean(x_values)
    y_mean = statistics.mean(y_values)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_values, y_values))
    x_ss = sum((x - x_mean) ** 2 for x in x_values)
    y_ss = sum((y - y_mean) ** 2 for y in y_values)
    return numerator / math.sqrt(x_ss * y_ss) if x_ss and y_ss else None


data = json.loads((WORK / "interval_data.json").read_text(encoding="utf-8"))
rows = data["interval_rows"]
full_rows = [row for row in rows if abs(row["camera_seconds"] - 1800.0) < 1e-6]

full_bouts = [row["foraging_bouts"] for row in full_rows]
full_foraging_seconds = [row["foraging_seconds"] for row in full_rows]
full_visible_seconds = [row["focal_visible_seconds"] for row in full_rows]

count_mean = statistics.mean(full_bouts)
poisson_ll = poisson_log_likelihood(full_bouts, count_mean)
alpha, nb_ll = maximize_nb_alpha(full_bouts, count_mean)
poisson_aic = -2 * poisson_ll + 2  # one fitted mean parameter
nb_aic = -2 * nb_ll + 4  # fitted mean and alpha
nb_size = 1.0 / alpha
nb_zero = (nb_size / (nb_size + count_mean)) ** nb_size

by_day = defaultdict(list)
for row in sorted(rows, key=lambda item: (item["observation_id"], item["bin_number"])):
    by_day[row["observation_id"]].append(row)

lag_x = []
lag_y = []
for day_rows in by_day.values():
    for previous, current in zip(day_rows, day_rows[1:]):
        if current["bin_number"] == previous["bin_number"] + 1:
            lag_x.append(previous["foraging_bouts"])
            lag_y.append(current["foraging_bouts"])

foraging_bouts_all = [row["foraging_bouts"] for row in rows]
camera_seconds_all = [row["camera_seconds"] for row in rows]
total_bouts = sum(foraging_bouts_all)
total_camera_hours = sum(camera_seconds_all) / 3600.0

diagnostics = {
    "dataset": {
        "interval_rows": len(rows),
        "full_30_minute_rows": len(full_rows),
        "partial_edge_rows": len(rows) - len(full_rows),
        "observation_days": len(by_day),
        "median_bins_per_day": statistics.median(len(day_rows) for day_rows in by_day.values()),
        "min_bins_per_day": min(len(day_rows) for day_rows in by_day.values()),
        "max_bins_per_day": max(len(day_rows) for day_rows in by_day.values()),
    },
    "full_bin_profiles": {
        "foraging_bouts": summarize(full_bouts),
        "foraging_seconds": summarize(full_foraging_seconds),
        "focal_visible_seconds": summarize(full_visible_seconds),
    },
    "count_family_check": {
        "poisson_dispersion_variance_to_mean": sample_variance(full_bouts) / count_mean,
        "nb2_alpha_mle_intercept_only": alpha,
        "poisson_log_likelihood": poisson_ll,
        "poisson_aic": poisson_aic,
        "negative_binomial_log_likelihood": nb_ll,
        "negative_binomial_aic": nb_aic,
        "aic_improvement_nb_over_poisson": poisson_aic - nb_aic,
        "observed_zero_fraction": sum(value == 0 for value in full_bouts) / len(full_bouts),
        "poisson_expected_zero_fraction": math.exp(-count_mean),
        "negative_binomial_expected_zero_fraction": nb_zero,
        "observed_minus_nb_zero_fraction": (
            sum(value == 0 for value in full_bouts) / len(full_bouts) - nb_zero
        ),
    },
    "dependence": {
        "adjacent_pairs": len(lag_x),
        "raw_lag1_foraging_bout_correlation": pearson(lag_x, lag_y),
    },
    "all_bin_exposure": {
        "foraging_bout_rate_per_camera_hour": total_bouts / total_camera_hours,
        "camera_hours": total_camera_hours,
    },
    "decision": {
        "primary_estimand": (
            "Multiplicative change in expected foraging seconds per camera time after the "
            "end of garbage collection, beyond the diurnal pattern and a collection-day baseline."
        ),
        "primary_response": "foraging_seconds",
        "primary_family": "Tweedie mixed-effects model with log link",
        "offset": "log(camera_seconds / 1800)",
        "fixed_effects": [
            "natural cubic spline of clock time with 4 degrees of freedom",
            "collection_day",
            "post_collection_fraction = post_collection_camera_seconds / camera_seconds",
        ],
        "random_effect": "random intercept for observation_id",
        "temporal_check": "inspect residual within-day autocorrelation; add AR(1) sensitivity if retained",
        "primary_interpretation": "event-centred association, not a causal food-abundance effect",
    },
}

(WORK / "issue5_diagnostics.json").write_text(
    json.dumps(diagnostics, indent=2, ensure_ascii=False), encoding="utf-8"
)
print(json.dumps(diagnostics, indent=2, ensure_ascii=False))
