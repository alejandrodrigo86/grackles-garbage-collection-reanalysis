# ================================================================================================
# Script: fit_time_decay_models.R
# Pipeline stage: 5. Time-since-collection analysis
# Analytical purpose: Fit adjusted models for the post-collection trajectory, window contrasts,
# linear decay, model comparisons, confounding checks, diagnostics, and smooth terms.
# Inputs: .codex_work/issue4/displacement_data_30min.csv
# Outputs: .codex_work/issue4/model_output/time_decay_model_estimates.csv and related
# time_decay_*.csv files
# Run-order position: 19
# Key scientific assumption: Clock time and day-level repeated observations are adjusted
# explicitly. Results describe association after collection, not a randomized causal effect of
# food abundance.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(splines))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

read_decay_data <- function(filename, nominal_seconds) {
  data <- read.csv(file.path(work_dir, filename), stringsAsFactors = FALSE)
  data <- data[order(data$observation_date, data$observation_id, data$bin_number, data$segment_number), ]
  data$observation_id <- factor(data$observation_id)
  data$observer <- factor(data$observer)
  data$collection_day <- as.numeric(data$collection_day)
  data$post_collection <- as.numeric(data$post_collection)
  data$camera_clock_hour <- as.numeric(data$camera_clock_hour)
  data$post_collection_hours <- as.numeric(data$post_collection_hours)
  data$foraging_seconds <- as.numeric(data$foraging_seconds)
  data$camera_offset <- log(data$segment_seconds / nominal_seconds)
  data$post_0_1 <- as.numeric(data$post_collection == 1 & data$post_collection_hours < 1)
  data$post_1_3 <- as.numeric(data$post_collection == 1 & data$post_collection_hours >= 1 & data$post_collection_hours < 3)
  data$post_3_6 <- as.numeric(data$post_collection == 1 & data$post_collection_hours >= 3 & data$post_collection_hours < 6)
  data$post_gt6 <- as.numeric(data$post_collection == 1 & data$post_collection_hours >= 6)
  rownames(data) <- NULL
  data
}

lag1_by_day <- function(values, data) {
  x <- numeric(0)
  y <- numeric(0)
  for (level in levels(droplevels(data$observation_id))) {
    indices <- which(data$observation_id == level)
    if (length(indices) < 2) next
    x <- c(x, values[indices[-length(indices)]])
    y <- c(y, values[indices[-1]])
  }
  if (length(x) < 3 || sd(x) == 0 || sd(y) == 0) return(NA_real_)
  cor(x, y, use = "complete.obs")
}

random_term <- "s(observation_id, bs = 're')"

make_formula <- function(extra_terms, include_observer = FALSE, clock_df = 4) {
  observer_term <- if (include_observer) " + observer" else ""
  as.formula(paste0(
    "foraging_seconds ~ ns(camera_clock_hour, df = ", clock_df, ") + collection_day + ", extra_terms, observer_term,
    " + offset(camera_offset) + ", random_term
  ))
}

fit_tweedie <- function(data, extra_terms, include_observer = FALSE, method = "REML", clock_df = 4) {
  gam(
    make_formula(extra_terms, include_observer, clock_df),
    data = data,
    family = tw(link = "log"),
    method = method,
    na.action = na.fail
  )
}

convergence_text <- function(model) {
  if (!is.null(model$outer.info$conv)) return(as.character(model$outer.info$conv))
  if (!is.null(model$converged)) return(as.character(model$converged))
  "not reported"
}

positive_hessian <- function(model) {
  if (is.null(model$outer.info$hess)) return(NA)
  all(eigen(model$outer.info$hess, symmetric = TRUE, only.values = TRUE)$values > 0)
}

