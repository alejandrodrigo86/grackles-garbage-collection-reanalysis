# ================================================================================================
# Script: leave_one_day_out.R
# Pipeline stage: 2. Primary analysis
# Analytical purpose: Refit the primary foraging model after omitting each observation day in turn
# to identify influential days and evaluate sign/magnitude stability.
# Inputs: .codex_work/issue4/model_data_30min.csv
# Outputs: .codex_work/issue4/model_output/primary_leave_one_day_out.csv and
# primary_leave_one_day_out_summary.csv
# Run-order position: 06
# Key scientific assumption: This is a sensitivity analysis; it does not create independent
# replications beyond the observed days.
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
data$exposure_offset <- log(as.numeric(data$camera_seconds) / 1800)

# --- Locked model specification ---
formula_locked <- foraging_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(exposure_offset) +
  s(observation_id, bs = "re")

ids <- levels(data$observation_id)
rows <- vector("list", length(ids))
for (index in seq_along(ids)) {
  held_out <- ids[index]
  sample_data <- droplevels(data[data$observation_id != held_out, ])
  model <- gam(
    formula_locked,
    data = sample_data,
    family = tw(link = "log"),
    method = "REML",
    na.action = na.fail
  )
  table <- summary(model)$p.table
  estimate <- unname(table["post_collection_fraction", 1])
  standard_error <- unname(table["post_collection_fraction", 2])
  rows[[index]] <- data.frame(
    omitted_observation_id = held_out,
    omitted_collection_day = unique(data$collection_day[data$observation_id == held_out]),
    estimate_log = estimate,
    standard_error = standard_error,
    rate_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = unname(table["post_collection_fraction", ncol(table)]),
    stringsAsFactors = FALSE
  )
}

results <- do.call(rbind, rows)
summary_table <- data.frame(
  metric = c(
    "Leave-one-day-out fits",
    "Minimum rate ratio",
    "Day omitted at minimum",
    "Maximum rate ratio",
    "Day omitted at maximum",
    "Fits with rate ratio above 1"
  ),
  value = c(
    nrow(results),
    min(results$rate_ratio),
    results$omitted_observation_id[which.min(results$rate_ratio)],
    max(results$rate_ratio),
    results$omitted_observation_id[which.max(results$rate_ratio)],
    sum(results$rate_ratio > 1)
  ),
  stringsAsFactors = FALSE
)

# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "primary_leave_one_day_out.csv"), row.names = FALSE, na = "")
write.csv(summary_table, file.path(output_dir, "primary_leave_one_day_out_summary.csv"), row.names = FALSE, na = "")
print(summary_table)
