# ================================================================================================
# Script: build_publication_figures.R
# Pipeline stage: 6. Figures and reporting
# Analytical purpose: Create the publication figures from model predictions and reconstructed data
# using an accessible, redundant visual encoding system.
# Inputs: .codex_work/issue4 model outputs and reconstructed interval/displacement data
# Outputs: outputs/.../figures/*.png, *.tiff, and supporting figure-data CSV files
# Run-order position: 27
# Key scientific assumption: Colour never carries meaning alone: line style, position, shape, and
# direct labels provide redundant encodings.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

options(stringsAsFactors = FALSE, scipen = 6)

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
work <- file.path(root, ".codex_work", "issue4")
model_dir <- file.path(work, "model_output")
out_dir <- file.path(
  root, "outputs", "019fb5b5-949c-74f1-ac2a-18b1d5a808c5", "Versions",
  "V4_Readability_Revision", "Figures", "Figures_V4"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Okabe-Ito-derived palette. Meaning is also encoded with line style, shape,
# position, and direct labels so no conclusion depends on colour alone.
ink <- "#202124"
muted <- "#68717D"
grid_col <- "#D8DEE6"
blue <- "#0072B2"
orange <- "#D55E00"
green <- "#009E73"
purple <- "#A6538A"
sky <- "#56B4E9"
paper <- "#FFFFFF"

num <- function(x) as.numeric(x)
alpha <- function(col, a) grDevices::adjustcolor(col, alpha.f = a)

read_numeric <- function(path, columns) {
  x <- read.csv(path, check.names = FALSE)
  for (column in intersect(columns, names(x))) x[[column]] <- num(x[[column]])
  x
}

pred <- read_numeric(
  file.path(model_dir, "primary_predictions.csv"),
  c("clock_hour", "expected_foraging_seconds_per_30_min", "ci_low", "ci_high")
)
segments30 <- read_numeric(
  file.path(work, "displacement_data_30min.csv"),
  c(
    "collection_day", "post_collection", "clock_hour", "post_collection_hours",
    "segment_seconds", "foraging_seconds", "focal_visible_seconds"
  )
)
collection_times <- read_numeric(
  file.path(model_dir, "collection_clock_times.csv"),
  "collection_clock_hour"
)
model_est <- read_numeric(
  file.path(model_dir, "model_estimates.csv"),
  c("rate_ratio", "ci_low", "ci_high", "p_value")
)
decomp_est <- read_numeric(
  file.path(model_dir, "decomposition_estimates.csv"),
  c("effect_ratio", "ci_low", "ci_high", "p_value")
)
disp_est <- read_numeric(
  file.path(model_dir, "displacement_model_estimates.csv"),
  c("effect_ratio", "ci_low", "ci_high", "p_value")
)
competitor_disp_est <- read_numeric(
  file.path(model_dir, "competitor_displacement_estimates.csv"),
  c("effect_ratio", "ci_low", "ci_high", "p_value")
)
group_est <- read_numeric(
  file.path(model_dir, "group_size_model_estimates.csv"),
  c("effect_ratio", "ci_low", "ci_high", "p_value")
)
group_pred <- read_numeric(
  file.path(model_dir, "group_size_predictions.csv"),
  c("clock_hour", "estimate", "ci_low", "ci_high")
)
group_paired <- read_numeric(
  file.path(model_dir, "group_size_paired_days.csv"),
  c(
    "observation_number", "pre_time_weighted_mean_group_size",
    "post_time_weighted_mean_group_size", "mean_group_size_difference"
  )
)
observation_register <- read_numeric(
  file.path(work, "observation_register.csv"),
  c("observation_number", "collection_day")
)
decay_est <- read_numeric(
  file.path(model_dir, "time_decay_model_estimates.csv"),
  c("estimate_log", "standard_error", "effect_ratio", "ci_low", "ci_high", "p_value")
)
decay_contrasts <- read_numeric(
  file.path(model_dir, "time_decay_linear_contrasts.csv"),
  c("hours_after_collection", "effect_ratio", "ci_low", "ci_high", "standard_error")
)
loo_primary <- read_numeric(
  file.path(model_dir, "primary_leave_one_day_out.csv"),
  c("omitted_collection_day", "rate_ratio", "ci_low", "ci_high")
)
loo_decay <- read_numeric(
  file.path(model_dir, "time_decay_leave_one_day_out.csv"),
  c("excluded_collection_day", "hourly_rate_ratio", "immediate_rate_ratio")
)

stopifnot(
  nrow(pred) == 480,
  length(unique(segments30$observation_id)) == 25,
  nrow(collection_times) == 12,
  nrow(loo_primary) == 25,
  nrow(loo_decay) == 25,
  nrow(group_paired) == 11
)

set_plot_style <- function(mar = c(4.2, 4.8, 2.4, 1.0)) {
  par(
    mar = mar, mgp = c(2.45, 0.72, 0), tcl = -0.24, las = 1,
    family = "sans", fg = ink, col.axis = ink, col.lab = ink,
    cex.axis = 0.86, cex.lab = 0.96, cex.main = 1.02,
    font.main = 2, bty = "l", lend = "round", ljoin = "round",
    xaxs = "i", yaxs = "i"
  )
}

horizontal_grid <- function(at) {
  abline(h = at, col = grid_col, lwd = 0.75)
}

panel_title <- function(letter, title) {
  title(main = paste0(letter, "  ", title), adj = 0, line = 0.55)
}

draw_ribbon <- function(x, low, high, fill) {
  polygon(c(x, rev(x)), c(low, rev(high)), border = NA, col = fill)
}

export_figure <- function(stem, width, height, draw) {
  png_path <- file.path(out_dir, paste0(stem, ".png"))
  pdf_path <- file.path(out_dir, paste0(stem, ".pdf"))
  svg_path <- file.path(out_dir, paste0(stem, ".svg"))

  grDevices::png(
    png_path, width = width, height = height, units = "in", res = 600,
    pointsize = 11, bg = paper, type = "cairo"
  )
  draw()
  invisible(dev.off())

  grDevices::pdf(
    pdf_path, width = width, height = height, pointsize = 11,
    family = "Helvetica", bg = paper, useDingbats = FALSE, version = "1.4"
  )
  draw()
  invisible(dev.off())

  grDevices::svg(
    svg_path, width = width, height = height, pointsize = 11,
    family = "sans", bg = paper
  )
  draw()
  invisible(dev.off())

  c(png_path, pdf_path, svg_path)
}

scenario_curve <- function(name, lower = -Inf, upper = Inf) {
  x <- pred[pred$scenario == name & pred$clock_hour >= lower & pred$clock_hour <= upper, ]
  x[order(x$clock_hour), ]
}

non_collection <- scenario_curve("Non-collection baseline")
collection_pre <- scenario_curve(
  "Collection day before end", upper = max(collection_times$collection_clock_hour)
)
collection_post <- scenario_curve(
  "Collection day after end", lower = min(collection_times$collection_clock_hour)
)

collection_rows <- segments30[segments30$collection_day == 1, ]
daily_phase <- aggregate(
  cbind(segment_seconds, foraging_seconds) ~ observation_id + post_collection,
  data = collection_rows,
  FUN = sum
)
daily_phase$rate <- daily_phase$foraging_seconds / daily_phase$segment_seconds * 3600
daily_pre <- daily_phase[daily_phase$post_collection == 0, c("observation_id", "segment_seconds", "rate")]
daily_post <- daily_phase[daily_phase$post_collection == 1, c("observation_id", "segment_seconds", "rate")]
names(daily_pre)[2:3] <- c("pre_seconds", "pre_rate")
names(daily_post)[2:3] <- c("post_seconds", "post_rate")
daily_pair <- merge(daily_pre, daily_post, by = "observation_id", all = TRUE)
daily_pair <- merge(
  daily_pair,
  observation_register[, c("original_recording_id", "observation_number", "observation_label")],
  by.x = "observation_id", by.y = "original_recording_id", all.x = TRUE
)
daily_pair <- daily_pair[order(daily_pair$observation_number), ]
stopifnot(nrow(daily_pair) == 12)

draw_figure_1 <- function() {
  layout(matrix(c(1, 2), ncol = 1), heights = c(1.25, 1.0))

  set_plot_style(c(4.1, 4.7, 2.5, 1.0))
  y_ticks <- seq(0, 400, 100)
  plot(
    NA, xlim = c(6.75, 20.75), ylim = c(0, 410), axes = FALSE,
    xlab = "Local time", ylab = "Expected foraging seconds per 30 min"
  )
  horizontal_grid(y_ticks)
  axis(1, at = seq(7, 20, 2), labels = sprintf("%02d:00", seq(7, 20, 2)))
  axis(2, at = y_ticks)

  draw_ribbon(
    non_collection$clock_hour, non_collection$ci_low, non_collection$ci_high,
    alpha(muted, 0.10)
  )
  draw_ribbon(
    collection_pre$clock_hour, collection_pre$ci_low, collection_pre$ci_high,
    alpha(blue, 0.10)
  )
  draw_ribbon(
    collection_post$clock_hour, collection_post$ci_low, collection_post$ci_high,
    alpha(orange, 0.13)
  )

  lines(
    non_collection$clock_hour, non_collection$expected_foraging_seconds_per_30_min,
    col = muted, lwd = 2.1, lty = 3
  )
  lines(
    collection_pre$clock_hour, collection_pre$expected_foraging_seconds_per_30_min,
    col = blue, lwd = 2.4, lty = 5
  )
  lines(
    collection_post$clock_hour, collection_post$expected_foraging_seconds_per_30_min,
    col = orange, lwd = 2.6, lty = 1
  )

  # Collection-end times are shown as a rug, retaining their actual spread.
  segments(
    collection_times$collection_clock_hour, 392,
    collection_times$collection_clock_hour, 408,
    col = ink, lwd = 1.0
  )
  text(13.95, 405, "Observed collection end", adj = c(0, 1), cex = 0.76, col = muted)

  legend(
    "topright",
    legend = c("After collection", "Before collection", "Non-collection day"),
    col = c(orange, blue, muted), lty = c(1, 5, 3), lwd = c(2.6, 2.4, 2.1),
    bty = "n", cex = 0.82, seg.len = 2.6, inset = c(0.01, 0.05)
  )
  text(
    6.95, 18,
    "Curves are model-adjusted; translucent bands are 95% confidence intervals.",
    adj = c(0, 0), cex = 0.76, col = muted
  )
  panel_title("A", "Adjusted foraging activity through the day")

  set_plot_style(c(4.2, 4.7, 2.5, 1.0))
  y_ticks <- seq(0, 750, 150)
  plot(
    NA, xlim = c(0.72, 2.28), ylim = c(0, 760), axes = FALSE,
    xlab = "Collection phase", ylab = "Observed foraging seconds per camera hour"
  )
  horizontal_grid(y_ticks)
  axis(1, at = c(1, 2), labels = c("Before collection", "After collection"))
  axis(2, at = y_ticks)

  offsets <- seq(-0.045, 0.045, length.out = nrow(daily_pair))
  for (i in seq_len(nrow(daily_pair))) {
    is_n3 <- daily_pair$observation_number[i] == 2
    segments(
      1 + offsets[i], daily_pair$pre_rate[i],
      2 + offsets[i], daily_pair$post_rate[i],
      col = if (is_n3) alpha(ink, 0.72) else alpha(muted, 0.43),
      lwd = if (is_n3) 1.25 else 1.0,
      lty = if (is_n3) 2 else 1
    )
  }
  points(1 + offsets, daily_pair$pre_rate, pch = 21, bg = paper, col = blue, lwd = 1.5, cex = 1.05)
  points(2 + offsets, daily_pair$post_rate, pch = 24, bg = orange, col = orange, lwd = 1.2, cex = 1.08)

  n3 <- which(daily_pair$observation_number == 2)
  text(
    1 + offsets[n3] + 0.035, daily_pair$pre_rate[n3] + 32,
    "Observation 2: 3.3 min pre exposure", adj = c(0, 0), cex = 0.74, col = ink
  )
  text(
    0.76, 733,
    "Descriptive, unadjusted rates; each line represents one collection day.",
    adj = c(0, 1), cex = 0.76, col = muted
  )
  legend(
    "topleft", legend = c("Before", "After"), pch = c(21, 24),
    pt.bg = c(paper, orange), col = c(blue, orange),
    pt.cex = 1.0, bty = "n", cex = 0.8, horiz = TRUE, inset = c(0.0, 0.07)
  )
  panel_title("B", "Variation among the 12 collection days")
}

# Reconstruct the event-centred confidence band from the fitted intercept,
# hourly slope, and their covariance. The published contrast standard errors
# exactly identify the covariance and reproduce all five saved contrasts.
decay_slope <- decay_est[decay_est$analysis == "Linear post-collection decay", ]
decay_level <- decay_est[decay_est$analysis == "Immediate post-collection level", ]
stopifnot(nrow(decay_slope) == 1, nrow(decay_level) == 1)
var_a <- decay_level$standard_error^2
var_b <- decay_slope$standard_error^2
se_at_one <- decay_contrasts$standard_error[decay_contrasts$hours_after_collection == 1]
cov_ab <- (se_at_one^2 - var_a - var_b) / 2
decay_x <- seq(0, 6, length.out = 241)
decay_log <- decay_level$estimate_log + decay_slope$estimate_log * decay_x
decay_se <- sqrt(var_a + decay_x^2 * var_b + 2 * decay_x * cov_ab)
decay_curve <- data.frame(
  hour = decay_x,
  ratio = exp(decay_log),
  low = exp(decay_log - 1.96 * decay_se),
  high = exp(decay_log + 1.96 * decay_se)
)
crossing_hour <- -decay_level$estimate_log / decay_slope$estimate_log

# Exact exposure in one-hour bins, split at each bin boundary.
post_rows <- segments30[segments30$post_collection == 1 & !is.na(segments30$post_collection_hours), ]
post_rows$start_hour <- pmax(0, post_rows$post_collection_hours - post_rows$segment_seconds / 7200)
post_rows$end_hour <- post_rows$post_collection_hours + post_rows$segment_seconds / 7200
exposure <- data.frame(bin = 0:5, camera_hours = 0, days = 0)
for (i in seq_len(nrow(exposure))) {
  lower <- exposure$bin[i]
  upper <- lower + 1
  overlap <- pmax(0, pmin(post_rows$end_hour, upper) - pmax(post_rows$start_hour, lower))
  exposure$camera_hours[i] <- sum(overlap)
  exposure$days[i] <- length(unique(post_rows$observation_id[overlap > 0]))
}

draw_figure_2 <- function() {
  layout(matrix(c(1, 2), ncol = 1), heights = c(1.65, 0.75))

  set_plot_style(c(4.0, 4.7, 2.5, 1.0))
  y_ticks <- c(0.4, 0.5, 0.75, 1, 1.5, 2, 3)
  plot(
    NA, xlim = c(0, 6), ylim = c(0.35, 3.45), log = "y", axes = FALSE,
    xlab = "Hours since garbage collection ended",
    ylab = "Adjusted foraging rate ratio"
  )
  horizontal_grid(y_ticks)
  axis(1, at = 0:6)
  axis(2, at = y_ticks, labels = y_ticks)
  abline(h = 1, col = ink, lty = 3, lwd = 1.1)

  draw_ribbon(decay_curve$hour, decay_curve$low, decay_curve$high, alpha(orange, 0.16))
  lines(decay_curve$hour, decay_curve$ratio, col = orange, lwd = 2.8)
  points(
    decay_contrasts$hours_after_collection,
    decay_contrasts$effect_ratio,
    pch = 21, bg = paper, col = orange, lwd = 1.6, cex = 1.0
  )

  segments(crossing_hour, 0.37, crossing_hour, 1, col = muted, lty = 2, lwd = 1.0)
  points(crossing_hour, 1, pch = 21, bg = paper, col = ink, lwd = 1.2, cex = 0.9)
  text(
    crossing_hour + 0.10, 0.45,
    sprintf("Ratio reaches 1 at %.1f h", crossing_hour),
    adj = c(0, 0.5), cex = 0.75, col = muted
  )

  text(
    0.10, 3.20, "At collection end: 1.93 [1.20-3.11]",
    adj = c(0, 1), cex = 0.80, col = ink
  )
  text(
    5.88, 1.35, "Hourly multiplier: 0.86 [0.76-0.97]",
    adj = c(1, 0.5), cex = 0.80, col = ink
  )
  panel_title("A", "Foraging activity declined with elapsed post-collection time")

  set_plot_style(c(4.2, 4.7, 2.45, 1.0))
  plot(
    NA, xlim = c(0, 6), ylim = c(0, 14.5), axes = FALSE,
    xlab = "Hours since garbage collection ended", ylab = "Camera exposure (h)"
  )
  horizontal_grid(c(0, 4, 8, 12))
  axis(1, at = 0:6)
  axis(2, at = c(0, 4, 8, 12))
  rect(
    exposure$bin + 0.08, 0, exposure$bin + 0.92, exposure$camera_hours,
    col = alpha(blue, 0.78), border = NA
  )
  text(
    exposure$bin + 0.5, exposure$camera_hours + 0.48,
    labels = paste0(exposure$days, " d"), cex = 0.77, col = ink
  )
  text(
    5.95, 13.95, "Labels show contributing observation days",
    adj = c(1, 1), cex = 0.74, col = muted
  )
  panel_title("B", "Data support behind the decay curve")
}

pick_model <- function(label) model_est[model_est$analysis == label, ][1, ]
pick_decomp <- function(label) decomp_est[decomp_est$analysis == label, ][1, ]
pick_disp <- function(label) disp_est[disp_est$analysis == label, ][1, ]

overall <- pick_model("Primary 30-minute model")
bouts <- pick_model("Secondary bout-frequency model")
occurrence <- pick_model("Hurdle occurrence component")
positive <- pick_model("Hurdle positive-duration component")
attendance <- pick_decomp("Attendance primary 30-minute")
intensity <- pick_decomp("Intensity primary 30-minute")
displacement <- pick_disp("Opportunity-adjusted displacement rate")
competitor_displacement <- competitor_disp_est[
  competitor_disp_est$analysis == "Competitor-time adjusted displacement", ][1, ]
recorded_group_size <- group_est[group_est$analysis == "Recorded group size: primary", ][1, ]

effects <- data.frame(
  label = c(
    "Overall foraging duration", "Recorded focal visibility", "Foraging share while visible",
    "Foraging-bout count", "Any foraging", "Positive foraging duration",
    "Recorded group size", "Displacements per competitor-time", "Per additional post-collection hour"
  ),
  ratio = c(
    overall$rate_ratio, attendance$effect_ratio, intensity$effect_ratio,
    bouts$rate_ratio, occurrence$rate_ratio, positive$rate_ratio,
    recorded_group_size$effect_ratio, competitor_displacement$effect_ratio, decay_slope$effect_ratio
  ),
  low = c(
    overall$ci_low, attendance$ci_low, intensity$ci_low,
    bouts$ci_low, occurrence$ci_low, positive$ci_low,
    recorded_group_size$ci_low, competitor_displacement$ci_low, decay_slope$ci_low
  ),
  high = c(
    overall$ci_high, attendance$ci_high, intensity$ci_high,
    bouts$ci_high, occurrence$ci_high, positive$ci_high,
    recorded_group_size$ci_high, competitor_displacement$ci_high, decay_slope$ci_high
  ),
  y = c(10.4, 8.7, 7.8, 6.9, 6.0, 5.1, 3.65, 2.7, 1.0),
  colour = c(orange, blue, green, muted, muted, muted, sky, purple, orange),
  pch = c(23, 22, 24, 21, 21, 21, 22, 23, 25),
  stringsAsFactors = FALSE
)

draw_figure_3 <- function() {
  set_plot_style(c(4.6, 10.4, 2.2, 1.2))
  x_ticks <- c(0.25, 0.5, 0.75, 1, 1.5, 2, 3)
  plot(
    NA, xlim = c(0.18, 5.0), ylim = c(0.2, 11.5), log = "x", axes = FALSE,
    xlab = "Effect ratio (log scale)", ylab = ""
  )
  abline(v = x_ticks, col = grid_col, lwd = 0.7)
  abline(v = 1, col = ink, lty = 3, lwd = 1.15)
  axis(1, at = x_ticks, labels = x_ticks)
  axis(
    2, at = effects$y, labels = effects$label,
    las = 1, tick = FALSE, line = -0.35, cex.axis = 0.78
  )

  text(0.185, 11.15, "Primary outcome", adj = c(0, 0.5), font = 2, cex = 0.88)
  text(0.185, 9.45, "Secondary/sensitivity and exploratory mechanism estimates", adj = c(0, 0.5), font = 2, cex = 0.78)
  text(0.185, 4.35, "Exploratory group/interaction estimates", adj = c(0, 0.5), font = 2, cex = 0.88)
  text(0.185, 1.7, "Exploratory elapsed-time estimate", adj = c(0, 0.5), font = 2, cex = 0.88)
  text(4.90, 11.15, "Ratio [95% CI]", adj = c(1, 0.5), font = 2, cex = 0.82)

  for (i in seq_len(nrow(effects))) {
    segments(effects$low[i], effects$y[i], effects$high[i], effects$y[i], col = effects$colour[i], lwd = 1.8)
    segments(
      c(effects$low[i], effects$high[i]), effects$y[i] - 0.09,
      c(effects$low[i], effects$high[i]), effects$y[i] + 0.09,
      col = effects$colour[i], lwd = 1.2
    )
    points(
      effects$ratio[i], effects$y[i], pch = effects$pch[i],
      bg = if (effects$pch[i] == 21) paper else effects$colour[i],
      col = effects$colour[i], lwd = 1.5, cex = 1.25
    )
    text(
      4.90, effects$y[i],
      sprintf("%.2f [%.2f-%.2f]", effects$ratio[i], effects$low[i], effects$high[i]),
      adj = c(1, 0.5), cex = 0.82
    )
  }

  abline(h = c(9.85, 4.62, 2.05), col = grid_col, lwd = 0.7)
  text(0.28, 0.35, "Lower", adj = c(0.5, 0), cex = 0.74, col = muted)
  text(2.9, 0.35, "Higher", adj = c(0.5, 0), cex = 0.74, col = muted)
  panel_title("", "Adjusted estimates show magnitude and uncertainty")
}

group_curve <- function(name, lower = -Inf, upper = Inf) {
  x <- group_pred[group_pred$phase == name & group_pred$clock_hour >= lower & group_pred$clock_hour <= upper, ]
  x[order(x$clock_hour), ]
}
group_noncollection <- group_curve("Non-collection")
group_pre <- group_curve("Collection day before end", upper = max(collection_times$collection_clock_hour))
group_post <- group_curve("Collection day after end", lower = min(collection_times$collection_clock_hour))

draw_figure_4 <- function() {
  layout(matrix(c(1, 2), ncol = 1), heights = c(1.15, 1.0))

  set_plot_style(c(4.1, 4.7, 2.5, 1.0))
  y_ticks <- seq(1.0, 3.0, 0.5)
  plot(
    NA, xlim = c(6.75, 20.75), ylim = c(1.0, 3.02), axes = FALSE,
    xlab = "Local time", ylab = "Expected recorded group size"
  )
  horizontal_grid(y_ticks)
  axis(1, at = seq(7, 20, 2), labels = sprintf("%02d:00", seq(7, 20, 2)))
  axis(2, at = y_ticks, labels = sprintf("%.1f", y_ticks))
  draw_ribbon(group_noncollection$clock_hour, group_noncollection$ci_low, group_noncollection$ci_high, alpha(muted, 0.10))
  draw_ribbon(group_pre$clock_hour, group_pre$ci_low, group_pre$ci_high, alpha(blue, 0.10))
  draw_ribbon(group_post$clock_hour, group_post$ci_low, group_post$ci_high, alpha(orange, 0.13))
  lines(group_noncollection$clock_hour, group_noncollection$estimate, col = muted, lwd = 2.1, lty = 3)
  lines(group_pre$clock_hour, group_pre$estimate, col = blue, lwd = 2.4, lty = 5)
  lines(group_post$clock_hour, group_post$estimate, col = orange, lwd = 2.6, lty = 1)
  segments(collection_times$collection_clock_hour, 2.92, collection_times$collection_clock_hour, 3.01, col = ink, lwd = 1.0)
  legend(
    "topleft", legend = c("After collection", "Before collection", "Non-collection day"),
    col = c(orange, blue, muted), lty = c(1, 5, 3), lwd = c(2.6, 2.4, 2.1),
    bty = "n", cex = 0.82, seg.len = 2.6, inset = c(0.01, 0.05)
  )
  text(
    20.55, 1.08,
    "Curves are adjusted estimates; bands are 95% confidence intervals.",
    adj = c(1, 0), cex = 0.76, col = muted
  )
  panel_title("A", "Recorded group size through the day")

  set_plot_style(c(4.2, 4.7, 2.5, 1.0))
  y_ticks <- seq(1.0, 3.0, 0.5)
  plot(
    NA, xlim = c(0.72, 2.28), ylim = c(0.95, 3.08), axes = FALSE,
    xlab = "Collection phase", ylab = "Time-weighted mean recorded group size"
  )
  horizontal_grid(y_ticks)
  axis(1, at = c(1, 2), labels = c("Before collection", "After collection"))
  axis(2, at = y_ticks, labels = sprintf("%.1f", y_ticks))
  offsets <- seq(-0.04, 0.04, length.out = nrow(group_paired))
  for (i in seq_len(nrow(group_paired))) {
    segments(
      1 + offsets[i], group_paired$pre_time_weighted_mean_group_size[i],
      2 + offsets[i], group_paired$post_time_weighted_mean_group_size[i],
      col = alpha(if (group_paired$mean_group_size_difference[i] >= 0) orange else blue, 0.48),
      lwd = 1.1
    )
  }
  points(1 + offsets, group_paired$pre_time_weighted_mean_group_size, pch = 21, bg = paper, col = blue, lwd = 1.4, cex = 1.02)
  points(2 + offsets, group_paired$post_time_weighted_mean_group_size, pch = 24, bg = orange, col = orange, lwd = 1.2, cex = 1.05)
  text(
    0.76, 3.02,
    "Eight of 11 collection days with both phases had a higher post-collection mean.",
    adj = c(0, 1), cex = 0.76, col = muted
  )
  panel_title("B", "Day-level variation in recorded group size")
}

loo <- merge(
  loo_primary,
  loo_decay[, c("excluded_day", "hourly_rate_ratio")],
  by.x = "omitted_observation_id", by.y = "excluded_day", all.x = TRUE
)
loo <- merge(
  loo,
  observation_register[, c("original_recording_id", "observation_number", "observation_label")],
  by.x = "omitted_observation_id", by.y = "original_recording_id", all.x = TRUE
)
loo <- loo[order(loo$rate_ratio), ]
loo$y <- seq_len(nrow(loo))
loo$display_id <- ifelse(loo$observation_number == 2, "Obs. 2*", paste0("Obs. ", loo$observation_number))

draw_supplement_1 <- function() {
  layout(matrix(c(1, 2), nrow = 1), widths = c(1.28, 1.0))

  set_plot_style(c(4.6, 3.8, 2.65, 0.6))
  x_ticks <- c(0.75, 1, 1.25, 1.5, 2)
  plot(
    NA, xlim = c(0.62, 2.38), ylim = c(0.4, 25.8), log = "x", axes = FALSE,
    xlab = "Post/pre foraging rate ratio", ylab = ""
  )
  abline(v = x_ticks, col = grid_col, lwd = 0.7)
  abline(v = 1, col = ink, lty = 3, lwd = 1.1)
  abline(v = overall$rate_ratio, col = orange, lty = 2, lwd = 1.4)
  axis(1, at = x_ticks, labels = x_ticks)
  axis(2, at = loo$y, labels = loo$display_id, las = 1, tick = FALSE, cex.axis = 0.77)

  for (i in seq_len(nrow(loo))) {
    is_collection <- loo$omitted_collection_day[i] == 1
    point_col <- if (is_collection) orange else blue
    point_pch <- if (is_collection) 24 else 21
    segments(loo$ci_low[i], loo$y[i], loo$ci_high[i], loo$y[i], col = alpha(point_col, 0.72), lwd = 1.1)
    points(
      loo$rate_ratio[i], loo$y[i], pch = point_pch,
      bg = if (is_collection) alpha(orange, 0.72) else paper,
      col = point_col, lwd = 1.2, cex = 0.82
    )
  }
  text(
    0.64, 25.55,
    "Triangle: omitted collection day   Circle: omitted non-collection day",
    adj = c(0, 1), cex = 0.72, col = muted
  )
  text(
    2.34, 24.90, "Dashed line: full-data estimate (1.30)",
    adj = c(1, 1), cex = 0.72, col = muted
  )
  mtext("* Observation 2 had 3.3 min of pre-collection exposure.", side = 1, line = 3.35, adj = 0, cex = 0.7, col = muted)
  panel_title("A", "Overall estimate after omitting each day")

  set_plot_style(c(4.6, 0.9, 2.65, 0.8))
  x_ticks <- c(0.82, 0.86, 0.90, 0.94, 0.98, 1.00)
  plot(
    NA, xlim = c(0.81, 1.01), ylim = c(0.4, 25.8), axes = FALSE,
    xlab = "Hourly multiplier after collection", ylab = ""
  )
  abline(v = x_ticks, col = grid_col, lwd = 0.7)
  abline(v = 1, col = ink, lty = 3, lwd = 1.1)
  abline(v = decay_slope$effect_ratio, col = orange, lty = 2, lwd = 1.4)
  axis(1, at = x_ticks, labels = sprintf("%.2f", x_ticks))

  for (i in seq_len(nrow(loo))) {
    is_collection <- loo$omitted_collection_day[i] == 1
    points(
      loo$hourly_rate_ratio[i], loo$y[i],
      pch = if (is_collection) 24 else 21,
      bg = if (is_collection) alpha(orange, 0.72) else paper,
      col = if (is_collection) orange else blue,
      lwd = 1.2, cex = 0.82
    )
  }
  text(
    0.812, 25.55, "All 25 estimates remained below 1",
    adj = c(0, 1), cex = 0.72, col = muted
  )
  panel_title("B", "Decay estimate after omitting each day")
}

files <- c(
  export_figure("Figure_1_clock_time_and_day_variation", 8.2, 7.4, draw_figure_1),
  export_figure("Figure_2_post_collection_decay", 7.4, 6.6, draw_figure_2),
  export_figure("Figure_3_effect_size_summary", 9.2, 5.8, draw_figure_3),
  export_figure("Figure_4_recorded_group_size", 7.4, 7.8, draw_figure_4),
  export_figure("Figure_S1_leave_one_day_out", 10.0, 8.4, draw_supplement_1)
)

cat(paste(files, collapse = "\n"), "\n")