extract_term <- function(model, data, analysis, term, bin_minutes, notes = "") {
  model_summary <- summary(model)
  table <- model_summary$p.table
  estimate <- unname(table[term, 1])
  standard_error <- unname(table[term, 2])
  p_value <- unname(table[term, ncol(table)])
  data.frame(
    analysis = analysis,
    term = term,
    bin_minutes = bin_minutes,
    interval_rows = nrow(data),
    observation_days = nlevels(droplevels(data$observation_id)),
    estimate_log = estimate,
    standard_error = standard_error,
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = p_value,
    aic = AIC(model),
    deviance_explained = model_summary$dev.expl,
    residual_lag1 = lag1_by_day(residuals(model, type = "pearson"), data),
    convergence = convergence_text(model),
    max_gradient = if (!is.null(model$outer.info$grad)) max(abs(model$outer.info$grad)) else NA_real_,
    positive_hessian = positive_hessian(model),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

contrast_ratio <- function(model, terms) {
  beta <- coef(model)
  covariance <- vcov(model)
  vector <- rep(0, length(beta))
  names(vector) <- names(beta)
  for (term in names(terms)) vector[term] <- terms[[term]]
  estimate <- sum(vector * beta)
  standard_error <- sqrt(as.numeric(t(vector) %*% covariance %*% vector))
  data.frame(
    estimate_log = estimate,
    standard_error = standard_error,
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    stringsAsFactors = FALSE
  )
}

extract_tweedie_diagnostics <- function(model, data) {
  model_summary <- summary(model)
  power <- model$family$getTheta(TRUE)
  if (length(power) > 1) power <- power[1]
  dispersion <- model_summary$scale
  fitted_mean <- fitted(model)
  expected_zero_probability <- exp(
    -(fitted_mean^(2 - power)) / (dispersion * (2 - power))
  )
  data.frame(
    metric = c(
      "Tweedie power",
      "Dispersion",
      "Observed zero intervals",
      "Expected zero intervals",
      "Residual lag-1 correlation",
      "Maximum absolute gradient"
    ),
    value = c(
      power,
      dispersion,
      sum(data$foraging_seconds == 0),
      sum(expected_zero_probability),
      lag1_by_day(residuals(model, type = "pearson"), data),
      max(abs(model$outer.info$grad))
    ),
    stringsAsFactors = FALSE
  )
}

data_30 <- read_decay_data("displacement_data_30min.csv", 1800)
data_15 <- read_decay_data("displacement_data_15min.csv", 900)
data_60 <- read_decay_data("displacement_data_60min.csv", 3600)

no_decay <- fit_tweedie(data_30, "post_collection")
linear_decay <- fit_tweedie(data_30, "post_collection + post_collection_hours")
smooth_decay <- fit_tweedie(
  data_30,
  "post_collection + s(post_collection_hours, by = post_collection, k = 4, bs = 'cr')"
)
window_model <- fit_tweedie(data_30, "post_0_1 + post_1_3 + post_3_6 + post_gt6")

results <- rbind(
  extract_term(
    no_decay, data_30, "No-decay event-centred model", "post_collection", 30,
    "Exact phase splitting but no elapsed-time term"
  ),
  extract_term(
    linear_decay, data_30, "Linear post-collection decay", "post_collection_hours", 30,
    "Rate ratio for each additional hour after collection ended"
  ),
  extract_term(
    linear_decay, data_30, "Immediate post-collection level", "post_collection", 30,
    "Model-implied ratio at collection end before hourly decay accumulates"
  )
)

without_n3 <- droplevels(data_30[data_30$observation_id != "N3", ])
first_six_hours <- droplevels(data_30[!(data_30$collection_day == 1 & data_30$post_collection_hours > 6), ])
linear_without_n3 <- fit_tweedie(without_n3, "post_collection + post_collection_hours")
linear_15 <- fit_tweedie(data_15, "post_collection + post_collection_hours")
linear_60 <- fit_tweedie(data_60, "post_collection + post_collection_hours")
linear_first_six <- fit_tweedie(first_six_hours, "post_collection + post_collection_hours")
linear_observer <- fit_tweedie(
  data_30, "post_collection + post_collection_hours", include_observer = TRUE
)
linear_clock3 <- fit_tweedie(data_30, "post_collection + post_collection_hours", clock_df = 3)
linear_clock5 <- fit_tweedie(data_30, "post_collection + post_collection_hours", clock_df = 5)
linear_clock6 <- fit_tweedie(data_30, "post_collection + post_collection_hours", clock_df = 6)
results <- rbind(
  results,
  extract_term(
    linear_without_n3, without_n3, "Linear decay excluding N3", "post_collection_hours", 30,
    "Leverage sensitivity"
  ),
  extract_term(
    linear_15, data_15, "Linear decay 15-minute sensitivity", "post_collection_hours", 15,
    "Aggregation sensitivity"
  ),
  extract_term(
    linear_60, data_60, "Linear decay 60-minute sensitivity", "post_collection_hours", 60,
    "Aggregation sensitivity"
  ),
  extract_term(
    linear_first_six, first_six_hours, "Linear decay limited to first 6 hours", "post_collection_hours", 30,
    "Checks whether very late near-zero activity alone drives the slope"
  ),
  extract_term(
    linear_observer, data_30, "Linear decay plus observer", "post_collection_hours", 30,
    "Observer fixed-effect sensitivity"
  ),
  extract_term(
    linear_clock3, data_30, "Linear decay with 3-df clock spline", "post_collection_hours", 30,
    "Clock-pattern flexibility sensitivity"
  ),
  extract_term(
    linear_clock5, data_30, "Linear decay with 5-df clock spline", "post_collection_hours", 30,
    "Clock-pattern flexibility sensitivity"
  ),
  extract_term(
    linear_clock6, data_30, "Linear decay with 6-df clock spline", "post_collection_hours", 30,
    "Clock-pattern flexibility sensitivity"
  )
)

window_terms <- c("post_0_1", "post_1_3", "post_3_6", "post_gt6")
window_labels <- c("Post 0-1 h", "Post 1-3 h", "Post 3-6 h", "Post >6 h")
window_results <- do.call(rbind, lapply(seq_along(window_terms), function(index) {
  row <- extract_term(
    window_model, data_30, paste0("Window: ", window_labels[index]),
    window_terms[index], 30,
    "Ratio versus collection-day pre period, adjusted for clock time"
  )
  row$window <- window_labels[index]
  row
}))

linear_contrasts <- do.call(rbind, lapply(c(0, 0.5, 1, 3, 6), function(hour) {
  contrast <- contrast_ratio(
    linear_decay,
    c(post_collection = 1, post_collection_hours = hour)
  )
  contrast$hours_after_collection <- hour
  contrast
}))
linear_contrasts <- linear_contrasts[, c("hours_after_collection", setdiff(names(linear_contrasts), "hours_after_collection"))]

no_decay_ml <- fit_tweedie(data_30, "post_collection", method = "ML")
linear_decay_ml <- fit_tweedie(data_30, "post_collection + post_collection_hours", method = "ML")
smooth_decay_ml <- fit_tweedie(
  data_30,
  "post_collection + s(post_collection_hours, by = post_collection, k = 4, bs = 'cr')",
  method = "ML"
)
model_comparison <- data.frame(
  model = c("No elapsed-time term", "Linear decay", "Smooth decay"),
  aic = c(AIC(no_decay_ml), AIC(linear_decay_ml), AIC(smooth_decay_ml)),
  effective_df = c(sum(no_decay_ml$edf), sum(linear_decay_ml$edf), sum(smooth_decay_ml$edf)),
  deviance_explained = c(summary(no_decay)$dev.expl, summary(linear_decay)$dev.expl, summary(smooth_decay)$dev.expl),
  stringsAsFactors = FALSE
)
model_comparison$delta_aic <- model_comparison$aic - min(model_comparison$aic)

lrt_statistic <- 2 * (as.numeric(logLik(linear_decay_ml)) - as.numeric(logLik(no_decay_ml)))
lrt_df <- attr(logLik(linear_decay_ml), "df") - attr(logLik(no_decay_ml), "df")
lrt <- data.frame(
  comparison = "Linear decay versus no elapsed-time term",
  likelihood_ratio = lrt_statistic,
  df = lrt_df,
  p_value = pchisq(lrt_statistic, df = lrt_df, lower.tail = FALSE),
  stringsAsFactors = FALSE
)

post_data <- data_30[data_30$collection_day == 1 & data_30$post_collection == 1, ]
confounding_model <- lm(
  post_collection_hours ~ ns(camera_clock_hour, df = 4),
  data = post_data,
  weights = segment_seconds
)
confounding <- data.frame(
  metric = c(
    "Post rows",
    "Post camera hours",
    "Clock-hour / elapsed-time correlation",
    "Weighted R-squared: elapsed time from clock spline",
    "Approximate VIF from weighted R-squared",
    "Collection-time range hours"
  ),
  value = c(
    nrow(post_data),
    sum(post_data$segment_seconds) / 3600,
    cor(post_data$camera_clock_hour, post_data$post_collection_hours),
    summary(confounding_model)$r.squared,
    1 / (1 - summary(confounding_model)$r.squared),
    diff(range(post_data$camera_clock_hour - post_data$post_collection_hours))
  ),
  stringsAsFactors = FALSE
)

diagnostics <- extract_tweedie_diagnostics(linear_decay, data_30)
smooth_table <- as.data.frame(summary(smooth_decay)$s.table)
smooth_table$term <- rownames(smooth_table)
rownames(smooth_table) <- NULL
smooth_table <- smooth_table[, c(ncol(smooth_table), seq_len(ncol(smooth_table) - 1))]
# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "time_decay_model_estimates.csv"), row.names = FALSE, na = "")
write.csv(window_results, file.path(output_dir, "time_decay_window_estimates.csv"), row.names = FALSE, na = "")
write.csv(linear_contrasts, file.path(output_dir, "time_decay_linear_contrasts.csv"), row.names = FALSE, na = "")
write.csv(model_comparison, file.path(output_dir, "time_decay_model_comparison.csv"), row.names = FALSE, na = "")
write.csv(lrt, file.path(output_dir, "time_decay_lrt.csv"), row.names = FALSE, na = "")
write.csv(confounding, file.path(output_dir, "time_decay_confounding.csv"), row.names = FALSE, na = "")
write.csv(diagnostics, file.path(output_dir, "time_decay_model_diagnostics.csv"), row.names = FALSE, na = "")
write.csv(smooth_table, file.path(output_dir, "time_decay_smooth_terms.csv"), row.names = FALSE, na = "")
capture.output(summary(linear_decay), file = file.path(output_dir, "time_decay_linear_summary.txt"))
capture.output(summary(smooth_decay), file = file.path(output_dir, "time_decay_smooth_summary.txt"))
capture.output(summary(window_model), file = file.path(output_dir, "time_decay_window_summary.txt"))
capture.output(concurvity(smooth_decay, full = TRUE), file = file.path(output_dir, "time_decay_smooth_concurvity.txt"))

print(results)
print(window_results)
print(linear_contrasts)
print(model_comparison)
print(lrt)
print(confounding)
print(diagnostics)
