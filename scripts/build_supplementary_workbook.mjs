/**
 * Script: build_supplementary_workbook.mjs
 * Pipeline stage: 6. Figures and reporting
 * Analytical purpose: Assemble the observation register, event-level audits, revised model tables,
 * robustness results, revision matrix, and data dictionary into the editable supplementary
 * workbook.
 * Inputs: .codex_work/issue4 revision audit/model outputs and the reconstructed-manuscript
 * comparison tables
 * Outputs: outputs/.../Grackles_supplementary_audit_and_results_BlindReview.xlsx
 * Run-order position: 30
 * Key scientific assumption: This reporting utility does not alter the observations or refit
 * models; it exposes traceability and limits alongside the results.
 * Provenance note: This annotated copy preserves the executed analytical statements. Only
 * explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
 */

import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";


const root = process.cwd();
const work = path.join(root, ".codex_work", "issue4");
const modelDir = path.join(work, "model_output");
const outputDir = path.join(root, "outputs", "019fb5b5-949c-74f1-ac2a-18b1d5a808c5");
const previewDir = path.join(root, ".codex_work", "revision_support", "previews_blind_review");
const outputPath = path.join(outputDir, "Grackles_supplementary_audit_and_results_BlindReview.xlsx");

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }
  if (field.length || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows.filter((candidate) => candidate.some((value) => value !== ""));
}

async function readCsv(filename) {
  return parseCsv((await fs.readFile(path.join(work, filename), "utf8")).replace(/^\uFEFF/, ""));
}

async function readModelCsv(filename) {
  return parseCsv((await fs.readFile(path.join(modelDir, filename), "utf8")).replace(/^\uFEFF/, ""));
}

function coerce(value) {
  if (value === "") return null;
  if (/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(value)) return Number(value);
  return value;
}

function typedMatrix(matrix) {
  return matrix.map((row, rowIndex) => row.map((value) => rowIndex === 0 ? value : coerce(value)));
}

function colLetter(number) {
  let value = number;
  let result = "";
  while (value > 0) {
    const remainder = (value - 1) % 26;
    result = String.fromCharCode(65 + remainder) + result;
    value = Math.floor((value - 1) / 26);
  }
  return result;
}

function titleFromHeader(header) {
  return header
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
    .replace("Boris", "BORIS")
    .replace("Qc", "QC");
}

const colors = {
  navy: "#17324D",
  teal: "#246B6B",
  paleTeal: "#E3F0EF",
  blue: "#DCE9F4",
  gold: "#F4C95D",
  paleGold: "#FFF5D8",
  green: "#2E7D55",
  paleGreen: "#E7F4ED",
  red: "#AD4E4E",
  paleRed: "#FBEAEA",
  gray: "#5B6770",
  paleGray: "#F3F6F8",
  border: "#C7D1D9",
  white: "#FFFFFF",
};

const workbook = Workbook.create();
const previews = [];

