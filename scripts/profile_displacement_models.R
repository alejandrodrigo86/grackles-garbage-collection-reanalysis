# ================================================================================================
# Script: profile_displacement_models.R
# Pipeline stage: 4. Agonistic displacement analysis
# Analytical purpose: Compare plausible count families for visible displacement events and
# document zero frequency, dispersion, likelihood, and information criteria.
# Inputs: .codex_work/issue4/displacement_data_30min.csv
# Outputs: .codex_work/issue4/model_output/displacement_family_profile.csv
# Run-order position: 13
# Key scientific assumption: Family selection is driven by observed count properties and
# diagnostics, not by which family produces a preferred significance result.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(splines))

# --- Project paths and input preparation ---
work_dir <- file.path(getwd(), ".codex_work", "issue4")
data <- read.csv(file.path(work_dir, "displacement_data_30min.csv"), stringsAsFactors = FALSE)
data <- data[data$focal_visible_seconds > 0, ]
data <- data[order(data$observation_date, data$observation_id, data$bin_number, data$segment_number), ]
data$observation_id <- factor(data$observation_id)
data$collection_day <- as.numeric(data$collection_day)
data$post_collection <- as.numeric(data$post_collection)
data$visible_offset <- log(data$focal_visible_seconds / 1800)

form <- visible_displacement_events ~ ns(clock_hour, df = 4) + collection_day + post_collection +
  offset(visible_offset) + s(observation_id, bs = "re")

poisson_fit <- gam(form, data = data, family = poisson(link = "log"), method = "REML")
nb_fit <- gam(form, data = data, family = nb(link = "log"), method = "REML")

lag1_by_day <- function(fit, data) {
  residuals <- residuals(fit, type = "pearson")
  pairs <- lapply(split(seq_len(nrow(data)), data$observation_id), function(index) {
    if (length(index) < 2) return(NULL)
    cbind(residuals[index[-length(index)]], residuals[index[-1]])
  })
  pairs <- do.call(rbind, pairs)
  if (is.null(pairs) || nrow(pairs) < 2) return(NA_real_)
  cor(pairs[, 1], pairs[, 2], use = "complete.obs")
}

model_row <- function(name, fit) {
  mu <- fitted(fit)
  theta <- if (grepl("Negative Binomial", family(fit)$family)) fit$family$getTheta(TRUE) else NA_real_
  expected_zeros <- if (is.finite(theta) && theta > 0) {
    sum((theta / (theta + mu))^theta)
  } else {
    sum(exp(-mu))
  }
  pearson <- residuals(fit, type = "pearson")
  p_table <- summary(fit)$p.table
  coefficient <- p_table["post_collection", "Estimate"]
  se <- p_table["post_collection", "Std. Error"]
  data.frame(
    model = name,
    rows = nrow(data),
    events = sum(data$visible_displacement_events),
    zero_rows = sum(data$visible_displacement_events == 0),
    variance_to_mean = var(data$visible_displacement_events) / mean(data$visible_displacement_events),
    aic = AIC(fit),
    pearson_dispersion = sum(pearson^2, na.rm = TRUE) / df.residual(fit),
    observed_zeros = sum(data$visible_displacement_events == 0),
    expected_zeros = expected_zeros,
    post_rate_ratio = exp(coefficient),
    ci_low = exp(coefficient - 1.96 * se),
    ci_high = exp(coefficient + 1.96 * se),
    p_value = p_table["post_collection", "Pr(>|z|)"],
    residual_lag1 = lag1_by_day(fit, data),
    deviance_explained = summary(fit)$dev.expl,
    full_convergence = isTRUE(fit$outer.info$conv == "full convergence"),
    max_gradient = max(abs(fit$outer.info$grad)),
    positive_hessian = all(eigen(fit$outer.info$hess, symmetric = TRUE, only.values = TRUE)$values > 0),
    theta = theta
  )
}

profile <- rbind(model_row("Poisson", poisson_fit), model_row("Negative binomial", nb_fit))
# --- Export reproducible model tables ---
write.csv(profile, file.path(work_dir, "model_output", "displacement_family_profile.csv"), row.names = FALSE)
capture.output(summary(poisson_fit), file = file.path(work_dir, "model_output", "displacement_poisson_summary.txt"))
capture.output(summary(nb_fit), file = file.path(work_dir, "model_output", "displacement_nb_summary.txt"))
print(profile)
