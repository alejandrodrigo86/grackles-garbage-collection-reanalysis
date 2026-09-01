# ================================================================================================
# Script: fit_locked_models.R
# Pipeline stage: 2. Primary analysis
# Analytical purpose: Fit the designated primary reanalysis model for foraging seconds, plus
# documented secondary models, predictions, residual checks, and model tables.
# Inputs: .codex_work/issue4/model_data_30min.csv and sensitivity-resolution CSVs
# Outputs: .codex_work/issue4/model_output/model_estimates.csv; primary_fixed_effects.csv;
# primary_smooth_terms.csv; primary_tweedie_diagnostics.csv; primary_predictions.csv; fitted data;
# session_info.txt
# Run-order position: 04
# Key scientific assumption: Observation day is the replication unit through a day-level random
# intercept. Clock time is adjusted with a four-degree-of-freedom natural cubic spline, and camera
# time enters as an offset.
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
  data$foraging_bouts <- as.numeric(data$foraging_bouts)
  data$any_foraging <- as.numeric(data$any_foraging)
  data$exposure_offset <- log(data$camera_seconds / nominal_seconds)
  data$ar_start <- as.logical(data$ar_start)
  data <- data[order(data$observation_date, data$observation_id, data$bin_number), ]
  rownames(data) <- NULL
  data
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

model_formula <- function(response) {
  as.formula(paste0(
    response,
    " ~ splines::ns(clock_hour, df = 4) + collection_day + ",
    "post_collection_fraction + offset(exposure_offset) + ",
    "s(observation_id, bs = 're')"
  ))
}

fit_gam <- function(data, response, family) {
  gam(
    model_formula(response),
    data = data,
    family = family,
    method = "REML",
    na.action = na.fail
  )
}

extract_effect <- function(model, data, analysis, response, family_label, bin_minutes, notes = "") {
  model_summary <- summary(model)
  coefficient_table <- model_summary$p.table
  term <- "post_collection_fraction"
  if (!term %in% rownames(coefficient_table)) {
    stop(paste("Primary term missing from", analysis))
  }
  estimate <- unname(coefficient_table[term, 1])
  standard_error <- unname(coefficient_table[term, 2])
  p_value <- unname(coefficient_table[term, ncol(coefficient_table)])
  pearson_residuals <- residuals(model, type = "pearson")
  outer_convergence <- if (!is.null(model$outer.info$conv)) {
    as.character(model$outer.info$conv)
  } else if (!is.null(model$converged)) {
    as.character(model$converged)
  } else {
    "not reported"
  }
  data.frame(
    analysis = analysis,
    response = response,
    family = family_label,
    bin_minutes = bin_minutes,
    interval_rows = nrow(data),
    observation_days = nlevels(droplevels(data$observation_id)),
    estimate_log = estimate,
    standard_error = standard_error,
    rate_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = p_value,
    aic = AIC(model),
    deviance_explained = model_summary$dev.expl,
    adjusted_r_squared = model_summary$r.sq,
    residual_lag1 = lag1_by_day(pearson_residuals, data),
    convergence = outer_convergence,
    notes = notes,
    stringsAsFactors = FALSE
  )
}

extract_tweedie_diagnostics <- function(model, data) {
  model_summary <- summary(model)
  power <- tryCatch(model$family$getTheta(TRUE), error = function(error) NA_real_)
  if (length(power) > 1) power <- power[1]
  dispersion <- model_summary$scale
  fitted_mean <- fitted(model)
  expected_zero_probability <- if (is.finite(power) && power > 1 && power < 2) {
    exp(-(fitted_mean^(2 - power)) / (dispersion * (2 - power)))
  } else {
    rep(NA_real_, length(fitted_mean))
  }
  data.frame(
    metric = c(
      "Tweedie power parameter",
      "Dispersion parameter",
      "Observed zero intervals",
      "Expected zero intervals",
      "Observed zero fraction",
      "Expected zero fraction",
      "Maximum absolute gradient",
      "Model rank",
      "Coefficient count"
    ),
    value = c(
      power,
      dispersion,
      sum(data$foraging_seconds == 0),
      sum(expected_zero_probability),
      mean(data$foraging_seconds == 0),
      mean(expected_zero_probability),
      if (!is.null(model$outer.info$grad)) max(abs(model$outer.info$grad)) else NA_real_,
      model$rank,
      length(coef(model))
    ),
    stringsAsFactors = FALSE
  )
}

data_30 <- read_model_data("model_data_30min.csv", 1800)
data_15 <- read_model_data("model_data_15min.csv", 900)
data_60 <- read_model_data("model_data_60min.csv", 3600)

primary <- fit_gam(data_30, "foraging_seconds", tw(link = "log"))
results <- extract_effect(
  primary, data_30, "Primary 30-minute model", "foraging_seconds",
  "Tweedie log-link mixed GAM", 30,
  "Locked primary model"
)

negative_binomial <- fit_gam(data_30, "foraging_bouts", nb(link = "log"))
results <- rbind(
  results,
  extract_effect(
    negative_binomial, data_30, "Secondary bout-frequency model", "foraging_bouts",
    "Negative-binomial log-link mixed GAM", 30,
    "Poisson rejected before fitting because of overdispersion"
  )
)

hurdle_occurrence <- fit_gam(data_30, "any_foraging", binomial(link = "cloglog"))
results <- rbind(
  results,
  extract_effect(
    hurdle_occurrence, data_30, "Hurdle occurrence component", "any_foraging",
    "Binomial complementary-log-log mixed GAM", 30,
    "Probability that an interval contains any foraging"
  )
)

