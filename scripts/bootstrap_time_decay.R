# ================================================================================================
# Script: bootstrap_time_decay.R
# Pipeline stage: 5. Time-since-collection analysis
# Analytical purpose: Run chunkable day-cluster bootstrap replicates for the time-since-collection
# model.
# Inputs: .codex_work/issue4/displacement_data_30min.csv; optional GRACKLES_BOOT_* environment
# variables
# Outputs: .codex_work/issue4/model_output/time_decay_bootstrap_<start>.csv
# Run-order position: 20
# Key scientific assumption: The resampling unit is the observation day, preserving dependence
# among intervals recorded on the same day.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(splines))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
start_index <- as.integer(Sys.getenv("GRACKLES_BOOT_START", "1"))
n_replicates <- as.integer(Sys.getenv("GRACKLES_BOOT_N", "100"))
seed <- as.integer(Sys.getenv("GRACKLES_BOOT_SEED", "20260731"))
output_file <- Sys.getenv(
  "GRACKLES_BOOT_OUTPUT",
  file.path(output_dir, paste0("time_decay_bootstrap_", start_index, ".csv"))
)

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

fit_one <- function(bootstrap_index) {
  set.seed(seed + bootstrap_index)
  sampled_days <- sample(day_ids, length(day_ids), replace = TRUE)
  pieces <- lapply(seq_along(sampled_days), function(copy_index) {
    piece <- data[data$observation_id == sampled_days[copy_index], ]
    piece$observation_id <- paste0(sampled_days[copy_index], "__", copy_index)
    piece
  })
  boot <- do.call(rbind, pieces)
  boot$observation_id <- factor(boot$observation_id)
  result <- data.frame(
    replicate = bootstrap_index,
    hourly_rate_ratio = NA_real_,
    immediate_rate_ratio = NA_real_,
    convergence = NA_character_,
    error = NA_character_,
    stringsAsFactors = FALSE
  )
  tryCatch({
    fit <- gam(
      formula,
      data = boot,
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
}

indices <- seq.int(start_index, length.out = n_replicates)
results <- do.call(rbind, lapply(indices, fit_one))
# --- Export reproducible model tables ---
write.csv(results, output_file, row.names = FALSE, na = "")
print(data.frame(
  start = start_index,
  n = n_replicates,
  complete = sum(is.finite(results$hourly_rate_ratio)),
  hourly_median = median(results$hourly_rate_ratio, na.rm = TRUE)
))
