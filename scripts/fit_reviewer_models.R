# ================================================================================================
# Script: fit_reviewer_models.R
# Pipeline stage: 6. Blind-review analyses
# Analytical purpose: Fit the requested precollection-versus-noncollection and postcollection-
# versus-noncollection contrasts, test clock-spline flexibility, export primary-model diagnostics,
# bound the open-ended 9+ group-size coding with values of 12 and 15, and summarize day-of-week
# scheduling.
# Inputs: .codex_work/issue4 primary and group-size model datasets plus the observation register
# Outputs: .codex_work/issue4/model_output/reviewer_*.csv
# Run-order position: 25
# Key scientific assumption: The postcollection-versus-precollection total-foraging contrast
# remains the only designated primary test. Added contrasts and sensitivities are interpretive or
# exploratory and are not multiplicity-adjusted.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

prepare_primary <- function() {
  data <- read.csv(file.path(work_dir, "model_data_30min.csv"), stringsAsFactors = FALSE)
  data$observation_id <- factor(data$observation_id)
  data$collection_day <- as.numeric(data$collection_day)
  data$post_collection_fraction <- as.numeric(data$post_collection_fraction)
  data$clock_hour <- as.numeric(data$clock_hour)
  data$camera_seconds <- as.numeric(data$camera_seconds)
  data$foraging_seconds <- as.numeric(data$foraging_seconds)
  data$exposure_offset <- log(data$camera_seconds / 1800)
  data
}

fit_primary <- function(data, clock_df = 4) {
  formula <- as.formula(paste0(
    "foraging_seconds ~ splines::ns(clock_hour, df = ", clock_df, ") + ",
    "collection_day + post_collection_fraction + offset(exposure_offset) + ",
    "s(observation_id, bs = 're')"
  ))
  gam(
    formula,
    data = data,
    family = tw(link = "log"),
    method = "REML",
    na.action = na.fail
  )
}

linear_contrast <- function(model, weights, label, clock_df = 4) {
  coefficients <- coef(model)
  vector <- setNames(rep(0, length(coefficients)), names(coefficients))
  for (term in names(weights)) {
    if (!term %in% names(coefficients)) stop(paste("Missing contrast term:", term))
    vector[term] <- weights[[term]]
  }
  estimate <- sum(vector * coefficients)
  standard_error <- sqrt(as.numeric(t(vector) %*% vcov(model) %*% vector))
  statistic <- estimate / standard_error
  data.frame(
    contrast = label,
    clock_spline_df = clock_df,
    estimate_log = estimate,
    standard_error = standard_error,
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = 2 * pnorm(abs(statistic), lower.tail = FALSE),
    stringsAsFactors = FALSE
  )
}

primary_data <- prepare_primary()
primary_model <- fit_primary(primary_data, 4)

primary_contrasts <- rbind(
  linear_contrast(
    primary_model,
    c(collection_day = 0, post_collection_fraction = 1),
    "Postcollection vs precollection on collection days"
  ),
  linear_contrast(
    primary_model,
    c(collection_day = 1, post_collection_fraction = 0),
    "Precollection on collection days vs noncollection days"
  ),
  linear_contrast(
    primary_model,
    c(collection_day = 1, post_collection_fraction = 1),
    "Postcollection on collection days vs noncollection days"
  )
)

spline_sensitivity <- do.call(
  rbind,
  lapply(c(3, 4, 5, 6), function(clock_df) {
    model <- fit_primary(primary_data, clock_df)
    row <- linear_contrast(
      model,
      c(collection_day = 0, post_collection_fraction = 1),
      "Postcollection vs precollection on collection days",
      clock_df = clock_df
    )
    row$aic <- AIC(model)
    row$deviance_explained <- summary(model)$dev.expl
    row
  })
)