function styleHeader(range) {
  range.format = {
    fill: colors.navy,
    font: { name: "Aptos", size: 10, bold: true, color: colors.white },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  range.format.rowHeight = 42;
}

function addDataSheet(name, matrix, options = {}) {
  const sheet = workbook.worksheets.add(name);
  sheet.showGridLines = false;
  const data = typedMatrix(matrix);
  const rows = data.length;
  const columns = data[0].length;
  const endColumn = colLetter(columns);
  sheet.getRange(`A1:${endColumn}${rows}`).values = data;
  sheet.getRange(`A1:${endColumn}${rows}`).format = {
    font: { name: "Aptos", size: 9, color: "#24313B" },
    verticalAlignment: "top",
    wrapText: options.wrap !== false,
  };
  styleHeader(sheet.getRange(`A1:${endColumn}1`));
  sheet.tables.add(`A1:${endColumn}${rows}`, true, options.tableName ?? `${name.replace(/[^A-Za-z0-9]/g, "")}Table`).style = options.style ?? "TableStyleMedium2";
  sheet.freezePanes.freezeRows(1);
  const widths = options.widths ?? {};
  for (let column = 1; column <= columns; column += 1) {
    const letter = colLetter(column);
    const header = String(matrix[0][column - 1]);
    let width = widths[header] ?? 18;
    if (/description|decision|rule|interpretation|notes|comparison|portion/i.test(header)) width = widths[header] ?? 40;
    if (/datetime|local|date|time/i.test(header)) width = widths[header] ?? 24;
    if (/id|label|observer|phase|category/i.test(header)) width = widths[header] ?? 22;
    sheet.getRange(`${letter}1:${letter}${rows}`).format.columnWidth = width;
  }
  const previewRows = Math.min(rows, options.previewRows ?? 28);
  const previewColumns = Math.min(columns, options.previewColumns ?? 12);
  previews.push([name, `A1:${colLetter(previewColumns)}${previewRows}`]);
  return { sheet, rows, columns, endColumn };
}

const audits = JSON.parse(await fs.readFile(path.join(work, "revision_audits.json"), "utf8"));
const observationMatrix = await readCsv("observation_register.csv");
const containmentMatrix = await readCsv("containment_event_audit.csv");
const directionMatrix = await readCsv("displacement_direction_audit_labeled.csv");
const groupQcMatrix = await readCsv("group_size_qc.csv");
const groupEventMatrix = await readCsv("group_size_event_audit.csv");
const groupDayMatrix = await readCsv("group_size_day_phase_summary.csv");
const groupIntervalMatrix = await readCsv("group_size_phase_model_data_30min.csv");
const groupEstimateMatrix = await readModelCsv("group_size_model_estimates.csv");
const groupBootstrapMatrix = await readModelCsv("group_size_day_bootstrap_summary.csv");
const groupPairedMatrix = await readModelCsv("group_size_paired_days.csv");
const competitorMatrix = await readModelCsv("competitor_displacement_estimates.csv");
const containmentEstimateMatrix = await readModelCsv("containment_sensitivity_estimates.csv");
const primaryContrastMatrix = await readModelCsv("reviewer_primary_contrasts.csv");
const clockSplineMatrix = await readModelCsv("reviewer_clock_spline_sensitivity.csv");
const gamDiagnosticMatrix = await readModelCsv("reviewer_gam_diagnostics.csv");
const ninePlusMatrix = await readModelCsv("reviewer_group_9plus_sensitivity.csv");
const dayWeekMatrix = await readModelCsv("reviewer_day_of_week_schedule.csv");

const readme = workbook.worksheets.add("README");
readme.showGridLines = false;
readme.getRange("A1:H1").merge();
readme.getRange("A1").values = [["Great-tailed Grackle reconstruction: supplementary audit and results"]];
readme.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { name: "Aptos Display", size: 17, bold: true, color: colors.white },
  verticalAlignment: "center",
};
readme.getRange("A1:H1").format.rowHeight = 32;
readme.getRange("A3:H4").merge();
readme.getRange("A3").values = [[
  "Purpose: preserve the original recording identifiers while presenting chronological Observation 1–25 labels, document every data-quality decision, and expose the primary contrasts, diagnostics, schedule confounding, and exploratory reconstructions used in the blind-review revision.",
]];
readme.getRange("A3:H4").format = {
  fill: colors.blue,
  font: { name: "Aptos", size: 11, color: colors.navy },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};

