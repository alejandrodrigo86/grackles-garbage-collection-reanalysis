# ================================================================================================
# Script: fit_displacement_models.R
# Pipeline stage: 4. Agonistic displacement analysis
# Analytical purpose: Fit camera-exposure, focal-visible-exposure, and directional displacement
# models; produce phase summaries and model diagnostics.
# Inputs: .codex_work/issue4/displacement_data_30min.csv
# Outputs: .codex_work/issue4/model_output/displacement_model_estimates.csv;
# displacement_directional_models.csv; displacement_phase_summary.csv
# Run-order position: 14
# Key scientific assumption: Greater event counts may reflect greater observation or bird-presence
# opportunity, so camera-time and focal-visible-time exposure formulations are separated.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(splines))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
output_dir <- file.path(work_dir, "model_output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

read_displacement_data <- function(filename, nominal_seconds) {
  data <- read.csv(file.path(work_dir, filename), stringsAsFactors = FALSE)
  data <- data[order(data$observation_date, data$observation_id, data$bin_number, data$segment_number), ]
  data$observation_id <- factor(data$observation_id)
  data$observer <- factor(data$observer)
  data$collection_day <- as.numeric(data$collection_day)
  data$post_collection <- as.numeric(data$post_collection)
  data$clock_hour <- as.numeric(data$clock_hour)
  data$segment_seconds <- as.numeric(data$segment_seconds)
  data$focal_visible_seconds <- as.numeric(data$focal_visible_seconds)
  data$foraging_seconds <- as.numeric(data$foraging_seconds)
  data$camera_offset <- log(data$segment_seconds / nominal_seconds)
  data$visible_offset <- ifelse(
    data$focal_visible_seconds > 0,
    log(data$focal_visible_seconds / nominal_seconds),
    NA_real_
  )
  data$foraging_offset <- ifelse(
    data$foraging_seconds > 0,
    log(data$foraging_seconds / nominal_seconds),
    NA_real_
  )
  data$directed_events <- data$visible_displacement_focal_to_others +
    data$visible_displacement_others_to_focal
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

count_formula <- function(response, offset_name, include_observer = FALSE) {
  observer_term <- if (include_observer) " + observer" else ""
  as.formula(paste0(
    response,
    " ~ ns(clock_hour, df = 4) + collection_day + post_collection",
    observer_term,
    " + offset(", offset_name, ") + s(observation_id, bs = 're')"
  ))
}

fit_count <- function(data, response, offset_name, include_observer = FALSE, family = nb(link = "log")) {
  gam(
    count_formula(response, offset_name, include_observer),
    data = data,
    family = family,
    method = "REML",
    na.action = na.fail
  )
}

model_convergence <- function(model) {
  if (!is.null(model$outer.info$conv)) return(as.character(model$outer.info$conv))
  if (!is.null(model$converged)) return(as.character(model$converged))
  "not reported"
}

positive_hessian <- function(model) {
  if (is.null(model$outer.info$hess)) return(NA)
  all(eigen(model$outer.info$hess, symmetric = TRUE, only.values = TRUE)$values > 0)
}

extract_count_effect <- function(model, data, analysis, response, exposure, bin_minutes, notes = "") {
  model_summary <- summary(model)
  coefficient_table <- model_summary$p.table
  term <- "post_collection"
  estimate <- unname(coefficient_table[term, 1])
  standard_error <- unname(coefficient_table[term, 2])
  p_value <- unname(coefficient_table[term, ncol(coefficient_table)])
  theta <- tryCatch(model$family$getTheta(TRUE), error = function(error) NA_real_)
  if (length(theta) > 1) theta <- theta[1]
  mu <- fitted(model)
  expected_zeros <- if (is.finite(theta) && theta > 0) {
    sum((theta / (theta + mu))^theta)
  } else {
    sum(exp(-mu))
  }
  pearson <- residuals(model, type = "pearson")
  day_row <- grep("s\\(observation_id\\)", rownames(model_summary$s.table), value = TRUE)
  day_edf <- if (length(day_row)) unname(model_summary$s.table[day_row[1], "edf"]) else NA_real_
  day_p <- if (length(day_row)) unname(model_summary$s.table[day_row[1], ncol(model_summary$s.table)]) else NA_real_
  data.frame(
    analysis = analysis,
    response = response,
    exposure = exposure,
    family = model$family$family,
    bin_minutes = bin_minutes,
    interval_rows = nrow(data),
    observation_days = nlevels(droplevels(data$observation_id)),
    events = sum(data[[response]]),
    estimate_log = estimate,
    standard_error = standard_error,
    effect_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = p_value,
    aic = AIC(model),
    deviance_explained = model_summary$dev.expl,
    pearson_dispersion = sum(pearson^2, na.rm = TRUE) / df.residual(model),
    observed_zeros = sum(data[[response]] == 0),
    expected_zeros = expected_zeros,
    residual_lag1 = lag1_by_day(pearson, data),
    theta = theta,
    day_random_effect_edf = day_edf,
    day_random_effect_p = day_p,
    convergence = model_convergence(model),
    max_gradient = if (!is.null(model$outer.info$grad)) max(abs(model$outer.info$grad)) else NA_real_,
    positive_hessian = positive_hessian(model),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

fit_directional <- function(data, outcome_left, outcome_right, label) {
  analysis_data <- data[data[[outcome_left]] + data[[outcome_right]] > 0, ]
  analysis_data <- droplevels(analysis_data)
  formula <- as.formula(paste0(
    "cbind(", outcome_left, ", ", outcome_right, ")",
    " ~ ns(clock_hour, df = 4) + collection_day + post_collection + ",
    "s(observation_id, bs = 're')"
  ))
  model <- gam(
    formula,
    data = analysis_data,
    family = quasibinomial(link = "logit"),
    method = "REML",
    na.action = na.fail
  )
  model_summary <- summary(model)
  table <- model_summary$p.table
  estimate <- unname(table["post_collection", 1])
  standard_error <- unname(table["post_collection", 2])
  result <- data.frame(
    analysis = label,
    numerator = outcome_left,
    denominator_component = outcome_right,
    interval_rows = nrow(analysis_data),
    events = sum(analysis_data[[outcome_left]] + analysis_data[[outcome_right]]),
    numerator_events = sum(analysis_data[[outcome_left]]),
    denominator_events = sum(analysis_data[[outcome_right]]),
    estimate_log_odds = estimate,
    standard_error = standard_error,
    odds_ratio = exp(estimate),
    ci_low = exp(estimate - qnorm(0.975) * standard_error),
    ci_high = exp(estimate + qnorm(0.975) * standard_error),
    p_value = unname(table["post_collection", ncol(table)]),
    dispersion = model_summary$dispersion,
    deviance_explained = model_summary$dev.expl,
    convergence = model_convergence(model),
    max_gradient = if (!is.null(model$outer.info$grad)) max(abs(model$outer.info$grad)) else NA_real_,
    positive_hessian = positive_hessian(model),
    stringsAsFactors = FALSE
  )
  list(model = model, data = analysis_data, result = result)
}

data_30_all <- read_displacement_data("displacement_data_30min.csv", 1800)
data_15_all <- read_displacement_data("displacement_data_15min.csv", 900)
data_60_all <- read_displacement_data("displacement_data_60min.csv", 3600)
data_30 <- droplevels(data_30_all[data_30_all$focal_visible_seconds > 0, ])
data_15 <- droplevels(data_15_all[data_15_all$focal_visible_seconds > 0, ])
data_60 <- droplevels(data_60_all[data_60_all$focal_visible_seconds > 0, ])

camera_model <- fit_count(data_30_all, "displacement_events", "camera_offset")
primary_model <- fit_count(data_30, "visible_displacement_events", "visible_offset")
outgoing_model <- fit_count(data_30, "visible_displacement_focal_to_others", "visible_offset")
incoming_model <- fit_count(data_30, "visible_displacement_others_to_focal", "visible_offset")
unspecified_model <- fit_count(data_30, "visible_displacement_unspecified", "visible_offset")
foraging_data <- droplevels(data_30[data_30$foraging_seconds > 0, ])
foraging_exposure_model <- fit_count(
  foraging_data, "foraging_displacement_events", "foraging_offset"
)

results <- rbind(
  extract_count_effect(
    camera_model, data_30_all, "Total displacement per camera exposure",
    "displacement_events", "camera time", 30,
    "Descriptive total-activity model; includes all 139 recorded events"
  ),
  extract_count_effect(
    primary_model, data_30, "Opportunity-adjusted displacement rate",
    "visible_displacement_events", "focal-visible time", 30,
    "Primary aggression test; excludes one unspecified event outside coded focal visibility"
  ),
  extract_count_effect(
    outgoing_model, data_30, "Focal-to-others displacement rate",
    "visible_displacement_focal_to_others", "focal-visible time", 30,
    "Exploratory direction-specific rate"
  ),
  extract_count_effect(
    incoming_model, data_30, "Others-to-focal displacement rate",
    "visible_displacement_others_to_focal", "focal-visible time", 30,
    "Exploratory direction-specific rate"
  ),
  extract_count_effect(
    unspecified_model, data_30, "Unspecified-direction displacement rate",
    "visible_displacement_unspecified", "focal-visible time", 30,
    "Exploratory missing-direction rate"
  ),
  extract_count_effect(
    foraging_exposure_model, foraging_data, "Displacement rate during foraging",
    "foraging_displacement_events", "coded foraging time", 30,
    "Exposure sensitivity restricted to displacement events occurring during foraging"
  )
)

without_n3 <- droplevels(data_30[data_30$observation_id != "N3", ])
model_without_n3 <- fit_count(without_n3, "visible_displacement_events", "visible_offset")
results <- rbind(
  results,
  extract_count_effect(
    model_without_n3, without_n3, "Opportunity-adjusted excluding N3",
    "visible_displacement_events", "focal-visible time", 30,
    "Leverage sensitivity"
  )
)

model_15 <- fit_count(data_15, "visible_displacement_events", "visible_offset")
model_60 <- fit_count(data_60, "visible_displacement_events", "visible_offset")
results <- rbind(
  results,
  extract_count_effect(
    model_15, data_15, "Opportunity-adjusted 15-minute sensitivity",
    "visible_displacement_events", "focal-visible time", 15,
    "Aggregation sensitivity"
  ),
  extract_count_effect(
    model_60, data_60, "Opportunity-adjusted 60-minute sensitivity",
    "visible_displacement_events", "focal-visible time", 60,
    "Aggregation sensitivity"
  )
)

observer_model <- fit_count(
  data_30, "visible_displacement_events", "visible_offset", include_observer = TRUE
)
poisson_model <- fit_count(
  data_30, "visible_displacement_events", "visible_offset", family = quasipoisson(link = "log")
)
results <- rbind(
  results,
  extract_count_effect(
    observer_model, data_30, "Opportunity-adjusted plus observer",
    "visible_displacement_events", "focal-visible time", 30,
    "Observer fixed-effect sensitivity"
  ),
  extract_count_effect(
    poisson_model, data_30, "Opportunity-adjusted quasi-Poisson sensitivity",
    "visible_displacement_events", "focal-visible time", 30,
    "Variance-robust count-family sensitivity"
  )
)

collection_data <- data_30[data_30$collection_day == 1, ]
pre_data <- collection_data[collection_data$post_collection == 0, ]
post_data <- collection_data[collection_data$post_collection == 1, ]

direction_matrix <- matrix(
  c(
    sum(post_data$visible_displacement_focal_to_others),
    sum(post_data$visible_displacement_others_to_focal),
    sum(pre_data$visible_displacement_focal_to_others),
    sum(pre_data$visible_displacement_others_to_focal)
  ),
  nrow = 2,
  byrow = TRUE,
  dimnames = list(c("Post", "Pre"), c("Focal_to_others", "Others_to_focal"))
)
direction_fisher <- fisher.test(direction_matrix)

specified_matrix <- matrix(
  c(
    sum(post_data$directed_events),
    sum(post_data$visible_displacement_unspecified),
    sum(pre_data$directed_events),
    sum(pre_data$visible_displacement_unspecified)
  ),
  nrow = 2,
  byrow = TRUE,
  dimnames = list(c("Post", "Pre"), c("Directed", "Unspecified"))
)
specified_fisher <- fisher.test(specified_matrix)

directional_results <- rbind(
  data.frame(
    analysis = "Direction among directed events: post versus pre",
    post_first = direction_matrix["Post", "Focal_to_others"],
    post_second = direction_matrix["Post", "Others_to_focal"],
    pre_first = direction_matrix["Pre", "Focal_to_others"],
    pre_second = direction_matrix["Pre", "Others_to_focal"],
    odds_ratio = unname(direction_fisher$estimate),
    ci_low = direction_fisher$conf.int[1],
    ci_high = direction_fisher$conf.int[2],
    p_value = direction_fisher$p.value,
    interpretation = "Odds that a directed event was focal-to-others rather than others-to-focal",
    stringsAsFactors = FALSE
  ),
  data.frame(
    analysis = "Direction coding completeness: post versus pre",
    post_first = specified_matrix["Post", "Directed"],
    post_second = specified_matrix["Post", "Unspecified"],
    pre_first = specified_matrix["Pre", "Directed"],
    pre_second = specified_matrix["Pre", "Unspecified"],
    odds_ratio = unname(specified_fisher$estimate),
    ci_low = specified_fisher$conf.int[1],
    ci_high = specified_fisher$conf.int[2],
    p_value = specified_fisher$p.value,
    interpretation = "Odds that a displacement event had a recorded direction",
    stringsAsFactors = FALSE
  )
)

data_30$phase <- ifelse(
  data_30$collection_day == 0,
  "Non-collection",
  ifelse(data_30$post_collection == 1, "Collection day: post", "Collection day: pre")
)
phase_levels <- c("Non-collection", "Collection day: pre", "Collection day: post")
phase_summary <- do.call(rbind, lapply(phase_levels, function(phase) {
  group <- data_30[data_30$phase == phase, ]
  exposure_hours <- sum(group$focal_visible_seconds) / 3600
  data.frame(
    phase = phase,
    interval_rows = nrow(group),
    observation_days = length(unique(group$observation_id)),
    focal_visible_hours = exposure_hours,
    foraging_hours = sum(group$foraging_seconds) / 3600,
    displacement_events = sum(group$visible_displacement_events),
    events_per_visible_hour = sum(group$visible_displacement_events) / exposure_hours,
    displacement_events_during_foraging = sum(group$foraging_displacement_events),
    events_per_foraging_hour = sum(group$foraging_displacement_events) /
      (sum(group$foraging_seconds) / 3600),
    focal_to_others = sum(group$visible_displacement_focal_to_others),
    others_to_focal = sum(group$visible_displacement_others_to_focal),
    unspecified = sum(group$visible_displacement_unspecified),
    stringsAsFactors = FALSE
  )
}))

# --- Export reproducible model tables ---
write.csv(results, file.path(output_dir, "displacement_model_estimates.csv"), row.names = FALSE, na = "")
write.csv(directional_results, file.path(output_dir, "displacement_directional_models.csv"), row.names = FALSE, na = "")
write.csv(phase_summary, file.path(output_dir, "displacement_phase_summary.csv"), row.names = FALSE, na = "")
capture.output(summary(camera_model), file = file.path(output_dir, "displacement_camera_model_summary.txt"))
capture.output(summary(primary_model), file = file.path(output_dir, "displacement_primary_model_summary.txt"))
capture.output(gam.check(primary_model), file = file.path(output_dir, "displacement_primary_gam_check.txt"))

print(results)
print(directional_results)
print(phase_summary)
