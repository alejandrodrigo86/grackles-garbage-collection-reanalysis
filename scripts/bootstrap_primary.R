# ================================================================================================
# Script: bootstrap_primary.R
# Pipeline stage: 2. Primary analysis
# Analytical purpose: Perform a day-cluster bootstrap for the primary foraging model and summarize
# the collection-day and post-collection effect estimates.
# Inputs: .codex_work/issue4/model_data_30min.csv
# Outputs: .codex_work/issue4/model_output/primary_day_bootstrap_replicates.csv and
# primary_day_bootstrap_summary.csv
# Run-order position: 05
# Key scientific assumption: Whole observation days, rather than individual intervals, are
# resampled to preserve within-day dependence.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(parallel))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
data <- read.csv(file.path(work_dir, "model_data_30min.csv"), stringsAsFactors = FALSE)
data$observation_id <- factor(data$observation_id)
data$collection_day <- as.numeric(data$collection_day)
data$post_collection_fraction <- as.numeric(data$post_collection_fraction)
data$clock_hour <- as.numeric(data$clock_hour)
data$camera_seconds <- as.numeric(data$camera_seconds)
data$foraging_seconds <- as.numeric(data$foraging_seconds)
data$exposure_offset <- log(data$camera_seconds / 1800)

# --- Locked model specification ---
formula_locked <- foraging_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(exposure_offset) +
  s(observation_id, bs = "re")

collection_ids <- unique(as.character(data$observation_id[data$collection_day == 1]))
noncollection_ids <- unique(as.character(data$observation_id[data$collection_day == 0]))

bootstrap_once <- function(seed) {
  set.seed(seed)
  sampled <- c(
    sample(collection_ids, length(collection_ids), replace = TRUE),
    sample(noncollection_ids, length(noncollection_ids), replace = TRUE)
  )
  pieces <- vector("list", length(sampled))
  for (index in seq_along(sampled)) {
    piece <- data[as.character(data$observation_id) == sampled[index], , drop = FALSE]
    piece$observation_id <- paste0("bootstrap_day_", sprintf("%02d", index))
    pieces[[index]] <- piece
  }
  sample_data <- do.call(rbind, pieces)
  sample_data$observation_id <- factor(sample_data$observation_id)
  model <- tryCatch(
    gam(
      formula_locked,
      data = sample_data,
      family = tw(link = "log"),
      method = "REML",
      na.action = na.fail
    ),
    error = function(error) NULL
  )
  if (is.null(model)) {
    return(c(estimate_log = NA_real_, standard_error = NA_real_, converged = 0))
  }
  table <- summary(model)$p.table
  estimate <- unname(table["post_collection_fraction", 1])
  standard_error <- unname(table["post_collection_fraction", 2])
  convergence <- if (!is.null(model$outer.info$conv)) {
    identical(model$outer.info$conv, "full convergence")
  } else {
    isTRUE(model$converged)
  }
  c(estimate_log = estimate, standard_error = standard_error, converged = as.numeric(convergence))
}

replicates <- as.integer(Sys.getenv("GRACKLES_BOOT_N", "2000"))
seeds <- 448443L + seq_len(replicates)
workers <- max(1L, min(3L, detectCores(logical = FALSE) - 1L))
if (workers > 1) {
  cluster <- makeCluster(workers)
  clusterEvalQ(cluster, suppressPackageStartupMessages(library(mgcv)))
  clusterExport(
    cluster,
    c("data", "formula_locked", "collection_ids", "noncollection_ids", "bootstrap_once"),
    envir = environment()
  )
  raw_results <- parLapplyLB(cluster, seeds, bootstrap_once)
  stopCluster(cluster)
} else {
  raw_results <- lapply(seeds, bootstrap_once)
}

bootstrap <- as.data.frame(do.call(rbind, raw_results))
bootstrap$replicate <- seq_len(nrow(bootstrap))
bootstrap$rate_ratio <- exp(bootstrap$estimate_log)
successful <- bootstrap[is.finite(bootstrap$estimate_log), ]

summary_table <- data.frame(
  metric = c(
    "Requested replicates",
    "Successful fits",
    "Converged fits",
    "Bootstrap median rate ratio",
    "Bootstrap 2.5th percentile",
    "Bootstrap 97.5th percentile",
    "Proportion of rate ratios above 1",
    "Bootstrap standard error on log scale"
  ),
  value = c(
    replicates,
    nrow(successful),
    sum(successful$converged == 1),
    median(successful$rate_ratio),
    unname(quantile(successful$rate_ratio, 0.025)),
    unname(quantile(successful$rate_ratio, 0.975)),
    mean(successful$rate_ratio > 1),
    sd(successful$estimate_log)
  ),
  stringsAsFactors = FALSE
)

# --- Export reproducible model tables ---
write.csv(bootstrap, file.path(output_dir, "primary_day_bootstrap_replicates.csv"), row.names = FALSE, na = "")
write.csv(summary_table, file.path(output_dir, "primary_day_bootstrap_summary.csv"), row.names = FALSE, na = "")
print(summary_table)