const cards = [
  ["Observation days", audits.summary.observation_days],
  ["Containment discrepancies", audits.summary.containment_discrepancies],
  ["Displacement events", audits.summary.displacement_events],
  ["Group-size updates", audits.summary.subject_count_updates],
  ["Visible-state coverage", audits.summary.group_size_state_coverage_percent / 100],
  ["Known group-size hours", audits.summary.group_size_known_hours],
  ["9+ updates", audits.summary.more_than_eight_updates],
  ["Direction-coded events", audits.summary.displacement_events - audits.summary.displacement_direction_counts["Not direction-coded"]],
];
readme.getRange("A6:H6").merge();
readme.getRange("A6").values = [["Audit snapshot"]];
readme.getRange("A6:H6").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (let index = 0; index < cards.length; index += 1) {
  const row = 7 + Math.floor(index / 4) * 2;
  const column = 1 + (index % 4) * 2;
  const labelCell = `${colLetter(column)}${row}`;
  const valueCell = `${colLetter(column + 1)}${row}`;
  readme.getRange(labelCell).values = [[cards[index][0]]];
  readme.getRange(valueCell).values = [[cards[index][1]]];
  readme.getRange(labelCell).format = { fill: colors.paleGray, font: { bold: true, color: colors.gray }, wrapText: true };
  readme.getRange(valueCell).format = { fill: colors.white, font: { bold: true, color: colors.navy, size: 12 }, borders: { preset: "outside", style: "thin", color: colors.border } };
}
readme.getRange("B9").format.numberFormat = "0.0%";
readme.getRange("D9").format.numberFormat = "0.00";
readme.getRange("A12:H12").merge();
readme.getRange("A12").values = [["Decisions embodied in this workbook"]];
readme.getRange("A12:H12").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
readme.getRange("A13:H21").merge(true);
readme.getRange("A13:A21").values = [
  ["1. Public-facing labels follow calendar order: Observation 1 (23 October 2017) through Observation 25 (6 January 2018). Original M/N/V identifiers remain available for traceability only."],
  ["2. The 18 foraging intervals outside a raw at-site state are retained because a coded foraging state itself demonstrates focal visibility. No unobserved gap is filled."],
  ["3. Subject-count annotations are reconstructed as state updates only within focal-visible episodes; time before the first update is left unknown."],
  ["4. The open-ended More subjects code is represented as 9+; analyses use 9 as a lower bound, test 12 and 15 as plausible higher values, and separately exclude affected intervals."],
  ["5. Displacement direction is described as not direction-coded when the event exists but its direction modifier is absent."],
  ["6. Statistical inference remains at the patch and observation-day level; group-size states do not identify independent birds or individual rank."],
  ["7. The single primary contrast is total focal-foraging duration after versus before collection. It was designated retrospectively; all other estimates are secondary, sensitivity, or exploratory and were not multiplicity-adjusted."],
  ["8. Collection status is partly confounded with day of week. The dataset cannot reliably separate schedule effects from collection effects."],
  ["9. Focal-visible time combines bird presence within the fixed camera view with detectability because temporary obstruction was not coded."],
];
readme.getRange("A13:H21").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
for (const column of ["A", "B", "C", "D", "E", "F", "G", "H"]) readme.getRange(`${column}1:${column}21`).format.columnWidth = 17;
readme.getRange("A13:H21").format.rowHeight = 32;
readme.freezePanes.freezeRows(1);
previews.push(["README", "A1:H21"]);

addDataSheet("Observation Register", observationMatrix, { tableName: "ObservationRegisterTable", previewColumns: 13 });
addDataSheet("Containment Audit", containmentMatrix, { tableName: "ContainmentAuditTable", previewColumns: 14 });
addDataSheet("Direction Audit", directionMatrix, { tableName: "DirectionAuditTable", previewColumns: 14 });
addDataSheet("Group Size QC", groupQcMatrix, { tableName: "GroupSizeQCTable", previewColumns: 12 });
addDataSheet("Group Size Events", groupEventMatrix, { tableName: "GroupSizeEventsTable", previewColumns: 12, wrap: false });
addDataSheet("Group Day Summary", groupDayMatrix, { tableName: "GroupDaySummaryTable", previewColumns: 11 });
addDataSheet("Group Model Data", groupIntervalMatrix, { tableName: "GroupModelDataTable", previewColumns: 14, wrap: false });
addDataSheet("Group Paired Days", groupPairedMatrix, { tableName: "GroupPairedDaysTable", previewColumns: 15 });
addDataSheet("Primary Contrasts", primaryContrastMatrix, { tableName: "PrimaryContrastsTable", previewColumns: 8 });
addDataSheet("Clock Spline Checks", clockSplineMatrix, { tableName: "ClockSplineChecksTable", previewColumns: 12 });
addDataSheet("GAM Diagnostics", gamDiagnosticMatrix, { tableName: "GAMDiagnosticsTable", previewColumns: 4 });
addDataSheet("9plus Sensitivity", ninePlusMatrix, { tableName: "NinePlusSensitivityTable", previewColumns: 12 });
addDataSheet("Day Week Schedule", dayWeekMatrix, { tableName: "DayWeekScheduleTable", previewColumns: 5 });

