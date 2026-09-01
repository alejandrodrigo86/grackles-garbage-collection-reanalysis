# ================================================================================================
# Script: fit_revision_models.R
# Pipeline stage: 6. Approved-revision audits
# Analytical purpose: Fit the recorded-group-size, multiple-occupancy, competitor-time-adjusted
# displacement, and raw-at-site containment-sensitivity models; then run day-level robustness
# checks.
# Inputs: .codex_work/issue4 group-size, displacement-direction, containment-sensitivity, and
# model datasets
# Outputs: .codex_work/issue4/model_output/revision_*.csv plus group-size bootstrap and leave-one-
# day-out tables
# Run-order position: 24
# Key scientific assumption: Recorded group size is descriptive of the camera view, not
# independent abundance. Competitor-time exposure and every 9+ value are conservative lower
# bounds.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(parallel))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

extract_effect <- function(model, data, analysis, response, ratio_type, notes = "", term = "post_collection_fraction") {
  table <- summary(model)$p.table
  estimate <- unname(table[term, 1])
  standard_error <- unname(table[term, 2])
  data.frame(
    analysis = analysis,
    response = response,
    ratio_type = ratio_type,
    interval_rows = nrow(data),
    observation_days = nlevels(droplevels(data$observation_id)),
    estimate_log = estimate,
    standard_error = standard_error,
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = unname(table[term, ncol(table)]),
    deviance_explained = summary(model)$dev.expl,
    convergence = if (!is.null(model$outer.info$conv)) as.character(model$outer.info$conv) else as.character(model$converged),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

group <- read.csv(file.path(work_dir, "group_size_phase_model_data_30min.csv"), stringsAsFactors = FALSE)
group <- group[is.finite(group$time_weighted_mean_group_size) & group$group_size_known_seconds > 0, ]
group$observation_id <- factor(group$original_recording_id)
group$collection_day <- as.numeric(group$collection_day)
group$post_collection <- as.numeric(group$post_collection)
group$clock_hour <- as.numeric(group$clock_hour)
group$group_size_known_seconds <- as.numeric(group$group_size_known_seconds)
group$time_weighted_mean_group_size <- as.numeric(group$time_weighted_mean_group_size)
group$multiple_grackle_fraction <- as.numeric(group$multiple_grackle_fraction)
group$maximum_group_size_lower_bound <- as.numeric(group$maximum_group_size_lower_bound)
group$analysis_weight <- pmax(group$group_size_known_seconds / 1800, 0.01)
group <- group[order(group$observation_date, group$bin_number, group$phase_segment_number), ]

group_formula <- time_weighted_mean_group_size ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection + s(observation_id, bs = "re")

group_model <- gam(
  group_formula,
  data = group,
  weights = analysis_weight,
  family = Gamma(link = "log"),
  method = "REML",
  na.action = na.fail
)

# Twenty annotations used the open-ended "More subjects" code. Excluding every
# interval that contains a 9+ lower-bound state checks whether that conservative
# numeric representation materially drives the estimate.
group_below_nine <- droplevels(group[group$maximum_group_size_lower_bound < 9, ])
group_below_nine_model <- gam(
  group_formula,
  data = group_below_nine,
  weights = analysis_weight,
  family = Gamma(link = "log"),
  method = "REML",
  na.action = na.fail
)

# A complementary beta-regression describes the fraction of known state time
# during which more than one grackle was recorded. The standard boundary
# adjustment retains intervals whose observed fraction is exactly 0 or 1.
n_group <- nrow(group)
group$multiple_fraction_adjusted <- (group$multiple_grackle_fraction * (n_group - 1) + 0.5) / n_group
multiple_model <- gam(
  multiple_fraction_adjusted ~ splines::ns(clock_hour, df = 4) +
    collection_day + post_collection + s(observation_id, bs = "re"),
  data = group,
  weights = analysis_weight,
  family = betar(link = "logit"),
  method = "REML",
  na.action = na.fail
)

group_estimates <- rbind(
  extract_effect(
    group_model, group, "Recorded group size: primary", "Time-weighted mean recorded group size",
    "Mean ratio", "Gamma-log model; count state known for 98.1% of focal-visible time", term = "post_collection"
  ),
  extract_effect(
    group_below_nine_model, group_below_nine, "Recorded group size: exclude 9+ intervals",
    "Time-weighted mean recorded group size", "Mean ratio",
    "Sensitivity excluding intervals containing the open-ended More subjects code", term = "post_collection"
  ),
  extract_effect(
    multiple_model, group, "Multiple-grackle occupancy", "Fraction of known time with >1 grackle",
    "Odds ratio", "Exploratory beta-regression with boundary adjustment", term = "post_collection"
  )
)

# Displacement events are focal-versus-other interactions, so the most direct
# recorded opportunity denominator is the time-integral of (group size - 1).
# This is preferable to camera time or focal-visible time alone. The 9+ code
# makes this denominator a conservative lower bound in affected intervals.
displacement_group <- droplevels(group[group$focal_competitor_seconds_lower_bound > 0, ])
displacement_group$competitor_offset <- log(displacement_group$focal_competitor_seconds_lower_bound / 1800)
displacement_formula <- displacement_events_with_known_group ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection + offset(competitor_offset) + s(observation_id, bs = "re")
displacement_competitor_model <- gam(
  displacement_formula,
  data = displacement_group,
  family = nb(link = "log"),
  method = "REML",
  na.action = na.fail
)

displacement_below_nine <- droplevels(displacement_group[displacement_group$maximum_group_size_lower_bound < 9, ])
displacement_below_nine_model <- gam(
  displacement_formula,
  data = displacement_below_nine,
  family = nb(link = "log"),
  method = "REML",
  na.action = na.fail
)

displacement_strict_formula <- displacement_events_with_recorded_competitor ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection + offset(competitor_offset) + s(observation_id, bs = "re")
displacement_strict_model <- gam(
  displacement_strict_formula,
  data = displacement_group,
  family = nb(link = "log"),
  method = "REML",
  na.action = na.fail
)

competitor_displacement_estimates <- rbind(
  extract_effect(
    displacement_competitor_model, displacement_group, "Competitor-time adjusted displacement",
    "Displacement events with known group state", "Rate ratio",
    "Offset is the time-integral of recorded focal competitors; 136 of 139 events retained",
    term = "post_collection"
  ),
  extract_effect(
    displacement_below_nine_model, displacement_below_nine,
    "Competitor-time adjusted displacement excluding 9+ intervals",
    "Displacement events with known group state", "Rate ratio",
    "Sensitivity excluding intervals containing the open-ended More subjects code",
    term = "post_collection"
  ),
  extract_effect(
    displacement_strict_model, displacement_group,
    "Competitor-time adjusted displacement: event-state strict",
    "Events whose exact timestamp had recorded group size >1", "Rate ratio",
    "Strict timestamp sensitivity retains 115 events; coding order can label an interaction instant as group size 1",
    term = "post_collection"
  )
)

# Population-level clock-time curves. The random day effect is set to zero by
# excluding the random-effect term during prediction.
clock_grid <- seq(min(group$clock_hour), max(group$clock_hour), length.out = 241)
reference_id <- levels(group$observation_id)[1]
prediction_grid <- rbind(
  data.frame(clock_hour = clock_grid, collection_day = 0, post_collection = 0,
             observation_id = factor(reference_id, levels = levels(group$observation_id)),
             phase = "Non-collection"),
  data.frame(clock_hour = clock_grid, collection_day = 1, post_collection = 0,
             observation_id = factor(reference_id, levels = levels(group$observation_id)),
             phase = "Collection day before end"),
  data.frame(clock_hour = clock_grid, collection_day = 1, post_collection = 1,
             observation_id = factor(reference_id, levels = levels(group$observation_id)),
             phase = "Collection day after end")
)
prediction <- predict(group_model, newdata = prediction_grid, type = "link", se.fit = TRUE,
                      exclude = "s(observation_id)")
prediction_grid$estimate <- exp(prediction$fit)
prediction_grid$ci_low <- exp(prediction$fit - qnorm(0.975) * prediction$se.fit)
prediction_grid$ci_high <- exp(prediction$fit + qnorm(0.975) * prediction$se.fit)

# Descriptive paired collection-day summaries retain the original day as the
# replicate and avoid treating thousands of count updates as independent.
day_phase <- read.csv(file.path(work_dir, "group_size_day_phase_summary.csv"), stringsAsFactors = FALSE)
pre <- day_phase[day_phase$collection_phase == "Pre-collection",
                 c("original_recording_id", "observation_number", "observation_label", "observation_date",
                   "group_size_known_hours", "time_weighted_mean_group_size", "multiple_grackle_percent")]
post <- day_phase[day_phase$collection_phase == "Post-collection",
                  c("original_recording_id", "group_size_known_hours", "time_weighted_mean_group_size", "multiple_grackle_percent")]
names(pre)[5:7] <- paste0("pre_", names(pre)[5:7])
names(post)[2:4] <- paste0("post_", names(post)[2:4])
paired <- merge(pre, post, by = "original_recording_id")
paired$mean_group_size_difference <- paired$post_time_weighted_mean_group_size - paired$pre_time_weighted_mean_group_size
paired$mean_group_size_ratio <- paired$post_time_weighted_mean_group_size / paired$pre_time_weighted_mean_group_size
paired$multiple_grackle_percentage_point_difference <- paired$post_multiple_grackle_percent - paired$pre_multiple_grackle_percent
paired <- paired[order(paired$observation_number), ]

# Observation-day bootstrap for the adjusted group-size ratio. Sampling remains
# stratified by collection status, as in the main analysis.
collection_ids <- unique(as.character(group$observation_id[group$collection_day == 1]))
noncollection_ids <- unique(as.character(group$observation_id[group$collection_day == 0]))
bootstrap_once <- function(seed) {
  set.seed(seed)
  sampled <- c(
    sample(collection_ids, length(collection_ids), replace = TRUE),
    sample(noncollection_ids, length(noncollection_ids), replace = TRUE)
  )
  pieces <- vector("list", length(sampled))
  for (index in seq_along(sampled)) {
    piece <- group[as.character(group$observation_id) == sampled[index], , drop = FALSE]
    piece$observation_id <- paste0("bootstrap_day_", sprintf("%02d", index))
    pieces[[index]] <- piece
  }
  sample_data <- do.call(rbind, pieces)
  sample_data$observation_id <- factor(sample_data$observation_id)
  model <- tryCatch(
    gam(group_formula, data = sample_data, weights = analysis_weight,
        family = Gamma(link = "log"), method = "REML", na.action = na.fail),
    error = function(error) NULL
  )
  if (is.null(model)) return(c(estimate_log = NA_real_, converged = 0))
  estimate <- unname(summary(model)$p.table["post_collection", 1])
  convergence <- if (!is.null(model$outer.info$conv)) identical(model$outer.info$conv, "full convergence") else isTRUE(model$converged)
  c(estimate_log = estimate, converged = as.numeric(convergence))
}

replicates <- as.integer(Sys.getenv("GRACKLES_GROUP_BOOT_N", "2000"))
seeds <- 9448443L + seq_len(replicates)
workers <- max(1L, min(3L, detectCores(logical = FALSE) - 1L))
if (workers > 1) {
  cluster <- makeCluster(workers)
  clusterEvalQ(cluster, suppressPackageStartupMessages(library(mgcv)))
  clusterExport(
    cluster,
    c("group", "group_formula", "collection_ids", "noncollection_ids", "bootstrap_once"),
    envir = environment()
  )
  raw_bootstrap <- parLapplyLB(cluster, seeds, bootstrap_once)
  stopCluster(cluster)
} else {
  raw_bootstrap <- lapply(seeds, bootstrap_once)
}
bootstrap <- as.data.frame(do.call(rbind, raw_bootstrap))
bootstrap$replicate <- seq_len(nrow(bootstrap))
bootstrap$effect_ratio <- exp(bootstrap$estimate_log)
successful <- bootstrap[is.finite(bootstrap$estimate_log), ]
bootstrap_summary <- data.frame(
  metric = c("Requested replicates", "Successful fits", "Converged fits", "Median mean ratio",
             "2.5th percentile", "97.5th percentile", "Proportion of ratios above 1"),
  value = c(replicates, nrow(successful), sum(successful$converged == 1), median(successful$effect_ratio),
            unname(quantile(successful$effect_ratio, 0.025)),
            unname(quantile(successful$effect_ratio, 0.975)), mean(successful$effect_ratio > 1)),
  stringsAsFactors = FALSE
)

# Leave-one-day-out check for direction and leverage.
loo <- do.call(rbind, lapply(levels(group$observation_id), function(omitted) {
  subset <- droplevels(group[group$observation_id != omitted, ])
  model <- gam(group_formula, data = subset, weights = analysis_weight,
               family = Gamma(link = "log"), method = "REML", na.action = na.fail)
  table <- summary(model)$p.table
  estimate <- unname(table["post_collection", 1])
  se <- unname(table["post_collection", 2])
  data.frame(
    omitted_original_recording_id = omitted,
    omitted_observation_number = unique(group$observation_number[as.character(group$observation_id) == omitted]),
    omitted_observation_label = unique(group$observation_label[as.character(group$observation_id) == omitted]),
    collection_day = unique(group$collection_day[as.character(group$observation_id) == omitted]),
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * se),
    ci_high = exp(estimate + qnorm(0.975) * se),
    p_value = unname(table["post_collection", ncol(table)]),
    stringsAsFactors = FALSE
  )
}))

# Sensitivity to the focal-visible union repair. These models use only the
# original At the observation site states and restrict foraging to their exact
# overlap.
containment <- read.csv(file.path(work_dir, "containment_sensitivity_data_30min.csv"), stringsAsFactors = FALSE)
containment$observation_id <- factor(containment$original_recording_id)
containment$collection_day <- as.numeric(containment$collection_day)
containment$post_collection_fraction <- as.numeric(containment$post_collection_fraction)
containment$clock_hour <- as.numeric(containment$clock_hour)
containment$camera_seconds <- as.numeric(containment$camera_seconds)
containment$raw_at_site_seconds <- as.numeric(containment$raw_at_site_seconds)
containment$foraging_within_raw_at_site_seconds <- as.numeric(containment$foraging_within_raw_at_site_seconds)
containment$camera_offset <- log(containment$camera_seconds / 1800)

# --- Mechanism-specific model specifications ---
attendance_formula <- raw_at_site_seconds ~ splines::ns(clock_hour, df = 4) + collection_day +
  post_collection_fraction + offset(camera_offset) + s(observation_id, bs = "re")
raw_attendance_model <- gam(attendance_formula, data = containment, family = tw(link = "log"),
                            method = "REML", na.action = na.fail)

raw_intensity <- droplevels(containment[containment$raw_at_site_seconds > 0, ])
raw_intensity$visible_offset <- log(raw_intensity$raw_at_site_seconds / 1800)
intensity_formula <- foraging_within_raw_at_site_seconds ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + offset(visible_offset) + s(observation_id, bs = "re")
raw_intensity_model <- gam(intensity_formula, data = raw_intensity, family = tw(link = "log"),
                           method = "REML", na.action = na.fail)

containment_estimates <- rbind(
  extract_effect(raw_attendance_model, containment, "Raw at-site attendance sensitivity", "Raw at-site duration",
                 "Rate ratio", "Uses only original At the observation site states"),
  extract_effect(raw_intensity_model, raw_intensity, "Raw at-site intensity sensitivity",
                 "Foraging duration within raw at-site states", "Rate ratio",
                 "Foraging and exposure both restricted to original At the observation site states")
)

group_qc <- read.csv(file.path(work_dir, "group_size_qc.csv"), stringsAsFactors = FALSE)
group_state_coverage <- sum(group_qc$group_size_known_seconds) / sum(group_qc$focal_visible_seconds)
diagnostics <- data.frame(
  metric = c(
    "Group-size interval rows",
    "Observation days",
    "Known group-size hours",
    "Focal-visible hours represented",
    "Intervals containing a 9+ state",
    "Paired collection days with both phases",
    "Paired days with larger postcollection mean",
    "Paired days with smaller postcollection mean",
    "Gamma model deviance explained",
    "Gamma model scale"
  ),
  value = c(
    nrow(group), nlevels(group$observation_id), sum(group$group_size_known_seconds) / 3600,
    group_state_coverage,
    sum(group$maximum_group_size_lower_bound >= 9), nrow(paired),
    sum(paired$mean_group_size_difference > 0), sum(paired$mean_group_size_difference < 0),
    summary(group_model)$dev.expl, summary(group_model)$scale
  ),
  stringsAsFactors = FALSE
)

# --- Export reproducible model tables ---
write.csv(group_estimates, file.path(output_dir, "group_size_model_estimates.csv"), row.names = FALSE, na = "")
write.csv(competitor_displacement_estimates, file.path(output_dir, "competitor_displacement_estimates.csv"), row.names = FALSE, na = "")
write.csv(prediction_grid, file.path(output_dir, "group_size_predictions.csv"), row.names = FALSE, na = "")
write.csv(paired, file.path(output_dir, "group_size_paired_days.csv"), row.names = FALSE, na = "")
write.csv(bootstrap, file.path(output_dir, "group_size_day_bootstrap_replicates.csv"), row.names = FALSE, na = "")
write.csv(bootstrap_summary, file.path(output_dir, "group_size_day_bootstrap_summary.csv"), row.names = FALSE, na = "")
write.csv(loo, file.path(output_dir, "group_size_leave_one_day_out.csv"), row.names = FALSE, na = "")
write.csv(diagnostics, file.path(output_dir, "group_size_diagnostics.csv"), row.names = FALSE, na = "")
write.csv(containment_estimates, file.path(output_dir, "containment_sensitivity_estimates.csv"), row.names = FALSE, na = "")
capture.output(summary(group_model), file = file.path(output_dir, "group_size_model_summary.txt"))
capture.output(summary(displacement_competitor_model), file = file.path(output_dir, "competitor_displacement_model_summary.txt"))
capture.output(gam.check(group_model), file = file.path(output_dir, "group_size_gam_check.txt"))
capture.output(summary(raw_attendance_model), file = file.path(output_dir, "raw_at_site_attendance_summary.txt"))
capture.output(summary(raw_intensity_model), file = file.path(output_dir, "raw_at_site_intensity_summary.txt"))

print(group_estimates)
print(competitor_displacement_estimates)
print(bootstrap_summary)
print(diagnostics)
print(containment_estimates)
