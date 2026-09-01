from __future__ import annotations

"""
Script: build_revision_audits.py
Pipeline stage: 6. Approved-revision audits
Analytical purpose: Create chronological Observation 1–25 labels; build the detailed observation
register; audit the 18 foraging intervals outside raw at-site states; reconstruct recorded
group-size states; and attach competitor exposure to displacement events.
Inputs: BORIS project, observation-time metadata, reconstructed interval data, and aggregated
event exports
Outputs: .codex_work/issue4/observation_register.csv; containment_event_audit.csv; direction and
group-size audit/model datasets; revision_audits.json
Run-order position: 23
Key scientific assumption: Public observation numbers are chronological recording labels, not
subjects or observers. Recorded group size is time-varying and the open-ended 9+ category is a
lower bound.
Provenance note: This annotated copy preserves the executed analytical statements. Only
explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
"""

"""Build transparent audit tables and exploratory group-size data.

This script never edits the original BORIS project or spreadsheet exports. It
adds chronological public-facing labels, lists the 18 foraging-state
containment discrepancies event by event, attaches dates/times to displacement
events, and reconstructs the recorded number of grackles as a piecewise-
constant state during focal-visible periods.

Group-size rule
---------------
The BORIS point codes ("One subject", "Two subjects", ..., "More subjects")
are interpreted as state updates: a value starts at its timestamp and remains
in force until the next update or the end of the current focal-visible episode.
Time before the first update in an episode is left unknown. "More subjects" is
stored as 9+ and represented numerically by the conservative lower bound 9.
"""

import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

from extract_interval_data import (
    AGG_ROOT,
    BORIS_PATH,
    ROOT,
    containment_audit,
    interval_length,
    iso_datetime,
    load_schedule,
    load_state_intervals,
    observation_number,
    overlap_seconds,
    subtract_covered_seconds,
    union_intervals,
)


WORK_DIR = ROOT / ".codex_work" / "issue4"
INTERVAL_PATH = WORK_DIR / "interval_data.json"
OUTPUT_JSON = WORK_DIR / "revision_audits.json"

SUBJECT_COUNTS = {
    "One subject": 1,
    "Two subjects": 2,
    "Three subjects": 3,
    "Four subjects": 4,
    "Five subjects": 5,
    "Six subjects": 6,
    "Seven subjects": 7,
    "Eight subjects": 8,
    "More subjects": 9,
}


def write_csv(name: str, rows: list[dict]) -> None:
    path = WORK_DIR / name
    if not rows:
        raise ValueError(f"No rows available for {name}")
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def subtract_intervals(target: tuple[float, float], covering: list[tuple[float, float]]):
    """Return portions of one target interval not covered by a union."""
    pieces = [target]
    for cover_start, cover_stop in union_intervals(covering):
        next_pieces = []
        for start, stop in pieces:
            if cover_stop <= start or cover_start >= stop:
                next_pieces.append((start, stop))
                continue
            if cover_start > start:
                next_pieces.append((start, min(stop, cover_start)))
            if cover_stop < stop:
                next_pieces.append((max(start, cover_stop), stop))
        pieces = next_pieces
    return [(start, stop) for start, stop in pieces if stop > start]


def split_at_boundaries(start: float, stop: float, boundaries: list[float]):
    points = [start] + sorted(point for point in boundaries if start < point < stop) + [stop]
    return list(zip(points, points[1:]))


def phase_for_segment(collection_day: bool, collection_end: float | None, start: float, stop: float):
    if not collection_day:
        return "No collection"
    midpoint = (start + stop) / 2
    return "Pre-collection" if midpoint < collection_end else "Post-collection"