const resultRows = [
  ["Analysis family", ...groupEstimateMatrix[0]],
  ...groupEstimateMatrix.slice(1).map((row) => ["Recorded group size", ...row]),
  ...competitorMatrix.slice(1).map((row) => ["Competitor-adjusted displacement", ...row]),
  ...containmentEstimateMatrix.slice(1).map((row) => ["Containment sensitivity", ...row]),
];
addDataSheet("Revised Model Results", resultRows, { tableName: "RevisedModelResultsTable", previewColumns: 16 });
addDataSheet("Group Bootstrap", groupBootstrapMatrix, { tableName: "GroupBootstrapTable", previewColumns: 4 });

const modelRegistry = [
  ["Model", "Status", "Response", "Distribution / link", "Fixed effects", "Repeated-day term", "Exposure / weight", "Estimand", "Guardrail"],
  ["Primary foraging", "Primary", "Foraging seconds per interval", "Tweedie / log", "Natural cubic spline(clock time, 4 df) + collection day + postcollection fraction", "Random intercept for observation day", "log(camera seconds / 1,800) offset", "Post- vs. precollection rate ratio", "Association at one site; food not measured"],
  ["Foraging bouts", "Secondary", "Bout count", "Negative binomial / log", "Same as primary", "Random intercept for observation day", "Camera-time offset", "Post- vs. precollection rate ratio", "Counts are not independent replicates"],
  ["Any foraging", "Sensitivity", "Any foraging in interval", "Binomial / complementary log-log", "Same as primary", "Random intercept for observation day", "Camera-time offset", "Occurrence-rate ratio", "Link is not a double-log transformation"],
  ["Positive duration", "Sensitivity", "Foraging seconds when >0", "Gamma / log", "Same as primary", "Random intercept for observation day", "Camera-time offset", "Positive-duration ratio", "Conditioned on occurrence"],
  ["Recorded focal visibility", "Exploratory mechanism", "Focal-visible seconds", "Tweedie / log", "Same as primary", "Random intercept for observation day", "Camera-time offset", "Recorded-visibility rate ratio", "Combines bird presence in view with detectability; obstruction was not coded"],
  ["Conditional intensity", "Exploratory mechanism", "Foraging seconds while visible", "Tweedie / log", "Same as primary", "Random intercept for observation day", "Focal-visible-time offset", "Foraging-intensity ratio", "Union-rule sensitivity reported"],
  ["Elapsed-time model", "Exploratory", "Foraging seconds in exact phase segments", "Tweedie / log", "Clock spline + collection day + postcollection + elapsed postcollection hours", "Random intercept for observation day", "Camera-time offset", "Multiplier per additional hour", "Elapsed and clock time are strongly correlated"],
  ["Visible-time displacement", "Exploratory", "Displacement events", "Negative binomial / log", "Clock spline + collection day + postcollection", "Random intercept for observation day", "Focal-visible-time offset", "Post- vs. precollection rate ratio", "Does not fully represent competitor opportunity"],
  ["Recorded group size", "Exploratory", "Time-weighted mean recorded group size", "Gamma / log", "Clock spline + collection day + postcollection", "Random intercept for observation day", "Known-state fraction as analysis weight", "Post- vs. precollection mean ratio", "9+ is a lower bound; unmarked birds may recur"],
  ["Multiple-grackle occupancy", "Exploratory", "Fraction of known state time with >1 grackle", "Beta / logit", "Clock spline + collection day + postcollection", "Random intercept for observation day", "Known-state fraction as analysis weight", "Post- vs. precollection odds ratio", "Boundary adjustment; descriptive support"],
  ["Competitor-time displacement", "Exploratory", "Displacement events with known group state", "Negative binomial / log", "Clock spline + collection day + postcollection", "Random intercept for observation day", "Integral of (recorded group size − 1) seconds", "Post- vs. precollection rate ratio", "9+ yields conservative lower-bound opportunity"],
  ["Raw at-site sensitivity", "Sensitivity", "Raw at-site and contained-foraging seconds", "Tweedie / log", "Same as mechanism models", "Random intercept for observation day", "Camera or raw at-site offset", "Union-rule sensitivity ratios", "Uses no inferred visible time"],
];
addDataSheet("Model Registry", modelRegistry, { tableName: "ModelRegistryTable", previewColumns: 9, previewRows: 15 });

