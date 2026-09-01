# ================================================================================================
# Script: leave_one_day_out_displacement.R
# Pipeline stage: 4. Agonistic displacement analysis
# Analytical purpose: Refit camera- and visibility-adjusted displacement models while omitting one
# observation day at a time.
# Inputs: .codex_work/issue4/displacement_data_30min.csv
# Outputs: .codex_work/issue4/model_output/displacement_leave_one_day_out.csv and
# displacement_leave_one_day_out_summary.csv
# Run-order position: 16
# Key scientific assumption: Sparse events can make individual omissions influential; this script
# makes that instability visible.
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
data$clock_hour <- as.numeric(data$clock_hour)
data$camera_offset <- log(data$segment_seconds / 1800)
data$visible_offset <- ifelse(data$focal_visible_seconds > 0, log(data$focal_visible_seconds / 1800), NA_real_)
day_ids <- unique(data$observation_id)

# --- Exposure-adjusted model specifications ---
camera_formula <- displacement_events ~ ns(clock_hour, df = 4) + collection_day +
  post_collection + offset(camera_offset) + s(observation_id, bs = "re")
visible_formula <- visible_displacement_events ~ ns(clock_hour, df = 4) + collection_day +
  post_collection + offset(visible_offset) + s(observation_id, bs = "re")

rows <- lapply(day_ids, function(excluded_day) {
  reduced_all <- data[data$observation_id != excluded_day, ]
  reduced_all$observation_id <- factor(reduced_all$observation_id)
  reduced_visible <- droplevels(reduced_all[reduced_all$focal_visible_seconds > 0, ])
  result <- data.frame(
    excluded_day = excluded_day,
    camera_rate_ratio = NA_real_,
    opportunity_adjusted_rate_ratio = NA_real_,
    camera_convergence = NA_character_,
    opportunity_convergence = NA_character_,
    error = NA_character_,
    stringsAsFactors = FALSE
  )
  tryCatch({
    camera_fit <- gam(camera_formula, data = reduced_all, family = nb(link = "log"), method = "REML")
    opportunity_fit <- gam(visible_formula, data = reduced_visible, family = nb(link = "log"), method = "REML")
    result$camera_rate_ratio <- exp(coef(camera_fit)["post_collection"])
    result$opportunity_adjusted_rate_ratio <- exp(coef(opportunity_fit)["post_collection"])
    result$camera_convergence <- as.character(camera_fit$outer.info$conv)
    result$opportunity_convergence <- as.character(opportunity_fit$outer.info$conv)
  }, error = function(error) {
    result$error <- conditionMessage(error)
  })
  result
})

results <- do.call(rbind, rows)
# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "displacement_leave_one_day_out.csv"), row.names = FALSE, na = "")
summary_rows <- data.frame(
  estimate = c("camera_rate_ratio", "opportunity_adjusted_rate_ratio"),
  successful_fits = c(sum(is.finite(results$camera_rate_ratio)), sum(is.finite(results$opportunity_adjusted_rate_ratio))),
  positive_fits = c(sum(results$camera_rate_ratio > 1, na.rm = TRUE), sum(results$opportunity_adjusted_rate_ratio > 1, na.rm = TRUE)),
  minimum = c(min(results$camera_rate_ratio, na.rm = TRUE), min(results$opportunity_adjusted_rate_ratio, na.rm = TRUE)),
  maximum = c(max(results$camera_rate_ratio, na.rm = TRUE), max(results$opportunity_adjusted_rate_ratio, na.rm = TRUE)),
  stringsAsFactors = FALSE
)
write.csv(summary_rows, file.path(output_dir, "displacement_leave_one_day_out_summary.csv"), row.names = FALSE)
print(summary_rows)