def reconstruct_group_segments(
    visible: list[tuple[float, float]],
    subject_events: list[dict],
    collection_end: float | None,
):
    """Carry each count update to the next update within a visible episode."""
    segments = []
    for episode_number, (episode_start, episode_stop) in enumerate(visible, start=1):
        events = [
            event
            for event in subject_events
            if episode_start <= event["relative_seconds"] <= episode_stop
        ]
        events.sort(key=lambda event: (event["relative_seconds"], event["source_index"]))
        # If duplicate count annotations occur at one timestamp, retain the last
        # source event and flag the duplication in the QC table.
        by_time = {}
        for event in events:
            by_time[event["relative_seconds"]] = event
        events = [by_time[key] for key in sorted(by_time)]
        for index, event in enumerate(events):
            start = max(episode_start, event["relative_seconds"])
            stop = episode_stop if index + 1 == len(events) else min(
                episode_stop, events[index + 1]["relative_seconds"]
            )
            if stop <= start:
                continue
            boundaries = [collection_end] if collection_end is not None else []
            for part_start, part_stop in split_at_boundaries(start, stop, boundaries):
                segments.append(
                    {
                        "episode_number": episode_number,
                        "start_relative_seconds": part_start,
                        "stop_relative_seconds": part_stop,
                        "duration_seconds": part_stop - part_start,
                        "group_size_lower_bound": event["group_size_lower_bound"],
                        "group_size_label": event["group_size_label"],
                        "more_than_eight": event["more_than_eight"],
                    }
                )
    return segments