positive_data <- droplevels(data_30[data_30$foraging_seconds > 0, ])
hurdle_positive <- fit_gam(positive_data, "foraging_seconds", Gamma(link = "log"))
results <- rbind(
  results,
  extract_effect(
    hurdle_positive, positive_data, "Hurdle positive-duration component", "foraging_seconds",
    "Gamma log-link mixed GAM", 30,
    "Conditional duration among intervals with foraging"
  )
)

data_without_n3 <- droplevels(data_30[data_30$observation_id != "N3", ])
without_n3 <- fit_gam(data_without_n3, "foraging_seconds", tw(link = "log"))
results <- rbind(
  results,
  extract_effect(
    without_n3, data_without_n3, "Primary model excluding N3", "foraging_seconds",
    "Tweedie log-link mixed GAM", 30,
    "Required leverage sensitivity"
  )
)

primary_15 <- fit_gam(data_15, "foraging_seconds", tw(link = "log"))
results <- rbind(
  results,
  extract_effect(
    primary_15, data_15, "15-minute bin sensitivity", "foraging_seconds",
    "Tweedie log-link mixed GAM", 15,
    "Required aggregation sensitivity"
  )
)

primary_60 <- fit_gam(data_60, "foraging_seconds", tw(link = "log"))
results <- rbind(
  results,
  extract_effect(
    primary_60, data_60, "60-minute bin sensitivity", "foraging_seconds",
    "Tweedie log-link mixed GAM", 60,
    "Required aggregation sensitivity"
  )
)

primary_residual_lag1 <- results$residual_lag1[results$analysis == "Primary 30-minute model"]
estimated_rho <- max(-0.9, min(0.9, primary_residual_lag1))
ar1_error <- ""
ar1_model <- tryCatch(
  bam(
    model_formula("foraging_seconds"),
    data = data_30,
    family = tw(link = "log"),
    method = "fREML",
    discrete = TRUE,
    rho = estimated_rho,
    AR.start = data_30$ar_start,
    na.action = na.fail
  ),
  error = function(error) {
    ar1_error <<- conditionMessage(error)
    NULL
  }
)
if (!is.null(ar1_model)) {
  results <- rbind(
    results,
    extract_effect(
      ar1_model, data_30, "AR(1) temporal sensitivity", "foraging_seconds",
      "Tweedie log-link BAM with AR(1)", 30,
      paste0("rho fixed to primary Pearson-residual lag-1 estimate: ", round(estimated_rho, 4))
    )
  )
}

fixed_effects <- as.data.frame(summary(primary)$p.table)
fixed_effects$term <- rownames(fixed_effects)
rownames(fixed_effects) <- NULL
fixed_effects <- fixed_effects[, c(ncol(fixed_effects), seq_len(ncol(fixed_effects) - 1))]

smooth_terms <- as.data.frame(summary(primary)$s.table)
smooth_terms$term <- rownames(smooth_terms)
rownames(smooth_terms) <- NULL
smooth_terms <- smooth_terms[, c(ncol(smooth_terms), seq_len(ncol(smooth_terms) - 1))]

tweedie_diagnostics <- extract_tweedie_diagnostics(primary, data_30)

prediction_hours <- seq(min(data_30$clock_hour), max(data_30$clock_hour), length.out = 160)
prediction_grid <- expand.grid(
  clock_hour = prediction_hours,
  scenario = c("Non-collection baseline", "Collection day before end", "Collection day after end"),
  stringsAsFactors = FALSE
)
prediction_grid$collection_day <- ifelse(prediction_grid$scenario == "Non-collection baseline", 0, 1)
prediction_grid$post_collection_fraction <- ifelse(prediction_grid$scenario == "Collection day after end", 1, 0)
prediction_grid$exposure_offset <- 0
prediction_grid$observation_id <- factor(levels(data_30$observation_id)[1], levels = levels(data_30$observation_id))
prediction <- predict(
  primary,
  newdata = prediction_grid,
  type = "link",
  se.fit = TRUE,
  exclude = "s(observation_id)"
)
prediction_grid$expected_foraging_seconds_per_30_min <- exp(prediction$fit)
prediction_grid$ci_low <- exp(prediction$fit - qnorm(0.975) * prediction$se.fit)
prediction_grid$ci_high <- exp(prediction$fit + qnorm(0.975) * prediction$se.fit)

data_30$primary_fitted_seconds <- fitted(primary)
data_30$primary_pearson_residual <- residuals(primary, type = "pearson")
data_30$primary_deviance_residual <- residuals(primary, type = "deviance")

# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "model_estimates.csv"), row.names = FALSE, na = "")
write.csv(fixed_effects, file.path(output_dir, "primary_fixed_effects.csv"), row.names = FALSE, na = "")
write.csv(smooth_terms, file.path(output_dir, "primary_smooth_terms.csv"), row.names = FALSE, na = "")
write.csv(tweedie_diagnostics, file.path(output_dir, "primary_tweedie_diagnostics.csv"), row.names = FALSE, na = "")
write.csv(prediction_grid, file.path(output_dir, "primary_predictions.csv"), row.names = FALSE, na = "")
write.csv(data_30, file.path(output_dir, "model_data_with_primary_fit.csv"), row.names = FALSE, na = "")

capture.output(summary(primary), file = file.path(output_dir, "primary_model_summary.txt"))
capture.output(gam.check(primary), file = file.path(output_dir, "primary_gam_check.txt"))
capture.output(concurvity(primary, full = TRUE), file = file.path(output_dir, "primary_concurvity.txt"))
capture.output(sessionInfo(), file = file.path(output_dir, "session_info.txt"))
writeLines(ar1_error, file.path(output_dir, "ar1_error.txt"))

print(results)
print(tweedie_diagnostics)
