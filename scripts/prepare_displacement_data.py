"""
Script: prepare_displacement_data.py
Pipeline stage: 4. Agonistic displacement analysis
Analytical purpose: Reconstruct directional displacement events and split intervals at
collection time so pre- and post-collection exposure is represented correctly.
Inputs: BORIS source files via extract_interval_data.py; observation-time metadata
Outputs: .codex_work/issue4/displacement_data_30min.csv; displacement_event_audit.csv;
displacement_profile_30min.json
Run-order position: 12
Key scientific assumption: Displacements are patch-level interactions among unbanded birds; they
cannot establish individual dominance ranks or a stable hierarchy.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

import csv
import json
import math
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

import extract_interval_data as source


# --- Project locations and reproducible configuration ---
ROOT = Path.cwd()
WORK_DIR = ROOT / ".codex_work" / "issue4"
BIN_SECONDS = int(os.environ.get("GRACKLES_BIN_SECONDS", "1800"))
OUTPUT_CSV = Path(os.environ.get("GRACKLES_DISPLACEMENT_OUTPUT", WORK_DIR / "displacement_data_30min.csv"))
EVENT_OUTPUT_CSV = Path(os.environ.get("GRACKLES_DISPLACEMENT_EVENTS", WORK_DIR / "displacement_event_audit.csv"))
PROFILE_OUTPUT = Path(os.environ.get("GRACKLES_DISPLACEMENT_PROFILE", WORK_DIR / "displacement_profile_30min.json"))


def point_in_intervals(event_time, intervals, tolerance=0.01):
    return any(start - tolerance <= event_time <= stop + tolerance for start, stop in intervals)


def clipped_intervals(intervals, window_start, window_stop):
    return [
        (max(start, window_start), min(stop, window_stop))
        for start, stop in intervals
        if min(stop, window_stop) > max(start, window_start)
    ]


def exposure_midpoint(intervals, window_start, window_stop):
    clips = clipped_intervals(intervals, window_start, window_stop)
    exposure = sum(stop - start for start, stop in clips)
    if exposure <= 0:
        return None
    return sum(((start + stop) / 2.0) * (stop - start) for start, stop in clips) / exposure


def direction(modifier):
    if modifier == "Displacement from focal to others":
        return "focal_to_others"
    if modifier == "Displacement from others to focal":
        return "others_to_focal"
    return "unspecified"


def write_csv(path, rows, fieldnames):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


# --- Execute the complete script workflow ---
def main():
    schedule = source.load_schedule()
    boris = json.loads(source.BORIS_PATH.read_text(encoding="utf-8"))
    segment_rows = []
    event_rows = []
    event_number = 0

    for observation_id, observation in boris["observations"].items():
        prefix = observation_id[0]
        number = source.observation_number(observation_id)
        schedule_row = schedule[(prefix, number)]
        study_date = schedule_row["date"]
        camera_start_clock = float(schedule_row["start_seconds"])
        media_duration = float(next(iter(observation["media_info"]["length"].values())))
        camera_end_clock = camera_start_clock + media_duration
        time_offset = float(observation.get("time offset", 0) or 0)

        state_intervals, _ = source.load_state_intervals(observation_id, time_offset, media_duration)
        at_site_union = source.union_intervals(state_intervals["At the observation site"])
        foraging_union = source.union_intervals(state_intervals["Searching for food"])
        focal_visible_union = source.union_intervals(at_site_union + foraging_union)

        displacement_events = []
        garbage_times = []
        for raw_event in observation["events"]:
            event_time = float(raw_event[0]) - time_offset if time_offset else float(raw_event[0])
            behavior = raw_event[2]
            modifier = raw_event[3]
            if behavior == "Garbage":
                garbage_times.append(event_time)
            elif behavior == "Displacement":
                displacement_events.append((event_time, modifier, direction(modifier)))

        collection_day = int(bool(garbage_times))
        collection_end_relative = garbage_times[0] if garbage_times else None

        for event_time, modifier, event_direction in displacement_events:
            event_number += 1
            event_rows.append(
                {
                    "event_id": event_number,
                    "observation_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "collection_day": collection_day,
                    "event_clock_hour": (camera_start_clock + event_time) / 3600.0,
                    "hours_from_collection": "" if collection_end_relative is None else (event_time - collection_end_relative) / 3600.0,
                    "post_collection": int(collection_end_relative is not None and event_time >= collection_end_relative),
                    "direction": event_direction,
                    "raw_modifier": modifier,
                    "inside_focal_visible": int(point_in_intervals(event_time, focal_visible_union)),
                    "inside_raw_at_site": int(point_in_intervals(event_time, at_site_union)),
                    "inside_foraging": int(point_in_intervals(event_time, foraging_union)),
                }
            )

        first_clock_bin = math.floor(camera_start_clock / BIN_SECONDS) * BIN_SECONDS
        final_clock_bin = math.ceil(camera_end_clock / BIN_SECONDS) * BIN_SECONDS
        bin_number = 0
        current_clock_start = first_clock_bin
        while current_clock_start < final_clock_bin:
            current_clock_stop = current_clock_start + BIN_SECONDS
            relative_start = max(0.0, current_clock_start - camera_start_clock)
            relative_stop = min(media_duration, current_clock_stop - camera_start_clock)
            if relative_stop <= relative_start:
                current_clock_start = current_clock_stop
                continue
            bin_number += 1

            boundaries = [relative_start, relative_stop]
            if (
                collection_end_relative is not None
                and relative_start < collection_end_relative < relative_stop
            ):
                boundaries.insert(1, collection_end_relative)

            for segment_number, (segment_start, segment_stop) in enumerate(zip(boundaries, boundaries[1:]), start=1):
                segment_midpoint = (segment_start + segment_stop) / 2.0
                post_collection = int(
                    collection_end_relative is not None and segment_start >= collection_end_relative
                )
                focal_visible_seconds = source.overlap_seconds(
                    focal_visible_union, segment_start, segment_stop
                )
                foraging_seconds = source.overlap_seconds(
                    foraging_union, segment_start, segment_stop
                )
                visible_midpoint = exposure_midpoint(
                    focal_visible_union, segment_start, segment_stop
                )
                segment_events = [
                    (event_time, modifier, event_direction)
                    for event_time, modifier, event_direction in displacement_events
                    if segment_start <= event_time < segment_stop
                    or (segment_stop == media_duration and event_time == segment_stop)
                ]
                visible_segment_events = [
                    event
                    for event in segment_events
                    if point_in_intervals(event[0], focal_visible_union)
                ]
                foraging_segment_events = [
                    event
                    for event in segment_events
                    if point_in_intervals(event[0], foraging_union)
                ]
                directions = Counter(event_direction for _, _, event_direction in segment_events)
                visible_directions = Counter(
                    event_direction for _, _, event_direction in visible_segment_events
                )
                segment_rows.append(
                    {
                        "observation_id": observation_id,
                        "observation_date": study_date.isoformat(),
                        "weekday": study_date.strftime("%A"),
                        "observer": schedule_row["observer"],
                        "collection_day": collection_day,
                        "post_collection": post_collection,
                        "bin_number": bin_number,
                        "segment_number": segment_number,
                        "clock_hour": (
                            (camera_start_clock + visible_midpoint) / 3600.0
                            if visible_midpoint is not None
                            else (camera_start_clock + (segment_start + segment_stop) / 2.0) / 3600.0
                        ),
                        "camera_clock_hour": (camera_start_clock + segment_midpoint) / 3600.0,
                        "hours_from_collection_midpoint": (
                            ""
                            if collection_end_relative is None
                            else (segment_midpoint - collection_end_relative) / 3600.0
                        ),
                        "post_collection_hours": (
                            max(0.0, (segment_midpoint - collection_end_relative) / 3600.0)
                            if collection_end_relative is not None and post_collection
                            else 0.0
                        ),
                        "segment_seconds": segment_stop - segment_start,
                        "focal_visible_seconds": focal_visible_seconds,
                        "foraging_seconds": foraging_seconds,
                        "displacement_events": len(segment_events),
                        "displacement_focal_to_others": directions["focal_to_others"],
                        "displacement_others_to_focal": directions["others_to_focal"],
                        "displacement_unspecified": directions["unspecified"],
                        "visible_displacement_events": len(visible_segment_events),
                        "visible_displacement_focal_to_others": visible_directions["focal_to_others"],
                        "visible_displacement_others_to_focal": visible_directions["others_to_focal"],
                        "visible_displacement_unspecified": visible_directions["unspecified"],
                        "foraging_displacement_events": len(foraging_segment_events),
                        "exclude_n3": int(observation_id != "N3"),
                    }
                )
            current_clock_start = current_clock_stop

    segment_rows.sort(
        key=lambda row: (
            row["observation_date"],
            row["observation_id"],
            row["bin_number"],
            row["segment_number"],
        )
    )
    event_rows.sort(key=lambda row: (row["observation_date"], row["event_clock_hour"], row["event_id"]))

    segment_fields = [
        "observation_id",
        "observation_date",
        "weekday",
        "observer",
        "collection_day",
        "post_collection",
        "bin_number",
        "segment_number",
        "clock_hour",
        "camera_clock_hour",
        "hours_from_collection_midpoint",
        "post_collection_hours",
        "segment_seconds",
        "focal_visible_seconds",
        "foraging_seconds",
        "displacement_events",
        "displacement_focal_to_others",
        "displacement_others_to_focal",
        "displacement_unspecified",
        "visible_displacement_events",
        "visible_displacement_focal_to_others",
        "visible_displacement_others_to_focal",
        "visible_displacement_unspecified",
        "foraging_displacement_events",
        "exclude_n3",
    ]
    event_fields = [
        "event_id",
        "observation_id",
        "observation_date",
        "collection_day",
        "event_clock_hour",
        "hours_from_collection",
        "post_collection",
        "direction",
        "raw_modifier",
        "inside_focal_visible",
        "inside_raw_at_site",
        "inside_foraging",
    ]
    write_csv(OUTPUT_CSV, segment_rows, segment_fields)
    if BIN_SECONDS == 1800:
        write_csv(EVENT_OUTPUT_CSV, event_rows, event_fields)

    visible_rows = [row for row in segment_rows if row["focal_visible_seconds"] > 0]
    collection_visible_rows = [row for row in visible_rows if row["collection_day"]]
    profile = {
        "bin_seconds": BIN_SECONDS,
        "segments_all": len(segment_rows),
        "segments_with_focal_visibility": len(visible_rows),
        "observation_days": len({row["observation_id"] for row in segment_rows}),
        "days_with_displacement": len({row["observation_id"] for row in segment_rows if row["displacement_events"] > 0}),
        "total_focal_visible_seconds": sum(row["focal_visible_seconds"] for row in visible_rows),
        "total_displacement_events": sum(row["displacement_events"] for row in segment_rows),
        "direction_counts": dict(Counter(row["direction"] for row in event_rows)),
        "events_inside_focal_visible": sum(row["inside_focal_visible"] for row in event_rows),
        "events_inside_raw_at_site": sum(row["inside_raw_at_site"] for row in event_rows),
        "events_inside_foraging": sum(row["inside_foraging"] for row in event_rows),
        "exposure_eligible_displacement_events": sum(
            row["visible_displacement_events"] for row in segment_rows
        ),
        "zero_visible_segments_with_events": sum(
            row["focal_visible_seconds"] <= 0 and row["displacement_events"] > 0
            for row in segment_rows
        ),
        "collection_day_pre": {
            "visible_seconds": sum(row["focal_visible_seconds"] for row in collection_visible_rows if not row["post_collection"]),
            "events": sum(row["visible_displacement_events"] for row in collection_visible_rows if not row["post_collection"]),
        },
        "collection_day_post": {
            "visible_seconds": sum(row["focal_visible_seconds"] for row in collection_visible_rows if row["post_collection"]),
            "events": sum(row["visible_displacement_events"] for row in collection_visible_rows if row["post_collection"]),
        },
        "noncollection": {
            "visible_seconds": sum(row["focal_visible_seconds"] for row in visible_rows if not row["collection_day"]),
            "events": sum(row["visible_displacement_events"] for row in visible_rows if not row["collection_day"]),
        },
    }
    for block in [profile["collection_day_pre"], profile["collection_day_post"], profile["noncollection"]]:
        block["events_per_visible_hour"] = block["events"] / (block["visible_seconds"] / 3600.0)

    PROFILE_OUTPUT.write_text(json.dumps(profile, indent=2), encoding="utf-8")
    print(json.dumps(profile, indent=2))


# --- Command-line entry point ---
if __name__ == "__main__":
    main()
