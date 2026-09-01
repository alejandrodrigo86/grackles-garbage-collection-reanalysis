# ================================================================================================
# Script: fit_decomposition_models.R
# Pipeline stage: 3. Attendance/intensity decomposition
# Analytical purpose: Decompose total foraging into recorded focal visibility (visible seconds per
# camera time) and conditional foraging intensity (foraging seconds per visible time).
# Inputs: .codex_work/issue4/model_data_30min.csv and sensitivity-resolution CSVs
# Outputs: .codex_work/issue4/model_output/decomposition_estimates.csv;
# decomposition_profiles.csv; decomposition_diagnostics.csv
# Run-order position: 08
# Key scientific assumption: Recorded focal visibility and conditional foraging intensity are
# distinct operational components. Visibility combines bird presence in view with detectability
# because obstruction was not coded.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

read_model_data <- function(filename, nominal_seconds) {
  data <- read.csv(file.path(work_dir, filename), stringsAsFactors = FALSE)
  data$observation_id <- factor(data$observation_id)
  data$collection_day <- as.numeric(data$collection_day)
  data$post_collection_fraction <- as.numeric(data$post_collection_fraction)
  data$clock_hour <- as.numeric(data$clock_hour)
  data$camera_seconds <- as.numeric(data$camera_seconds)
  data$foraging_seconds <- as.numeric(data$foraging_seconds)
  data$focal_visible_seconds <- as.numeric(data$focal_visible_seconds)
  data$camera_offset <- log(data$camera_seconds / nominal_seconds)
  data <- data[order(data$observation_date, data$observation_id, data$bin_number), ]
  rownames(data) <- NULL
  data$ar_start <- c(
    TRUE,
    as.character(data$observation_id[-1]) != as.character(data$observation_id[-nrow(data)]) |
      diff(data$bin_number) != 1
  )
  data
}

prepare_intensity_data <- function(data, nominal_seconds) {
  intensity <- droplevels(data[data$focal_visible_seconds > 0, ])
  intensity$visible_offset <- log(intensity$focal_visible_seconds / nominal_seconds)
  intensity$intensity_proportion <- intensity$foraging_seconds / intensity$focal_visible_seconds
  intensity$visible_minutes <- intensity$focal_visible_seconds / 60
  intensity$ar_start <- c(
    TRUE,
    as.character(intensity$observation_id[-1]) != as.character(intensity$observation_id[-nrow(intensity)]) |
      diff(intensity$bin_number) != 1
  )
  intensity
}

lag1_by_day <- function(values, data) {
  x <- numeric(0)
  y <- numeric(0)
  for (level in levels(droplevels(data$observation_id))) {
    indices <- which(data$observation_id == level)
    if (length(indices) < 2) next
    ordered <- indices[order(data$bin_number[indices])]
    adjacent <- which(diff(data$bin_number[ordered]) == 1)
    if (length(adjacent) == 0) next
    x <- c(x, values[ordered[adjacent]])
    y <- c(y, values[ordered[adjacent + 1]])
  }
  if (length(x) < 3 || sd(x) == 0 || sd(y) == 0) return(NA_real_)
  cor(x, y, use = "complete.obs")
}

offset_formula <- function(response, offset_name) {
  as.formula(paste0(
    response,
    " ~ splines::ns(clock_hour, df = 4) + collection_day + ",
    "post_collection_fraction + offset(", offset_name, ") + ",
    "s(observation_id, bs = 're')"
  ))
}

proportion_formula <- intensity_proportion ~ splines::ns(clock_hour, df = 4) +
  collection_day + post_collection_fraction + s(observation_id, bs = "re")

fit_tweedie <- function(data, response, offset_name) {
  gam(
    offset_formula(response, offset_name),
    data = data,
    family = tw(link = "log"),
    method = "REML",
    na.action = na.fail
  )
}

