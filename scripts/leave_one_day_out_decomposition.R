# ================================================================================================
# Script: leave_one_day_out_decomposition.R
# Pipeline stage: 3. Attendance/intensity decomposition
# Analytical purpose: Assess whether attendance and conditional-intensity conclusions depend on
# any single observation day.
# Inputs: .codex_work/issue4/model_data_30min.csv
# Outputs: .codex_work/issue4/model_output/decomposition_leave_one_day_out.csv and
# decomposition_leave_one_day_out_summary.csv
# Run-order position: 10
# Key scientific assumption: The analysis is diagnostic and should be interpreted alongside, not
# instead of, uncertainty intervals.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
data <- read.csv(file.path(work_dir, "model_data_30min.csv"), stringsAsFactors = FALSE)
data$observation_id <- factor(data$observation_id)
data$collection_day <- as.numeric(data$collection_day)
data$post_collection_fraction <- as.numeric(data$post_collection_fraction)
data$camera_offset <- log(as.numeric(data$camera_seconds) / 1800)

# --- Mechanism-specific model specifications ---
attendance_formula <- focal_visible_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(camera_offset) +
  s(observation_id, bs = "re")
intensity_formula <- foraging_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(visible_offset) +
  s(observation_id, bs = "re")

ids <- levels(data$observation_id)
rows <- vector("list", length(ids))
for (index in seq_along(ids)) {
  omitted <- ids[index]
  sample_data <- droplevels(data[data$observation_id != omitted, ])
  intensity_data <- droplevels(sample_data[sample_data$focal_visible_seconds > 0, ])
  intensity_data$visible_offset <- log(intensity_data$focal_visible_seconds / 1800)
  attendance <- gam(
    attendance_formula, data = sample_data, family = tw(link = "log"),
    method = "REML", na.action = na.fail
  )
  intensity <- gam(
    intensity_formula, data = intensity_data, family = tw(link = "log"),
    method = "REML", na.action = na.fail
  )
  attendance_log <- unname(summary(attendance)$p.table["post_collection_fraction", 1])
  intensity_log <- unname(summary(intensity)$p.table["post_collection_fraction", 1])
  rows[[index]] <- data.frame(
    omitted_observation_id = omitted,
    omitted_collection_day = unique(data$collection_day[data$observation_id == omitted]),
    attendance_ratio = exp(attendance_log),
    intensity_ratio = exp(intensity_log),
    product_ratio = exp(attendance_log + intensity_log),
    stringsAsFactors = FALSE
  )
}

results <- do.call(rbind, rows)
summarize_mechanism <- function(values, mechanism) {
  data.frame(
    mechanism = mechanism,
    fits = length(values),
    minimum_ratio = min(values),
    omitted_at_minimum = results$omitted_observation_id[which.min(values)],
    maximum_ratio = max(values),
    omitted_at_maximum = results$omitted_observation_id[which.max(values)],
    fits_above_one = sum(values > 1),
    stringsAsFactors = FALSE
  )
}

summary_table <- rbind(
  summarize_mechanism(results$attendance_ratio, "Patch attendance"),
  summarize_mechanism(results$intensity_ratio, "Conditional foraging intensity"),
  summarize_mechanism(results$product_ratio, "Attendance × intensity")
)

# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "decomposition_leave_one_day_out.csv"), row.names = FALSE, na = "")
write.csv(summary_table, file.path(output_dir, "decomposition_leave_one_day_out_summary.csv"), row.names = FALSE, na = "")
print(summary_table)