# --- Execute the complete script workflow ---
def main():
    payload = json.loads(INTERVAL_PATH.read_text(encoding="utf-8"))
    boris = json.loads(BORIS_PATH.read_text(encoding="utf-8"))
    schedule = load_schedule()

    days = sorted(payload["day_rows"], key=lambda row: (row["observation_date"], row["observation_id"]))
    observation_map = {
        row["observation_id"]: {
            "observation_number": index,
            "observation_label": f"Observation {index}",
            "observation_date": row["observation_date"],
        }
        for index, row in enumerate(days, start=1)
    }

    observation_register = []
    containment_rows = []
    direction_rows = []
    group_event_rows = []
    group_segment_rows = []
    group_interval_rows = []
    group_phase_interval_rows = []
    group_day_phase_rows = []
    group_qc_rows = []
    containment_interval_rows = []

    interval_by_id = defaultdict(list)
    for row in payload["interval_rows"]:
        interval_by_id[row["observation_id"]].append(row)

    for day in days:
        observation_id = day["observation_id"]
        mapping = observation_map[observation_id]
        observation = boris["observations"][observation_id]
        prefix = observation_id[0]
        schedule_row = schedule[(prefix, observation_number(observation_id))]
        study_date = schedule_row["date"]
        camera_start_clock = float(schedule_row["start_seconds"])
        media_duration = float(next(iter(observation["media_info"]["length"].values())))
        camera_end_clock = camera_start_clock + media_duration
        time_offset = float(observation.get("time offset", 0) or 0)

        state_intervals, _ = load_state_intervals(observation_id, time_offset, media_duration)
        at_site = sorted(state_intervals["At the observation site"])
        foraging = sorted(state_intervals["Searching for food"])
        at_site_union = union_intervals(at_site)
        foraging_union = union_intervals(foraging)
        visible = union_intervals(at_site + foraging)

        normalized_events = []
        subject_events = []
        garbage_times = []
        for source_index, raw_event in enumerate(observation["events"], start=1):
            relative = float(raw_event[0]) - time_offset if time_offset else float(raw_event[0])
            event = {
                "source_index": source_index,
                "relative_seconds": relative,
                "subject": raw_event[1],
                "behavior": raw_event[2],
                "modifier": raw_event[3],
            }
            normalized_events.append(event)
            if event["behavior"] == "Garbage":
                garbage_times.append(relative)
            if event["behavior"] in SUBJECT_COUNTS:
                event["group_size_lower_bound"] = SUBJECT_COUNTS[event["behavior"]]
                event["group_size_label"] = "9+" if event["behavior"] == "More subjects" else str(SUBJECT_COUNTS[event["behavior"]])
                event["more_than_eight"] = int(event["behavior"] == "More subjects")
                subject_events.append(event)

        collection_day = bool(garbage_times)
        collection_end = garbage_times[0] if collection_day else None
        collection_end_clock = camera_start_clock + collection_end if collection_day else None
        observation_register.append(
            {
                "observation_number": mapping["observation_number"],
                "observation_label": mapping["observation_label"],
                "original_recording_id": observation_id,
                "observation_date": study_date.isoformat(),
                "weekday": study_date.strftime("%A"),
                "observer": schedule_row["observer"],
                "camera_start_local": iso_datetime(study_date, camera_start_clock),
                "camera_end_local": iso_datetime(study_date, camera_end_clock),
                "camera_duration_hours": media_duration / 3600,
                "collection_day": int(collection_day),
                "collection_end_local": iso_datetime(study_date, collection_end_clock) if collection_day else "",
                "garbage_marker_count": len(garbage_times),
                "boris_time_offset_seconds": time_offset,
            }
        )

        failures = containment_audit(foraging, at_site)
        for failure_number, (start, stop) in enumerate(failures, start=1):
            uncovered = subtract_intervals((start, stop), at_site_union)
            uncovered_seconds = sum(part_stop - part_start for part_start, part_stop in uncovered)
            containment_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "event_number_within_observation": failure_number,
                    "foraging_start_local": iso_datetime(study_date, camera_start_clock + start),
                    "foraging_stop_local": iso_datetime(study_date, camera_start_clock + stop),
                    "foraging_duration_seconds": stop - start,
                    "seconds_covered_by_raw_at_site": overlap_seconds(at_site_union, start, stop),
                    "seconds_added_by_union_rule": uncovered_seconds,
                    "percent_outside_raw_at_site": 100 * uncovered_seconds / (stop - start) if stop > start else 0,
                    "uncovered_portions_local": "; ".join(
                        f"{iso_datetime(study_date, camera_start_clock + part_start)} to "
                        f"{iso_datetime(study_date, camera_start_clock + part_stop)}"
                        for part_start, part_stop in uncovered
                    ),
                    "decision": "Retain foraging; foraging itself confirms focal visibility",
                }
            )

        segments = reconstruct_group_segments(visible, subject_events, collection_end)

        for event in normalized_events:
            if event["behavior"] != "Displacement":
                continue
            modifier = event["modifier"]
            if modifier == "Displacement from focal to others":
                direction = "Focal displaced another grackle"
            elif modifier == "Displacement from others to focal":
                direction = "Another grackle displaced focal"
            else:
                direction = "Not direction-coded"
            phase = phase_for_segment(collection_day, collection_end, event["relative_seconds"], event["relative_seconds"])
            group_segment = next(
                (
                    segment for segment in segments
                    if segment["start_relative_seconds"] <= event["relative_seconds"] < segment["stop_relative_seconds"]
                ),
                None,
            )
            direction_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "event_time_local": iso_datetime(study_date, camera_start_clock + event["relative_seconds"]),
                    "collection_day": int(collection_day),
                    "collection_phase": phase,
                    "direction_category": direction,
                    "raw_modifier": modifier if modifier not in (None, "") else "Blank",
                    "recorded_group_size_label": group_segment["group_size_label"] if group_segment else "Unknown",
                    "recorded_group_size_lower_bound": group_segment["group_size_lower_bound"] if group_segment else "",
                    "focal_competitors_lower_bound": max(0, group_segment["group_size_lower_bound"] - 1) if group_segment else "",
                    "source_event_index": event["source_index"],
                }
            )

        for event_number, event in enumerate(subject_events, start=1):
            inside_visible = any(start <= event["relative_seconds"] <= stop for start, stop in visible)
            group_event_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "event_number_within_observation": event_number,
                    "event_time_local": iso_datetime(study_date, camera_start_clock + event["relative_seconds"]),
                    "relative_seconds": event["relative_seconds"],
                    "group_size_label": event["group_size_label"],
                    "group_size_lower_bound": event["group_size_lower_bound"],
                    "more_than_eight": event["more_than_eight"],
                    "inside_focal_visible_state": int(inside_visible),
                    "source_event_index": event["source_index"],
                }
            )

        for segment_number, segment in enumerate(segments, start=1):
            phase = phase_for_segment(
                collection_day,
                collection_end,
                segment["start_relative_seconds"],
                segment["stop_relative_seconds"],
            )
            group_segment_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "segment_number": segment_number,
                    "episode_number": segment["episode_number"],
                    "segment_start_local": iso_datetime(study_date, camera_start_clock + segment["start_relative_seconds"]),
                    "segment_stop_local": iso_datetime(study_date, camera_start_clock + segment["stop_relative_seconds"]),
                    "duration_seconds": segment["duration_seconds"],
                    "collection_day": int(collection_day),
                    "collection_phase": phase,
                    "group_size_label": segment["group_size_label"],
                    "group_size_lower_bound": segment["group_size_lower_bound"],
                    "more_than_eight": segment["more_than_eight"],
                }
            )

        known_seconds = sum(segment["duration_seconds"] for segment in segments)
        visible_seconds = interval_length(visible)
        duplicate_event_times = sum(
            count - 1 for count in Counter(event["relative_seconds"] for event in subject_events).values() if count > 1
        )
        group_qc_rows.append(
            {
                "observation_number": mapping["observation_number"],
                "observation_label": mapping["observation_label"],
                "original_recording_id": observation_id,
                "observation_date": study_date.isoformat(),
                "subject_count_updates": len(subject_events),
                "updates_inside_focal_visible": sum(
                    any(start <= event["relative_seconds"] <= stop for start, stop in visible)
                    for event in subject_events
                ),
                "more_than_eight_updates": sum(event["more_than_eight"] for event in subject_events),
                "duplicate_update_timestamps": duplicate_event_times,
                "focal_visible_seconds": visible_seconds,
                "group_size_known_seconds": known_seconds,
                "known_coverage_percent": 100 * known_seconds / visible_seconds if visible_seconds else 0,
                "reconstruction_rule": "Carry update to next update or visible-episode end; pre-first-update time unknown",
            }
        )

        # Integrate the reconstructed state into the same clock-aligned intervals
        # used by the main analyses.
        for interval in sorted(interval_by_id[observation_id], key=lambda row: row["bin_number"]):
            bin_start_clock = datetime.fromisoformat(interval["bin_start_datetime"])
            bin_stop_clock = datetime.fromisoformat(interval["bin_end_datetime"])
            camera_start_dt = datetime.fromisoformat(interval["camera_start_datetime"])
            relative_start = max(0.0, (bin_start_clock - camera_start_dt).total_seconds())
            relative_stop = min(media_duration, (bin_stop_clock - camera_start_dt).total_seconds())
            known = 0.0
            person_seconds = 0.0
            multi_seconds = 0.0
            focal_competitor_seconds = 0.0
            group_size_9plus_seconds = 0.0
            max_group_size = None
            for segment in segments:
                seconds = max(
                    0.0,
                    min(relative_stop, segment["stop_relative_seconds"])
                    - max(relative_start, segment["start_relative_seconds"]),
                )
                if seconds <= 0:
                    continue
                known += seconds
                person_seconds += seconds * segment["group_size_lower_bound"]
                focal_competitor_seconds += seconds * max(0, segment["group_size_lower_bound"] - 1)
                if segment["group_size_lower_bound"] > 1:
                    multi_seconds += seconds
                if segment["more_than_eight"]:
                    group_size_9plus_seconds += seconds
                max_group_size = segment["group_size_lower_bound"] if max_group_size is None else max(
                    max_group_size, segment["group_size_lower_bound"]
                )

            observed_start = max(
                datetime.fromisoformat(interval["camera_start_datetime"]),
                datetime.fromisoformat(interval["bin_start_datetime"]),
            )
            observed_stop = min(
                datetime.fromisoformat(interval["camera_end_datetime"]),
                datetime.fromisoformat(interval["bin_end_datetime"]),
            )
            midpoint = observed_start + (observed_stop - observed_start) / 2
            displacement_events_in_bin = [
                event for event in normalized_events
                if event["behavior"] == "Displacement"
                and relative_start <= event["relative_seconds"] < relative_stop
            ]
            displacement_events_with_known_group = 0
            displacement_events_with_competitor = 0
            for event in displacement_events_in_bin:
                event_segment = next(
                    (
                        segment for segment in segments
                        if segment["start_relative_seconds"] <= event["relative_seconds"] < segment["stop_relative_seconds"]
                    ),
                    None,
                )
                if event_segment is not None:
                    displacement_events_with_known_group += 1
                    if event_segment["group_size_lower_bound"] > 1:
                        displacement_events_with_competitor += 1
            group_interval_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "observer": schedule_row["observer"],
                    "collection_day": int(collection_day),
                    "bin_number": interval["bin_number"],
                    "bin_start_local": interval["bin_start_datetime"],
                    "bin_stop_local": interval["bin_end_datetime"],
                    "clock_hour": midpoint.hour + midpoint.minute / 60 + midpoint.second / 3600,
                    "camera_seconds": interval["camera_seconds"],
                    "post_collection_fraction": (
                        interval["post_collection_camera_seconds"] / interval["camera_seconds"]
                        if interval["camera_seconds"] else 0
                    ),
                    "hours_from_collection_midpoint": (
                        "" if interval["time_from_collection_midpoint_hours"] is None
                        else interval["time_from_collection_midpoint_hours"]
                    ),
                    "collection_phase": interval["collection_phase"],
                    "focal_visible_seconds": interval["focal_visible_seconds"],
                    "group_size_known_seconds": known,
                    "group_size_person_seconds": person_seconds,
                    "time_weighted_mean_group_size": person_seconds / known if known > 0 else "",
                    "multiple_grackle_seconds": multi_seconds,
                    "multiple_grackle_fraction": multi_seconds / known if known > 0 else "",
                    "focal_competitor_seconds_lower_bound": focal_competitor_seconds,
                    "group_size_9plus_seconds": group_size_9plus_seconds,
                    "displacement_events_all": len(displacement_events_in_bin),
                    "displacement_events_with_known_group": displacement_events_with_known_group,
                    "displacement_events_with_recorded_competitor": displacement_events_with_competitor,
                    "maximum_group_size_lower_bound": max_group_size if max_group_size is not None else "",
                }
            )

            # Exact pre/post segments for group-size and competitor-adjusted
            # displacement models. A clock-aligned bin that crosses collection
            # end is split at the marker rather than represented by a fraction.
            phase_boundaries = [collection_end] if collection_day and collection_end is not None else []
            for phase_segment_number, (part_start, part_stop) in enumerate(
                split_at_boundaries(relative_start, relative_stop, phase_boundaries), start=1
            ):
                part_known = 0.0
                part_person_seconds = 0.0
                part_multi_seconds = 0.0
                part_competitor_seconds = 0.0
                part_9plus_seconds = 0.0
                part_max = None
                for segment in segments:
                    seconds = max(
                        0.0,
                        min(part_stop, segment["stop_relative_seconds"])
                        - max(part_start, segment["start_relative_seconds"]),
                    )
                    if seconds <= 0:
                        continue
                    size = segment["group_size_lower_bound"]
                    part_known += seconds
                    part_person_seconds += seconds * size
                    part_multi_seconds += seconds if size > 1 else 0.0
                    part_competitor_seconds += seconds * max(0, size - 1)
                    if segment["more_than_eight"]:
                        part_9plus_seconds += seconds
                    part_max = size if part_max is None else max(part_max, size)

                part_displacement_events = [
                    event for event in normalized_events
                    if event["behavior"] == "Displacement"
                    and part_start <= event["relative_seconds"] < part_stop
                ]
                known_displacement_events = 0
                recorded_competitor_events = 0
                for event in part_displacement_events:
                    event_segment = next(
                        (
                            segment for segment in segments
                            if segment["start_relative_seconds"] <= event["relative_seconds"] < segment["stop_relative_seconds"]
                        ),
                        None,
                    )
                    if event_segment is not None:
                        known_displacement_events += 1
                        recorded_competitor_events += int(event_segment["group_size_lower_bound"] > 1)

                part_midpoint_clock = camera_start_clock + (part_start + part_stop) / 2
                part_phase = phase_for_segment(collection_day, collection_end, part_start, part_stop)
                group_phase_interval_rows.append(
                    {
                        "observation_number": mapping["observation_number"],
                        "observation_label": mapping["observation_label"],
                        "original_recording_id": observation_id,
                        "observation_date": study_date.isoformat(),
                        "observer": schedule_row["observer"],
                        "collection_day": int(collection_day),
                        "bin_number": interval["bin_number"],
                        "phase_segment_number": phase_segment_number,
                        "segment_start_local": iso_datetime(study_date, camera_start_clock + part_start),
                        "segment_stop_local": iso_datetime(study_date, camera_start_clock + part_stop),
                        "clock_hour": part_midpoint_clock / 3600,
                        "segment_camera_seconds": part_stop - part_start,
                        "post_collection": int(collection_day and collection_end is not None and part_start >= collection_end),
                        "collection_phase": part_phase,
                        "group_size_known_seconds": part_known,
                        "group_size_person_seconds": part_person_seconds,
                        "time_weighted_mean_group_size": part_person_seconds / part_known if part_known > 0 else "",
                        "multiple_grackle_seconds": part_multi_seconds,
                        "multiple_grackle_fraction": part_multi_seconds / part_known if part_known > 0 else "",
                        "focal_competitor_seconds_lower_bound": part_competitor_seconds,
                        "group_size_9plus_seconds": part_9plus_seconds,
                        "displacement_events_all": len(part_displacement_events),
                        "displacement_events_with_known_group": known_displacement_events,
                        "displacement_events_with_recorded_competitor": recorded_competitor_events,
                        "maximum_group_size_lower_bound": part_max if part_max is not None else "",
                    }
                )

            # Strict raw-at-site sensitivity for the mechanism decomposition.
            raw_at_site_seconds = overlap_seconds(at_site_union, relative_start, relative_stop)
            foraging_within_at_site = sum(
                overlap_seconds(at_site_union, max(relative_start, start), min(relative_stop, stop))
                for start, stop in foraging_union
                if min(relative_stop, stop) > max(relative_start, start)
            )
            containment_interval_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "observer": schedule_row["observer"],
                    "collection_day": int(collection_day),
                    "bin_number": interval["bin_number"],
                    "clock_hour": midpoint.hour + midpoint.minute / 60 + midpoint.second / 3600,
                    "camera_seconds": interval["camera_seconds"],
                    "post_collection_fraction": (
                        interval["post_collection_camera_seconds"] / interval["camera_seconds"]
                        if interval["camera_seconds"] else 0
                    ),
                    "raw_at_site_seconds": raw_at_site_seconds,
                    "foraging_within_raw_at_site_seconds": min(raw_at_site_seconds, foraging_within_at_site),
                    "focal_visible_union_seconds": interval["focal_visible_seconds"],
                    "all_foraging_seconds": interval["foraging_seconds"],
                }
            )

        # Day-phase summaries are descriptive and exposure-weighted.
        for phase in ["No collection", "Pre-collection", "Post-collection"]:
            phase_segments = [
                segment for segment in segments
                if phase_for_segment(
                    collection_day,
                    collection_end,
                    segment["start_relative_seconds"],
                    segment["stop_relative_seconds"],
                ) == phase
            ]
            if not phase_segments:
                continue
            seconds = sum(segment["duration_seconds"] for segment in phase_segments)
            person_seconds = sum(
                segment["duration_seconds"] * segment["group_size_lower_bound"] for segment in phase_segments
            )
            multi_seconds = sum(
                segment["duration_seconds"] for segment in phase_segments if segment["group_size_lower_bound"] > 1
            )
            group_day_phase_rows.append(
                {
                    "observation_number": mapping["observation_number"],
                    "observation_label": mapping["observation_label"],
                    "original_recording_id": observation_id,
                    "observation_date": study_date.isoformat(),
                    "collection_day": int(collection_day),
                    "collection_phase": phase,
                    "group_size_known_hours": seconds / 3600,
                    "time_weighted_mean_group_size": person_seconds / seconds,
                    "multiple_grackle_percent": 100 * multi_seconds / seconds,
                    "maximum_group_size_lower_bound": max(segment["group_size_lower_bound"] for segment in phase_segments),
                }
            )

    # Append the chronological labels to the existing interval and day tables in
    # the JSON output without changing the audited original identifier.
    for collection in (payload["day_rows"], payload["qc_rows"], payload["interval_rows"]):
        for row in collection:
            row.update(observation_map[row["observation_id"]])

    direction_summary = Counter(row["direction_category"] for row in direction_rows)
    qc_total_visible = sum(row["focal_visible_seconds"] for row in group_qc_rows)
    qc_total_known = sum(row["group_size_known_seconds"] for row in group_qc_rows)
    summary = {
        "observation_days": len(observation_register),
        "containment_discrepancies": len(containment_rows),
        "containment_added_visible_seconds": sum(row["seconds_added_by_union_rule"] for row in containment_rows),
        "displacement_events": len(direction_rows),
        "displacement_direction_counts": dict(direction_summary),
        "subject_count_updates": len(group_event_rows),
        "subject_count_updates_inside_visible": sum(row["inside_focal_visible_state"] for row in group_event_rows),
        "more_than_eight_updates": sum(row["more_than_eight"] for row in group_event_rows),
        "group_size_known_hours": qc_total_known / 3600,
        "focal_visible_hours": qc_total_visible / 3600,
        "group_size_state_coverage_percent": 100 * qc_total_known / qc_total_visible,
    }

    result = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "group_size_rule": (
            "Each subject-count annotation is carried forward until the next annotation or the end of the current "
            "focal-visible episode. Time before the first update is unknown. 'More subjects' is represented as 9+, "
            "with 9 used as a conservative numerical lower bound."
        ),
        "observation_map": observation_map,
        "summary": summary,
        "observation_register": observation_register,
        "containment_audit": containment_rows,
        "direction_audit": direction_rows,
        "group_size_events": group_event_rows,
        "group_size_segments": group_segment_rows,
        "group_size_intervals": group_interval_rows,
        "group_size_phase_intervals": group_phase_interval_rows,
        "group_size_day_phase": group_day_phase_rows,
        "group_size_qc": group_qc_rows,
        "containment_sensitivity_intervals": containment_interval_rows,
        "labeled_interval_data": payload,
    }
    OUTPUT_JSON.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

    write_csv("observation_register.csv", observation_register)
    write_csv("containment_event_audit.csv", containment_rows)
    write_csv("displacement_direction_audit_labeled.csv", direction_rows)
    write_csv("group_size_event_audit.csv", group_event_rows)
    write_csv("group_size_segments.csv", group_segment_rows)
    write_csv("group_size_model_data_30min.csv", group_interval_rows)
    write_csv("group_size_phase_model_data_30min.csv", group_phase_interval_rows)
    write_csv("group_size_day_phase_summary.csv", group_day_phase_rows)
    write_csv("group_size_qc.csv", group_qc_rows)
    write_csv("containment_sensitivity_data_30min.csv", containment_interval_rows)
    print(json.dumps(summary, indent=2))


# --- Command-line entry point ---
if __name__ == "__main__":
    main()