const preprintComparison = [
  ["Component", "2021 preprint", "Reconstructed manuscript", "Reason for change"],
  ["Recording effort", "Approximately 194 h", "251.7 camera-hours from complete-file media metadata", "The complete recordings were watched and BORIS media durations provide the auditable denominator"],
  ["Public observation labels", "M/N/V recording identifiers", "Observation 1–25 in chronological order; original IDs retained in supplement", "Separates recording identity from observer identity and makes figures readable"],
  ["Primary replicate", "Aggregated events and percentages", "Observation day, with repeated 30-min intervals nested within day", "Thousands of events are not independent ecological replicates"],
  ["Primary analysis", "Areas under pooled hourly curves and percentages", "Tweedie mixed generalized additive model", "Retains day-level variation, exposure, nonlinear clock time, and uncertainty"],
  ["Garbage variable", "Presence/absence framing", "Timed collection-end marker as a proxy for temporary food accessibility", "Garbage was always present; accessibility and disturbance were not measured"],
  ["Focal visibility", "Raw at-site states", "Strict union of at-site and foraging states, plus a raw-state sensitivity", "Foraging necessarily demonstrates visibility; all 18 discrepancies are audited"],
  ["Group size", "Counts summarized by hour", "State reconstruction covering 98.1% of focal-visible time; exploratory mixed model", "Updates can be used as time-varying recorded states but not as independent-bird abundance"],
  ["Aggressive interactions", "Hierarchy and producer–scrounger interpretation", "Patch-level displacement rates adjusted for focal visibility and recorded competitor time", "Birds were unmarked and 51 event directions were not coded"],
  ["Theory", "State-dependent foraging, risk spreading, MVT, hierarchy, producer–scrounger", "Brief predation–starvation context plus a focused temporal-accessibility hypothesis", "Clock time is theoretically relevant, but state, risk, depletion, identity, rank, and individual strategies were not measured or tested"],
  ["Analysis provenance", "Descriptive preprint without a prospective analysis plan", "One retrospectively designated primary contrast; all other estimates labelled secondary, sensitivity, or exploratory", "Makes researcher degrees of freedom visible and prevents secondary results from being treated as independent confirmation"],
  ["Causal language", "Collection interpreted as changing foraging", "Association language throughout", "Single-site natural contrast was neither assigned nor spatially replicated"],
  ["Temporal result", "Descriptive daily curves", "Primary average contrast plus secondary event-centred decay", "Separates the average postcollection association from its possible duration"],
  ["Scientific name", "Misspelled in places", "Great-tailed Grackle (Quiscalus mexicanus)", "Taxonomic correction"],
  ["Length and focus", "Long, theory-heavy manuscript", "Shorter focused case study with explicit limits", "Addresses both reviewers' central concerns"],
];
addDataSheet("Preprint Comparison", preprintComparison, { tableName: "PreprintComparisonTable", previewColumns: 4, previewRows: 20 });

