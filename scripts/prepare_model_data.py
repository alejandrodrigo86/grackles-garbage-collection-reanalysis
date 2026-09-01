"""
Script: prepare_model_data.py
Pipeline stage: 1. Data reconstruction
Analytical purpose: Flatten reconstructed interval JSON into model-ready CSV rows with exposure,
time, collection-phase, foraging, visibility, and displacement fields.
Inputs: Command-line INPUT_JSON created by extract_interval_data.py
Outputs: Command-line OUTPUT_CSV (used as model_data_30min.csv and, where requested, sensitivity
datasets)
Run-order position: 02
Key scientific assumption: Partial intervals retain their actual camera seconds so models can
use an exposure offset.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

import csv
import json
import sys
from datetime import datetime
from pathlib import Path


def parse_datetime(value):
    return datetime.fromisoformat(value) if value else None


# --- Execute the complete script workflow ---
def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare_model_data.py INPUT_JSON OUTPUT_CSV")

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    payload = json.loads(input_path.read_text(encoding="utf-8"))
    rows = sorted(
        payload["interval_rows"],
        key=lambda row: (row["observation_date"], row["observation_id"], row["bin_number"]),
    )

    fieldnames = [
        "observation_id",
        "observation_date",
        "weekday",
        "observer",
        "collection_day",
        "bin_number",
        "clock_hour",
        "camera_seconds",
        "post_collection_camera_seconds",
        "post_collection_fraction",
        "hours_from_collection_midpoint",
        "collection_phase",
        "foraging_seconds",
        "foraging_bouts",
        "focal_visible_seconds",
        "displacement_events",
        "displacement_focal_to_others",
        "displacement_others_to_focal",
        "displacement_unspecified",
        "any_foraging",
        "full_bin",
        "ar_start",
        "exclude_n3",
    ]

    previous_observation = None
    output_rows = []
    nominal_bin_seconds = float(payload["parameters"]["bin_seconds"])
    for row in rows:
        camera_start = parse_datetime(row["camera_start_datetime"])
        camera_end = parse_datetime(row["camera_end_datetime"])
        bin_start = parse_datetime(row["bin_start_datetime"])
        bin_end = parse_datetime(row["bin_end_datetime"])
        observed_start = max(camera_start, bin_start)
        observed_end = min(camera_end, bin_end)
        midpoint = observed_start + (observed_end - observed_start) / 2
        clock_hour = midpoint.hour + midpoint.minute / 60 + midpoint.second / 3600 + midpoint.microsecond / 3.6e9
        camera_seconds = float(row["camera_seconds"])
        post_seconds = float(row["post_collection_camera_seconds"])
        foraging_seconds = float(row["foraging_seconds"])
        focal_visible_seconds = float(row["focal_visible_seconds"])
        displacement_events = int(row["displacement_events"])
        displacement_focal_to_others = int(row["displacement_focal_to_others"])
        displacement_others_to_focal = int(row["displacement_others_to_focal"])
        displacement_unspecified = int(row["displacement_unspecified"])
        if camera_seconds <= 0:
            raise ValueError(f"Non-positive camera exposure in {row['observation_id']} bin {row['bin_number']}")
        if foraging_seconds < -1e-9 or foraging_seconds > camera_seconds + 1e-6:
            raise ValueError(f"Invalid foraging duration in {row['observation_id']} bin {row['bin_number']}")
        if post_seconds < -1e-9 or post_seconds > camera_seconds + 1e-6:
            raise ValueError(f"Invalid post-collection exposure in {row['observation_id']} bin {row['bin_number']}")
        if displacement_events < 0:
            raise ValueError(f"Negative displacement count in {row['observation_id']} bin {row['bin_number']}")
        if displacement_events != (
            displacement_focal_to_others
            + displacement_others_to_focal
            + displacement_unspecified
        ):
            raise ValueError(f"Displacement directions do not reconcile in {row['observation_id']} bin {row['bin_number']}")

        observation_id = row["observation_id"]
        output_rows.append(
            {
                "observation_id": observation_id,
                "observation_date": row["observation_date"],
                "weekday": row["weekday"],
                "observer": row["observer"],
                "collection_day": int(row["collection_day"]),
                "bin_number": int(row["bin_number"]),
                "clock_hour": clock_hour,
                "camera_seconds": camera_seconds,
                "post_collection_camera_seconds": post_seconds,
                "post_collection_fraction": post_seconds / camera_seconds,
                "hours_from_collection_midpoint": (
                    "" if row["time_from_collection_midpoint_hours"] is None
                    else float(row["time_from_collection_midpoint_hours"])
                ),
                "collection_phase": row["collection_phase"],
                "foraging_seconds": foraging_seconds,
                "foraging_bouts": int(row["foraging_bouts"]),
                "focal_visible_seconds": focal_visible_seconds,
                "displacement_events": displacement_events,
                "displacement_focal_to_others": displacement_focal_to_others,
                "displacement_others_to_focal": displacement_others_to_focal,
                "displacement_unspecified": displacement_unspecified,
                "any_foraging": int(foraging_seconds > 0),
                "full_bin": int(abs(camera_seconds - nominal_bin_seconds) < 1e-6),
                "ar_start": int(observation_id != previous_observation),
                "exclude_n3": int(observation_id != "N3"),
            }
        )
        previous_observation = observation_id

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(output_rows)

    print(
        json.dumps(
            {
                "input": str(input_path),
                "output": str(output_path),
                "rows": len(output_rows),
                "observation_days": len({row["observation_id"] for row in output_rows}),
                "bin_seconds": nominal_bin_seconds,
                "camera_seconds": sum(row["camera_seconds"] for row in output_rows),
                "foraging_seconds": sum(row["foraging_seconds"] for row in output_rows),
                "displacement_events": sum(row["displacement_events"] for row in output_rows),
            },
            indent=2,
        )
    )


# --- Command-line entry point ---
if __name__ == "__main__":
    main()
