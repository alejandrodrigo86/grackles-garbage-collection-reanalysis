from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path


ROOT = Path.cwd()
INPUT = ROOT / ".codex_work" / "issue4" / "displacement_data_30min.csv"
OUTPUT_DIR = ROOT / ".codex_work" / "v4_full_revision"
DETAIL_OUTPUT = OUTPUT_DIR / "schedule_sensitivity_by_day.csv"
SUMMARY_OUTPUT = OUTPUT_DIR / "schedule_sensitivity_summary.csv"


with INPUT.open(newline="", encoding="utf-8-sig") as handle:
    rows = list(csv.DictReader(handle))

collection_rows = [row for row in rows if int(float(row["collection_day"])) == 1]

by_day_phase: dict[tuple[str, str, str, str], dict[str, float]] = defaultdict(
    lambda: {"camera_seconds": 0.0, "foraging_seconds": 0.0}
)
for row in collection_rows:
    weekday = row["weekday"]
    schedule = "Regular (Wednesday/Friday)" if weekday in {"Wednesday", "Friday"} else "Off-schedule"
    phase = "Postcollection" if int(float(row["post_collection"])) == 1 else "Precollection"
    key = (row["observation_id"], row["observation_date"], weekday, schedule, phase)
    by_day_phase[key]["camera_seconds"] += float(row["segment_seconds"])
    by_day_phase[key]["foraging_seconds"] += float(row["foraging_seconds"])

detail_rows = []
for key, totals in sorted(by_day_phase.items(), key=lambda item: (item[0][1], item[0][4])):
    observation_id, date, weekday, schedule, phase = key
    camera_hours = totals["camera_seconds"] / 3600.0
    rate = totals["foraging_seconds"] / camera_hours if camera_hours else float("nan")
    detail_rows.append(
        {
            "observation_id": observation_id,
            "observation_date": date,
            "weekday": weekday,
            "schedule_group": schedule,
            "phase": phase,
            "camera_hours": camera_hours,
            "foraging_hours": totals["foraging_seconds"] / 3600.0,
            "foraging_seconds_per_camera_hour": rate,
        }
    )

summary_accumulator: dict[tuple[str, str], dict[str, float | set[str]]] = defaultdict(
    lambda: {"camera_seconds": 0.0, "foraging_seconds": 0.0, "days": set()}
)
for row in detail_rows:
    key = (row["schedule_group"], row["phase"])
    summary_accumulator[key]["camera_seconds"] += float(row["camera_hours"]) * 3600.0
    summary_accumulator[key]["foraging_seconds"] += float(row["foraging_hours"]) * 3600.0
    summary_accumulator[key]["days"].add(str(row["observation_date"]))

summary_rows = []
for schedule in ("Regular (Wednesday/Friday)", "Off-schedule"):
    phase_rates = {}
    for phase in ("Precollection", "Postcollection"):
        totals = summary_accumulator[(schedule, phase)]
        camera_hours = float(totals["camera_seconds"]) / 3600.0
        rate = float(totals["foraging_seconds"]) / camera_hours
        phase_rates[phase] = rate
        summary_rows.append(
            {
                "schedule_group": schedule,
                "observation_days": len(totals["days"]),
                "phase": phase,
                "camera_hours": camera_hours,
                "foraging_hours": float(totals["foraging_seconds"]) / 3600.0,
                "foraging_seconds_per_camera_hour": rate,
                "post_to_pre_raw_rate_ratio": "",
            }
        )
    ratio = phase_rates["Postcollection"] / phase_rates["Precollection"]
    for row in summary_rows[-2:]:
        row["post_to_pre_raw_rate_ratio"] = ratio

fieldnames_detail = list(detail_rows[0])
with DETAIL_OUTPUT.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames_detail)
    writer.writeheader()
    writer.writerows(detail_rows)

fieldnames_summary = list(summary_rows[0])
with SUMMARY_OUTPUT.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames_summary)
    writer.writeheader()
    writer.writerows(summary_rows)

print(DETAIL_OUTPUT)
print(SUMMARY_OUTPUT)
for row in summary_rows:
    print(row)