const revisionMatrix = [
  ["Issue", "Evidence checked", "Resolution", "Manuscript location", "Status"],
  ["Scientific name", "Taxonomic spelling", "Corrected to Quiscalus mexicanus", "Title, abstract, main text", "Resolved"],
  ["Scattered theoretical focus", "Measured variables versus original theories", "Restored brief predation–starvation context while explicitly declining to test state dependence, MVT, hierarchy, or producer–scrounger dynamics", "Introduction and Discussion", "Resolved"],
  ["No appropriate statistics", "Raw event stream, exposure, day structure", "Mixed GAMs with explicit distributions, offsets, uncertainty, and sensitivities", "Statistical Analysis and Results", "Resolved"],
  ["Small/unbanded sample", "No individual IDs", "Inference restricted to patch and observation day; no individual rank, learning, or strategy claims", "Method, Discussion, Limitations", "Resolved within data limits"],
  ["Unreplicated site", "One camera view at one refuse patch", "Causal and species-wide claims removed; replication specified as future work", "Throughout", "Unavoidable limitation"],
  ["Garbage always present", "Collection handling and marker timing", "Collection end treated as a proxy for temporary accessibility, not garbage presence or measured patch value", "Introduction, Method, Discussion", "Resolved within data limits"],
  ["Disturbance alternative", "Truck/workers not separately quantified", "Explicit competing explanation retained; no depletion claim", "Method and Discussion", "Unavoidable limitation"],
  ["18 containment discrepancies", "Event-level overlap audit", "Strict state union retained; raw at-site sensitivity added", "Data Reconstruction and supplement", "Resolved"],
  ["Group size", "9,469 update events; 98.1% state coverage", "Time-weighted state reconstruction plus lower-bound, 12, 15, and exclusion analyses for 9+", "Response Variables, Results, supplement", "Resolved cautiously"],
  ["Displacement opportunity", "Recorded group-size states", "Added focal-competitor-time denominator and direction audit", "Statistical Analysis, Results", "Resolved cautiously"],
  ["N3 naming", "Recording ID, coder, and date log", "Relabelled Observation 2; original N3 retained only in supplement", "Text and figures", "Resolved"],
  ["15:35 start time", "Observation log and first BORIS event", "Retained as verified local recording start", "Observation Register", "Resolved"],
  ["400 bootstrap replicates", "Monte Carlo stability", "Raised declared analyses to 2,000 fixed-seed day-level replicates", "Statistical Analysis and supplement", "Resolved"],
  ["194 h versus audited total", "BORIS media lengths and complete-file review", "Explained 251.7 h reconstruction and preprint difference", "Data Reconstruction and supplement", "Resolved"],
  ["Primary null result", "Primary ratio 1.30, 95% CI [0.84, 2.02], p = .245", "Abstract, Results, Discussion, and conclusion now lead with the unsupported primary hypothesis", "Throughout", "Resolved"],
  ["Confirmatory versus exploratory", "2021 preprint and reconstructed analysis history", "Declared retrospective provenance, one primary contrast, no multiplicity correction, and hypothesis-generating status for all other estimates", "Method, Table 1, Table 3", "Resolved"],
  ["Day-of-week confounding", "Observation register", "Reported schedule composition and explained why collection and weekday effects cannot be separated reliably", "Study Design and Limitations", "Resolved within data limits"],
  ["Camera line of sight", "Coding schema and fixed-camera design", "Reframed attendance as recorded focal visibility and disclosed that temporary obstruction was not coded", "Method, Results, Discussion", "Resolved within data limits"],
  ["Formula versus Figure 1", "Fitted model formula and prediction code", "Clarified that all phase curves share one clock-time basis and differ through scenario coefficients and support ranges", "Statistical Analysis and Figure 1", "Resolved"],
  ["Baseline contrasts", "Primary fitted model", "Added precollection-versus-noncollection and postcollection-versus-noncollection estimates", "Results and Table 3", "Resolved"],
  ["GAM diagnostics", "Primary model and clock-spline sensitivity refits", "Reported convergence, deviance explained, adjusted R squared, gradient, residual lag-1 correlation, random-effect edf, and 3–6 df sensitivity", "Model Diagnostics and supplement", "Resolved"],
  ["Displacement precision", "139 recorded events and model interval", "Labelled the analysis underpowered and prioritized it for dedicated follow-up", "Results and Discussion", "Resolved"],
  ["Supplement placement", "Journal-readiness review", "Moved Figure S1 into a separate supplementary document", "Separate supplement", "Resolved"],
  ["Overlong Results/Discussion", "Reviewer requests and claim scope", "Condensed around primary association, mechanism, timing, group size, and limitations", "Results and Discussion", "Resolved"],
  ["APA presentation", "APA 7 professional-paper layout", "Standardized headings, tables, figure notes, statistics, and references", "Entire document", "Resolved"],
];
addDataSheet("Revision Matrix", revisionMatrix, { tableName: "RevisionMatrixTable", previewColumns: 5, previewRows: 32 });