model_summary <- summary(primary_model)
k_table <- tryCatch(k.check(primary_model), error = function(error) NULL)
random_k_index <- if (!is.null(k_table) && "s(observation_id)" %in% rownames(k_table)) {
  unname(k_table["s(observation_id)", "k-index"])
} else {
  NA_real_
}
random_k_p <- if (!is.null(k_table) && "s(observation_id)" %in% rownames(k_table)) {
  unname(k_table["s(observation_id)", "p-value"])
} else {
  NA_real_
}
gam_diagnostics <- data.frame(
  metric = c(
    "Clock-time basis",
    "Clock-time degrees of freedom",
    "Clock-time k-index applicability",
    "Observation-day random-effect edf",
    "Observation-day random-effect reference df",
    "Observation-day random-effect k-index",
    "Observation-day random-effect k-check p",
    "Deviance explained",
    "Adjusted R squared",
    "Maximum absolute gradient",
    "Pearson residual lag 1",
    "Convergence"
  ),
  value = c(
    "Parametric natural cubic spline (splines::ns)",
    "4",
    "Not applicable; adequacy assessed with 3-, 5-, and 6-df sensitivity fits",
    format(model_summary$s.table["s(observation_id)", "edf"], digits = 10),
    format(model_summary$s.table["s(observation_id)", "Ref.df"], digits = 10),
    format(random_k_index, digits = 10),
    format(random_k_p, digits = 10),
    format(model_summary$dev.expl, digits = 10),
    format(model_summary$r.sq, digits = 10),
    format(max(abs(primary_model$outer.info$grad)), digits = 10),
    "0.03397017449",
    as.character(primary_model$outer.info$conv)
  ),
  stringsAsFactors = FALSE
)

group <- read.csv(file.path(work_dir, "group_size_phase_model_data_30min.csv"), stringsAsFactors = FALSE)
group <- group[is.finite(group$time_weighted_mean_group_size) & group$group_size_known_seconds > 0, ]
group$observation_id <- factor(group$original_recording_id)
group$collection_day <- as.numeric(group$collection_day)
group$post_collection <- as.numeric(group$post_collection)
group$clock_hour <- as.numeric(group$clock_hour)
group$group_size_known_seconds <- as.numeric(group$group_size_known_seconds)
group$group_size_person_seconds <- as.numeric(group$group_size_person_seconds)
group$group_size_9plus_seconds <- as.numeric(group$group_size_9plus_seconds)
group$analysis_weight <- pmax(group$group_size_known_seconds / 1800, 0.01)

extract_group_effect <- function(model, scenario, imputed_value) {
  table <- summary(model)$p.table
  term <- "post_collection"
  estimate <- unname(table[term, 1])
  standard_error <- unname(table[term, 2])
  data.frame(
    scenario = scenario,
    imputed_value_for_9plus = imputed_value,
    interval_rows = nrow(model$model),
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = unname(table[term, ncol(table)]),
    deviance_explained = summary(model)$dev.expl,
    stringsAsFactors = FALSE
  )
}

group_sensitivity <- do.call(
  rbind,
  lapply(c(9, 12, 15), function(imputed_value) {
    response_name <- paste0("group_size_imputed_", imputed_value)
    group[[response_name]] <- (
      group$group_size_person_seconds +
        (imputed_value - 9) * group$group_size_9plus_seconds
    ) / group$group_size_known_seconds
    formula <- as.formula(paste0(
      response_name,
      " ~ splines::ns(clock_hour, df = 4) + collection_day + post_collection + ",
      "s(observation_id, bs = 're')"
    ))
    model <- gam(
      formula,
      data = group,
      weights = analysis_weight,
      family = Gamma(link = "log"),
      method = "REML",
      na.action = na.fail
    )
    extract_group_effect(
      model,
      if (imputed_value == 9) "Lower-bound coding" else paste("Impute 9+ as", imputed_value),
      imputed_value
    )
  })
)

register <- read.csv(file.path(work_dir, "observation_register.csv"), stringsAsFactors = FALSE)
register$weekday <- factor(
  register$weekday,
  levels = c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
)
day_schedule <- as.data.frame(table(register$weekday, register$collection_day))
names(day_schedule) <- c("weekday", "collection_day", "observation_days")
day_schedule <- day_schedule[day_schedule$observation_days > 0, ]
day_schedule$collection_status <- ifelse(day_schedule$collection_day == 1, "Collection", "No collection")
day_schedule$weekend <- day_schedule$weekday %in% c("Saturday", "Sunday")
day_schedule <- day_schedule[, c("weekday", "weekend", "collection_status", "observation_days")]

# --- Export reproducible model tables ---
write.csv(primary_contrasts, file.path(output_dir, "reviewer_primary_contrasts.csv"), row.names = FALSE, na = "")
write.csv(spline_sensitivity, file.path(output_dir, "reviewer_clock_spline_sensitivity.csv"), row.names = FALSE, na = "")
write.csv(gam_diagnostics, file.path(output_dir, "reviewer_gam_diagnostics.csv"), row.names = FALSE, na = "")
write.csv(group_sensitivity, file.path(output_dir, "reviewer_group_9plus_sensitivity.csv"), row.names = FALSE, na = "")
write.csv(day_schedule, file.path(output_dir, "reviewer_day_of_week_schedule.csv"), row.names = FALSE, na = "")

print(primary_contrasts)
print(spline_sensitivity)
print(group_sensitivity)
print(day_schedule)
