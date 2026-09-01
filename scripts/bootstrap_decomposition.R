# ================================================================================================
# Script: bootstrap_decomposition.R
# Pipeline stage: 3. Attendance/intensity decomposition
# Analytical purpose: Use day-cluster bootstrap resampling to quantify uncertainty in attendance
# and conditional-intensity effects.
# Inputs: .codex_work/issue4/model_data_30min.csv
# Outputs: .codex_work/issue4/model_output/decomposition_day_bootstrap_replicates.csv and
# decomposition_day_bootstrap_summary.csv
# Run-order position: 09
# Key scientific assumption: Whole days are resampled; models retain the same locked adjustment
# and exposure structures as the decomposition analysis.
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
data$camera_offset <- log(as.numeric(data$camera_seconds) / 1800)

# --- Mechanism-specific model specifications ---
attendance_formula <- focal_visible_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(camera_offset) +
  s(observation_id, bs = "re")
intensity_formula <- foraging_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(visible_offset) +
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
  intensity_data <- droplevels(sample_data[sample_data$focal_visible_seconds > 0, ])
  intensity_data$visible_offset <- log(intensity_data$focal_visible_seconds / 1800)

  attendance <- tryCatch(
    gam(attendance_formula, data = sample_data, family = tw(link = "log"), method = "REML", na.action = na.fail),
    error = function(error) NULL
  )
  intensity <- tryCatch(
    gam(intensity_formula, data = intensity_data, family = tw(link = "log"), method = "REML", na.action = na.fail),
    error = function(error) NULL
  )
  if (is.null(attendance) || is.null(intensity)) {
    return(c(attendance_log = NA_real_, intensity_log = NA_real_, product_log = NA_real_, converged = 0))
  }
  attendance_estimate <- unname(summary(attendance)$p.table["post_collection_fraction", 1])
  intensity_estimate <- unname(summary(intensity)$p.table["post_collection_fraction", 1])
  attendance_converged <- identical(attendance$outer.info$conv, "full convergence")
  intensity_converged <- identical(intensity$outer.info$conv, "full convergence")
  c(
    attendance_log = attendance_estimate,
    intensity_log = intensity_estimate,
    product_log = attendance_estimate + intensity_estimate,
    converged = as.numeric(attendance_converged && intensity_converged)
  )
}

replicates <- as.integer(Sys.getenv("GRACKLES_BOOT_N", "2000"))
seeds <- 448843L + seq_len(replicates)
workers <- max(1L, min(3L, detectCores(logical = FALSE) - 1L))
if (workers > 1) {
  cluster <- makeCluster(workers)
  clusterEvalQ(cluster, suppressPackageStartupMessages(library(mgcv)))
  clusterExport(
    cluster,
    c(
      "data", "attendance_formula", "intensity_formula", "collection_ids",
      "noncollection_ids", "bootstrap_once"
    ),
    envir = environment()
  )
  raw <- parLapplyLB(cluster, seeds, bootstrap_once)
  stopCluster(cluster)
} else {
  raw <- lapply(seeds, bootstrap_once)
}

bootstrap <- as.data.frame(do.call(rbind, raw))
bootstrap$replicate <- seq_len(nrow(bootstrap))
bootstrap$attendance_ratio <- exp(bootstrap$attendance_log)
bootstrap$intensity_ratio <- exp(bootstrap$intensity_log)
bootstrap$product_ratio <- exp(bootstrap$product_log)
successful <- bootstrap[is.finite(bootstrap$product_log), ]

summarize_ratio <- function(values, mechanism) {
  data.frame(
    mechanism = mechanism,
    requested_replicates = replicates,
    successful_fits = length(values),
    converged_joint_fits = sum(successful$converged == 1),
    median_ratio = median(values),
    ci_low = unname(quantile(values, 0.025)),
    ci_high = unname(quantile(values, 0.975)),
    fraction_above_one = mean(values > 1),
    stringsAsFactors = FALSE
  )
}

summary_table <- rbind(
  summarize_ratio(successful$attendance_ratio, "Patch attendance"),
  summarize_ratio(successful$intensity_ratio, "Conditional foraging intensity"),
  summarize_ratio(successful$product_ratio, "Attendance × intensity")
)

# --- Export reproducible model tables ---
write.csv(bootstrap, file.path(output_dir, "decomposition_day_bootstrap_replicates.csv"), row.names = FALSE, na = "")
write.csv(summary_table, file.path(output_dir, "decomposition_day_bootstrap_summary.csv"), row.names = FALSE, na = "")
print(summary_table)
