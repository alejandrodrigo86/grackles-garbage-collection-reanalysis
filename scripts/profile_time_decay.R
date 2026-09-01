# ================================================================================================
# Script: profile_time_decay.R
# Pipeline stage: 5. Time-since-collection analysis
# Analytical purpose: Describe post-collection time windows and compare candidate structures for
# the duration of the collection-associated foraging response.
# Inputs: .codex_work/issue4/displacement_data_30min.csv
# Outputs: .codex_work/issue4/model_output/time_decay_profile.csv; time_decay_diagnostics.csv;
# collection_clock_times.csv
# Run-order position: 18
# Key scientific assumption: Time since collection is observational and partially confounded with
# clock time; this profile precedes the adjusted model.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
data <- read.csv(file.path(work_dir, "displacement_data_30min.csv"), stringsAsFactors = FALSE)
data <- data[order(data$observation_date, data$observation_id, data$bin_number, data$segment_number), ]

data$time_window <- ifelse(
  data$collection_day == 0,
  "Non-collection",
  ifelse(
    data$post_collection == 0,
    "Collection pre",
    as.character(cut(
      data$post_collection_hours,
      breaks = c(-Inf, 1, 3, 6, Inf),
      labels = c("Post 0-1 h", "Post 1-3 h", "Post 3-6 h", "Post >6 h"),
      right = FALSE
    ))
  )
)
window_order <- c(
  "Non-collection", "Collection pre", "Post 0-1 h", "Post 1-3 h",
  "Post 3-6 h", "Post >6 h"
)
profile <- do.call(rbind, lapply(window_order, function(window) {
  rows <- data[data$time_window == window, ]
  camera_hours <- sum(rows$segment_seconds) / 3600
  data.frame(
    window = window,
    rows = nrow(rows),
    observation_days = length(unique(rows$observation_id)),
    camera_hours = camera_hours,
    foraging_hours = sum(rows$foraging_seconds) / 3600,
    foraging_seconds_per_camera_hour = sum(rows$foraging_seconds) / camera_hours,
    zero_rows = sum(rows$foraging_seconds == 0),
    stringsAsFactors = FALSE
  )
}))

post <- data[data$collection_day == 1 & data$post_collection == 1, ]
collection_time_rows <- data.frame(
  observation_id = data$observation_id[data$collection_day == 1],
  collection_clock_hour = data$camera_clock_hour[data$collection_day == 1] -
    data$hours_from_collection_midpoint[data$collection_day == 1]
)
collection_times <- aggregate(
  collection_clock_hour ~ observation_id,
  data = collection_time_rows,
  FUN = mean
)
collection_times <- collection_times[order(collection_times$collection_clock_hour), ]

diagnostics <- data.frame(
  metric = c(
    "Post rows",
    "Post camera hours",
    "Post days",
    "Maximum post-collection hours",
    "Correlation: clock hour versus post hours",
    "Collection-time minimum hour",
    "Collection-time maximum hour",
    "Collection-time standard deviation"
  ),
  value = c(
    nrow(post),
    sum(post$segment_seconds) / 3600,
    length(unique(post$observation_id)),
    max(post$post_collection_hours),
    cor(post$camera_clock_hour, post$post_collection_hours),
    min(collection_times$collection_clock_hour),
    max(collection_times$collection_clock_hour),
    sd(collection_times$collection_clock_hour)
  ),
  stringsAsFactors = FALSE
)

# --- Export reproducible model tables ---
write.csv(profile, file.path(output_dir, "time_decay_profile.csv"), row.names = FALSE)
write.csv(diagnostics, file.path(output_dir, "time_decay_diagnostics.csv"), row.names = FALSE)
write.csv(collection_times, file.path(output_dir, "collection_clock_times.csv"), row.names = FALSE)
print(profile)
print(diagnostics)
print(collection_times)