extract_effect <- function(model, data, analysis, mechanism, ratio_type, bin_minutes, notes = "") {
  table <- summary(model)$p.table
  term <- "post_collection_fraction"
  estimate <- unname(table[term, 1])
  standard_error <- unname(table[term, 2])
  residual <- residuals(model, type = "pearson")
  data.frame(
    analysis = analysis,
    mechanism = mechanism,
    ratio_type = ratio_type,
    bin_minutes = bin_minutes,
    interval_rows = nrow(data),
    observation_days = nlevels(droplevels(data$observation_id)),
    estimate_log = estimate,
    standard_error = standard_error,
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = unname(table[term, ncol(table)]),
    deviance_explained = summary(model)$dev.expl,
    residual_lag1 = lag1_by_day(residual, data),
    convergence = if (!is.null(model$outer.info$conv)) as.character(model$outer.info$conv) else as.character(model$converged),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

zero_diagnostics <- function(model, data, response, label) {
  power <- tryCatch(model$family$getTheta(TRUE), error = function(error) NA_real_)
  if (length(power) > 1) power <- power[1]
  dispersion <- summary(model)$scale
  fitted_mean <- fitted(model)
  expected_zero_probability <- exp(-(fitted_mean^(2 - power)) / (dispersion * (2 - power)))
  data.frame(
    mechanism = label,
    tweedie_power = power,
    dispersion = dispersion,
    observed_zero_intervals = sum(data[[response]] == 0),
    expected_zero_intervals = sum(expected_zero_probability),
    observed_zero_fraction = mean(data[[response]] == 0),
    expected_zero_fraction = mean(expected_zero_probability),
    maximum_absolute_gradient = if (!is.null(model$outer.info$grad)) max(abs(model$outer.info$grad)) else NA_real_,
    model_rank = model$rank,
    coefficient_count = length(coef(model)),
    stringsAsFactors = FALSE
  )
}

fit_ar1 <- function(data, response, offset_name, rho) {
  data$ar_start_value <- data[["ar_start"]]
  bam(
    offset_formula(response, offset_name),
    data = data,
    family = tw(link = "log"),
    method = "fREML",
    discrete = TRUE,
    rho = max(-0.9, min(0.9, rho)),
    AR.start = ar_start_value,
    na.action = na.fail
  )
}

data_30 <- read_model_data("model_data_30min.csv", 1800)
data_15 <- read_model_data("model_data_15min.csv", 900)
data_60 <- read_model_data("model_data_60min.csv", 3600)
intensity_30 <- prepare_intensity_data(data_30, 1800)
intensity_15 <- prepare_intensity_data(data_15, 900)
intensity_60 <- prepare_intensity_data(data_60, 3600)

attendance <- fit_tweedie(data_30, "focal_visible_seconds", "camera_offset")
intensity <- fit_tweedie(intensity_30, "foraging_seconds", "visible_offset")

results <- rbind(
  extract_effect(attendance, data_30, "Attendance primary 30-minute", "Patch attendance", "Rate ratio", 30, "Focal-visible seconds per camera exposure"),
  extract_effect(intensity, intensity_30, "Intensity primary 30-minute", "Conditional foraging intensity", "Rate ratio", 30, "Foraging seconds per focal-visible exposure")
)

fractional_logit <- gam(
  proportion_formula,
  data = intensity_30,
  weights = visible_minutes,
  family = quasibinomial(link = "logit"),
  method = "REML",
  na.action = na.fail
)
results <- rbind(
  results,
  extract_effect(
    fractional_logit, intensity_30, "Intensity fractional-logit sensitivity",
    "Conditional foraging intensity", "Odds ratio", 30,
    "Quasibinomial proportion model weighted by focal-visible minutes"
  )
)

data_without_n3 <- droplevels(data_30[data_30$observation_id != "N3", ])
intensity_without_n3 <- prepare_intensity_data(data_without_n3, 1800)
attendance_without_n3 <- fit_tweedie(data_without_n3, "focal_visible_seconds", "camera_offset")
intensity_without_n3_model <- fit_tweedie(intensity_without_n3, "foraging_seconds", "visible_offset")
results <- rbind(
  results,
  extract_effect(attendance_without_n3, data_without_n3, "Attendance excluding N3", "Patch attendance", "Rate ratio", 30, "Leverage sensitivity"),
  extract_effect(intensity_without_n3_model, intensity_without_n3, "Intensity excluding N3", "Conditional foraging intensity", "Rate ratio", 30, "Leverage sensitivity")
)

attendance_15 <- fit_tweedie(data_15, "focal_visible_seconds", "camera_offset")
intensity_15_model <- fit_tweedie(intensity_15, "foraging_seconds", "visible_offset")
attendance_60 <- fit_tweedie(data_60, "focal_visible_seconds", "camera_offset")
intensity_60_model <- fit_tweedie(intensity_60, "foraging_seconds", "visible_offset")
results <- rbind(
  results,
  extract_effect(attendance_15, data_15, "Attendance 15-minute sensitivity", "Patch attendance", "Rate ratio", 15, "Aggregation sensitivity"),
  extract_effect(intensity_15_model, intensity_15, "Intensity 15-minute sensitivity", "Conditional foraging intensity", "Rate ratio", 15, "Aggregation sensitivity"),
  extract_effect(attendance_60, data_60, "Attendance 60-minute sensitivity", "Patch attendance", "Rate ratio", 60, "Aggregation sensitivity"),
  extract_effect(intensity_60_model, intensity_60, "Intensity 60-minute sensitivity", "Conditional foraging intensity", "Rate ratio", 60, "Aggregation sensitivity")
)

attendance_lag <- results$residual_lag1[results$analysis == "Attendance primary 30-minute"]
intensity_lag <- results$residual_lag1[results$analysis == "Intensity primary 30-minute"]
attendance_ar1 <- fit_ar1(data_30, "focal_visible_seconds", "camera_offset", attendance_lag)
intensity_ar1 <- fit_ar1(intensity_30, "foraging_seconds", "visible_offset", intensity_lag)
results <- rbind(
  results,
  extract_effect(attendance_ar1, data_30, "Attendance AR(1) sensitivity", "Patch attendance", "Rate ratio", 30, paste0("rho = ", round(attendance_lag, 4))),
  extract_effect(intensity_ar1, intensity_30, "Intensity AR(1) sensitivity", "Conditional foraging intensity", "Rate ratio", 30, paste0("rho = ", round(intensity_lag, 4)))
)

profiles <- data.frame(
  metric = c(
    "All interval rows",
    "Intervals with no focal visibility",
    "Intervals with focal visibility",
    "Visible intervals with zero foraging",
    "Visible intervals with foraging equal to focal-visible time",
    "Mean interval-level foraging proportion when visible",
    "Exposure-weighted foraging proportion when visible"
  ),
  value = c(
    nrow(data_30),
    sum(data_30$focal_visible_seconds == 0),
    nrow(intensity_30),
    sum(intensity_30$foraging_seconds == 0),
    sum(abs(intensity_30$foraging_seconds - intensity_30$focal_visible_seconds) < 1e-9),
    mean(intensity_30$intensity_proportion),
    sum(intensity_30$foraging_seconds) / sum(intensity_30$focal_visible_seconds)
  ),
  stringsAsFactors = FALSE
)

diagnostics <- rbind(
  zero_diagnostics(attendance, data_30, "focal_visible_seconds", "Patch attendance"),
  zero_diagnostics(intensity, intensity_30, "foraging_seconds", "Conditional foraging intensity")
)

# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "decomposition_estimates.csv"), row.names = FALSE, na = "")
write.csv(profiles, file.path(output_dir, "decomposition_profiles.csv"), row.names = FALSE, na = "")
write.csv(diagnostics, file.path(output_dir, "decomposition_diagnostics.csv"), row.names = FALSE, na = "")
capture.output(summary(attendance), file = file.path(output_dir, "attendance_model_summary.txt"))
capture.output(summary(intensity), file = file.path(output_dir, "intensity_model_summary.txt"))
capture.output(summary(fractional_logit), file = file.path(output_dir, "intensity_fractional_logit_summary.txt"))
capture.output(gam.check(attendance), file = file.path(output_dir, "attendance_gam_check.txt"))
capture.output(gam.check(intensity), file = file.path(output_dir, "intensity_gam_check.txt"))

print(profiles)
print(results)
print(diagnostics)
