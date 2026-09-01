# ================================================================================================
# Script: leave_one_day_out_time_decay.R
# Pipeline stage: 5. Time-since-collection analysis
# Analytical purpose: Evaluate sensitivity of the estimated post-collection trajectory to omission
# of each observation day.
# Inputs: .codex_work/issue4/displacement_data_30min.csv
# Outputs: .codex_work/issue4/model_output/time_decay_leave_one_day_out.csv and
# time_decay_leave_one_day_out_summary.csv
# Run-order position: 21
# Key scientific assumption: The diagnostic tests stability to single-day influence but cannot
# resolve unmeasured food availability or disturbance.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(splines))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
data <- read.csv(file.path(work_dir, "displacement_data_30min.csv"), stringsAsFactors = FALSE)
data <- data[order(data$observation_date, data$observation_id, data$bin_number, data$segment_number), ]
data$collection_day <- as.numeric(data$collection_day)
data$post_collection <- as.numeric(data$post_collection)
data$camera_clock_hour <- as.numeric(data$camera_clock_hour)
data$post_collection_hours <- as.numeric(data$post_collection_hours)
data$camera_offset <- log(data$segment_seconds / 1800)
day_ids <- unique(data$observation_id)

formula <- foraging_seconds ~ ns(camera_clock_hour, df = 4) + collection_day +
  post_collection + post_collection_hours + offset(camera_offset) +
  s(observation_id, bs = "re")

rows <- lapply(day_ids, function(excluded_day) {
  reduced <- data[data$observation_id != excluded_day, ]
  reduced$observation_id <- factor(reduced$observation_id)
  result <- data.frame(
    excluded_day = excluded_day,
    excluded_collection_day = unique(data$collection_day[data$observation_id == excluded_day]),
    hourly_rate_ratio = NA_real_,
    immediate_rate_ratio = NA_real_,
    convergence = NA_character_,
    error = NA_character_,
    stringsAsFactors = FALSE
  )
  tryCatch({
    fit <- gam(
      formula,
      data = reduced,
      family = tw(link = "log"),
      method = "REML",
      na.action = na.fail
    )
    result$hourly_rate_ratio <- exp(coef(fit)["post_collection_hours"])
    result$immediate_rate_ratio <- exp(coef(fit)["post_collection"])
    result$convergence <- as.character(fit$outer.info$conv)
  }, error = function(error) {
    result$error <- conditionMessage(error)
  })
  result
})

results <- do.call(rbind, rows)
# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "time_decay_leave_one_day_out.csv"), row.names = FALSE, na = "")
summary_rows <- data.frame(
  subset = c("All excluded days", "Collection days excluded", "Non-collection days excluded"),
  successful_fits = c(
    sum(is.finite(results$hourly_rate_ratio)),
    sum(is.finite(results$hourly_rate_ratio[results$excluded_collection_day == 1])),
    sum(is.finite(results$hourly_rate_ratio[results$excluded_collection_day == 0]))
  ),
  declining_fits = c(
    sum(results$hourly_rate_ratio < 1, na.rm = TRUE),
    sum(results$hourly_rate_ratio[results$excluded_collection_day == 1] < 1, na.rm = TRUE),
    sum(results$hourly_rate_ratio[results$excluded_collection_day == 0] < 1, na.rm = TRUE)
  ),
  minimum = c(
    min(results$hourly_rate_ratio, na.rm = TRUE),
    min(results$hourly_rate_ratio[results$excluded_collection_day == 1], na.rm = TRUE),
    min(results$hourly_rate_ratio[results$excluded_collection_day == 0], na.rm = TRUE)
  ),
  maximum = c(
    max(results$hourly_rate_ratio, na.rm = TRUE),
    max(results$hourly_rate_ratio[results$excluded_collection_day == 1], na.rm = TRUE),
    max(results$hourly_rate_ratio[results$excluded_collection_day == 0], na.rm = TRUE)
  ),
  stringsAsFactors = FALSE
)
write.csv(summary_rows, file.path(output_dir, "time_decay_leave_one_day_out_summary.csv"), row.names = FALSE)
print(summary_rows)
