# ================================================================================================
# Script: bootstrap_displacement.R
# Pipeline stage: 4. Agonistic displacement analysis
# Analytical purpose: Run chunkable day-cluster bootstrap replicates for displacement models.
# Inputs: .codex_work/issue4/displacement_data_30min.csv; optional GRACKLES_BOOT_* environment
# variables
# Outputs: .codex_work/issue4/model_output/displacement_bootstrap_<start>.csv
# Run-order position: 15
# Key scientific assumption: The cluster is the observation day. Chunk controls support
# reproducible parallel or resumed execution.
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
  file.path(output_dir, paste0("displacement_bootstrap_", start_index, ".csv"))
)

data <- read.csv(file.path(work_dir, "displacement_data_30min.csv"), stringsAsFactors = FALSE)
data <- data[order(data$observation_date, data$observation_id, data$bin_number, data$segment_number), ]
data$collection_day <- as.numeric(data$collection_day)
data$post_collection <- as.numeric(data$post_collection)
data$clock_hour <- as.numeric(data$clock_hour)
data$camera_offset <- log(data$segment_seconds / 1800)
data$visible_offset <- ifelse(
  data$focal_visible_seconds > 0,
  log(data$focal_visible_seconds / 1800),
  NA_real_
)
day_ids <- unique(data$observation_id)

# --- Exposure-adjusted model specifications ---
camera_formula <- displacement_events ~ ns(clock_hour, df = 4) + collection_day +
  post_collection + offset(camera_offset) + s(observation_id, bs = "re")
visible_formula <- visible_displacement_events ~ ns(clock_hour, df = 4) + collection_day +
  post_collection + offset(visible_offset) + s(observation_id, bs = "re")

fit_one <- function(bootstrap_index) {
  set.seed(seed + bootstrap_index)
  sampled_days <- sample(day_ids, length(day_ids), replace = TRUE)
  pieces <- lapply(seq_along(sampled_days), function(copy_index) {
    piece <- data[data$observation_id == sampled_days[copy_index], ]
    piece$observation_id <- paste0(sampled_days[copy_index], "__", copy_index)
    piece
  })
  boot_all <- do.call(rbind, pieces)
  boot_all$observation_id <- factor(boot_all$observation_id)
  boot_visible <- droplevels(boot_all[boot_all$focal_visible_seconds > 0, ])

  result <- data.frame(
    replicate = bootstrap_index,
    camera_rate_ratio = NA_real_,
    opportunity_adjusted_rate_ratio = NA_real_,
    camera_convergence = NA_character_,
    opportunity_convergence = NA_character_,
    error = NA_character_,
    stringsAsFactors = FALSE
  )
  tryCatch({
    camera_fit <- gam(
      camera_formula,
      data = boot_all,
      family = nb(link = "log"),
      method = "REML",
      na.action = na.fail
    )
    opportunity_fit <- gam(
      visible_formula,
      data = boot_visible,
      family = nb(link = "log"),
      method = "REML",
      na.action = na.fail
    )
    result$camera_rate_ratio <- exp(coef(camera_fit)["post_collection"])
    result$opportunity_adjusted_rate_ratio <- exp(coef(opportunity_fit)["post_collection"])
    result$camera_convergence <- as.character(camera_fit$outer.info$conv)
    result$opportunity_convergence <- as.character(opportunity_fit$outer.info$conv)
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
  complete = sum(is.finite(results$opportunity_adjusted_rate_ratio)),
  opportunity_median = median(results$opportunity_adjusted_rate_ratio, na.rm = TRUE)
))