const dictionary = [
  ["Dataset / sheet", "Field", "Definition", "Unit / coding", "Interpretation limit"],
  ["Observation Register", "observation_number", "Chronological public-facing number", "1–25", "Not a subject, coder, or replicate count"],
  ["Observation Register", "original_recording_id", "Identifier stored in the original BORIS project", "M/N/V code", "Retained only for traceability"],
  ["Containment Audit", "seconds_added_by_union_rule", "Foraging-state seconds not overlapped by a raw at-site state", "seconds", "Explicit coded visibility, not imputed gap time"],
  ["Direction Audit", "direction_category", "Direction modifier attached to a recorded displacement", "three categories", "Not direction-coded means the event exists but direction was not recorded"],
  ["Group Size Events", "group_size_lower_bound", "Recorded state update translated to a number", "1–9", "9 represents the open-ended 9+ category"],
  ["Group Model Data", "group_size_known_seconds", "Seconds covered after the first count update in each focal-visible episode", "seconds", "Time before the first update remains unknown"],
  ["Group Model Data", "time_weighted_mean_group_size", "Integral of recorded group size divided by known-state seconds", "grackles", "Repeated/unmarked individuals cannot be separated"],
  ["Group Model Data", "focal_competitor_seconds_lower_bound", "Integral of max(recorded group size − 1, 0)", "competitor-seconds", "Lower bound when 9+ is present"],
  ["Group Model Data", "group_size_9plus_seconds", "Known-state seconds represented by the open-ended 9+ code", "seconds", "Identifies intervals affected by open-ended group-size recording"],
  ["Primary Contrasts", "effect_ratio", "Exponentiated contrast from the same primary Tweedie model", "ratio", "Post/pre is primary; pre/noncollection and post/noncollection are interpretive contrasts"],
  ["Revised Model Results", "effect_ratio", "Exponentiated model coefficient", "ratio", "1 = no adjusted change; >1 higher after collection; <1 lower"],
  ["Revised Model Results", "ci_low / ci_high", "Wald 95% confidence interval", "ratio", "Compatibility interval, not a probability that the true value lies inside"],
];
addDataSheet("Data Dictionary", dictionary, { tableName: "DataDictionaryTable", previewColumns: 5, previewRows: 14 });

// Inspect all compact result sheets and scan the workbook for formula errors.
for (const [sheetName, range] of previews) {
  const inspection = await workbook.inspect({
    kind: "table",
    range: `${sheetName}!${range}`,
    include: "values,formulas",
    tableMaxRows: 8,
    tableMaxCols: 12,
    maxChars: 3000,
  });
  console.log(inspection.ndjson);
}
console.log((await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 200 },
  summary: "supplementary workbook formula-error scan",
  maxChars: 3000,
})).ndjson);

for (const [sheetName, range] of previews) {
  const blob = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(path.join(previewDir, `${sheetName.replaceAll(" ", "_")}.png`), new Uint8Array(await blob.arrayBuffer()));
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(JSON.stringify({ outputPath, sheets: previews.length }, null, 2));
