/**
 * Script: build_workbook.mjs
 * Pipeline stage: 6. Figures and reporting
 * Analytical purpose: Assemble the audited interval data, model decisions, results, diagnostics,
 * and explanatory sheets into the editable analysis workbook.
 * Inputs: interval_data.json; diagnostics and all collected result JSON files
 * Outputs: outputs/.../Grackles_30min_analysis_dataset.xlsx and sheet-preview images
 * Run-order position: 28
 * Key scientific assumption: This is a reporting/export utility; it does not fit or alter the
 * statistical models.
 * Provenance note: This annotated copy preserves the executed analytical statements. Only
 * explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
 */

import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";


// --- Project paths and analysis inputs ---
const rootDir = process.cwd();
const workDir = path.join(rootDir, ".codex_work", "issue4");
const outputDir = path.join(rootDir, "outputs", "019fb5b5-949c-74f1-ac2a-18b1d5a808c5");
const inputPath = path.join(workDir, "interval_data.json");
const diagnosticsPath = path.join(workDir, "issue5_diagnostics.json");
const modelResultsPath = path.join(workDir, "model_results.json");
const decompositionResultsPath = path.join(workDir, "decomposition_results.json");
const displacementResultsPath = path.join(workDir, "displacement_results.json");
const timeDecayResultsPath = path.join(workDir, "time_decay_results.json");
const outputPath = path.join(outputDir, "Grackles_30min_analysis_dataset.xlsx");
const previewDir = path.join(workDir, "previews");

const data = JSON.parse(await fs.readFile(inputPath, "utf8"));
const diagnostics = JSON.parse(await fs.readFile(diagnosticsPath, "utf8"));
const modelResults = JSON.parse(await fs.readFile(modelResultsPath, "utf8"));
const decompositionResults = JSON.parse(await fs.readFile(decompositionResultsPath, "utf8"));
const displacementResults = JSON.parse(await fs.readFile(displacementResultsPath, "utf8"));
const timeDecayResults = JSON.parse(await fs.readFile(timeDecayResultsPath, "utf8"));
await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

const workbook = Workbook.create();
const readme = workbook.worksheets.add("README");
const parameters = workbook.worksheets.add("Parameters");
const intervalSheet = workbook.worksheets.add("Interval_Data");
const daySheet = workbook.worksheets.add("Day_Summary");
const qcSheet = workbook.worksheets.add("State_QC");
const dictSheet = workbook.worksheets.add("Data_Dictionary");
const modelSheet = workbook.worksheets.add("Model_Decision");
const modelResultsSheet = workbook.worksheets.add("Model_Results");
const mechanismSheet = workbook.worksheets.add("Mechanism_Results");
const displacementSheet = workbook.worksheets.add("Displacement_Results");
const timeDecaySheet = workbook.worksheets.add("Time_Decay");

const colors = {
  navy: "#17324D",
  teal: "#2B7A78",
  paleTeal: "#DDEFEF",
  paleBlue: "#E8F0F7",
  gold: "#F2C14E",
  paleGold: "#FFF4CE",
  green: "#2E7D32",
  paleGreen: "#E7F3E8",
  red: "#B54747",
  paleRed: "#FBE9E7",
  gray: "#5F6B76",
  paleGray: "#F4F7F9",
  white: "#FFFFFF",
  border: "#CBD5DF",
};

const headerFormat = {
  fill: colors.navy,
  font: { bold: true, color: colors.white },
  verticalAlignment: "center",
  wrapText: true,
  borders: { preset: "outside", style: "thin", color: colors.border },
};

function colLetter(number) {
  let n = number;
  let result = "";
  while (n > 0) {
    const remainder = (n - 1) % 26;
    result = String.fromCharCode(65 + remainder) + result;
    n = Math.floor((n - 1) / 26);
  }
  return result;
}

function asUtcDate(iso) {
  if (!iso) return null;
  return new Date(`${iso}Z`);
}

function asUtcDay(iso) {
  if (!iso) return null;
  return new Date(`${iso}T00:00:00Z`);
}

function setColumnWidth(sheet, column, rowCount, width) {
  sheet.getRange(`${column}1:${column}${rowCount}`).format.columnWidth = width;
}

function styleFlatTable(sheet, range, headerRange) {
  range.format.font = { name: "Aptos", size: 10, color: "#1D2730" };
  headerRange.format = headerFormat;
  headerRange.format.rowHeight = 48;
}

function addTable(sheet, address, name, style = "TableStyleMedium2") {
  const table = sheet.tables.add(address, true, name);
  table.style = style;
  table.showFilterButton = true;
  return table;
}

// Parameters and source lineage.
parameters.showGridLines = false;
parameters.getRange("A1:D1").merge();
parameters.getRange("A1").values = [["Analysis parameters and source lineage"]];
parameters.getRange("A1:D1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 16 },
  verticalAlignment: "center",
};
parameters.getRange("A1:D1").format.rowHeight = 28;
parameters.getRange("A3:D7").values = [
  ["Parameter", "Value", "Unit", "Purpose"],
  ["bin_seconds", data.parameters.bin_seconds, "seconds", "Clock-aligned analysis interval length"],
  [
    "containment_tolerance_seconds",
    data.parameters.containment_tolerance_seconds,
    "seconds",
    "Used only to flag interval containment; never used to fill an unobserved gap",
  ],
  ["seconds_per_hour", 3600, "seconds", "Visible conversion factor for all hours calculations"],
  ["focal_visible_rule", data.parameters.focal_visible_rule, "text", "Conservative repair rule"],
];
styleFlatTable(parameters, parameters.getRange("A3:D7"), parameters.getRange("A3:D3"));
addTable(parameters, "A3:D7", "ParametersTable", "TableStyleMedium4");
parameters.getRange("A10:D10").values = [["Source", "SHA-256", "Role", "Status"]];
parameters.getRange("A11:D13").values = data.sources.map((source) => [
  source.path,
  source.sha256,
  source.role,
  source.sha256 ? "File verified" : "Folder of paired state exports",
]);
styleFlatTable(parameters, parameters.getRange("A10:D13"), parameters.getRange("A10:D10"));
addTable(parameters, "A10:D13", "SourcesTable", "TableStyleMedium4");
setColumnWidth(parameters, "A", 13, 38);
setColumnWidth(parameters, "B", 13, 68);
setColumnWidth(parameters, "C", 13, 58);
setColumnWidth(parameters, "D", 13, 30);
parameters.getRange("A3:D13").format.wrapText = true;
parameters.freezePanes.freezeRows(3);

// Main interval-level dataset.
const intervalHeaders = [
  "observation_id",
  "observation_date",
  "weekday",
  "observer",
  "collection_day",
  "camera_start_datetime",
  "camera_end_datetime",
  "bin_number",
  "bin_start_datetime",
  "bin_end_datetime",
  "camera_seconds",
  "camera_coverage_proportion",
  "collection_end_datetime",
  "collection_phase",
  "post_collection_camera_seconds",
  "hours_from_collection_midpoint",
  "raw_at_site_seconds",
  "foraging_seconds",
  "focal_visible_seconds",
  "added_visible_seconds",
  "focal_visible_per_camera",
  "foraging_per_camera",
  "foraging_per_focal_visible",
  "at_site_bouts",
  "foraging_bouts",
  "focal_visible_episodes",
  "fly_events",
  "jump_events",
  "out_of_sight_events",
  "displacement_events",
  "displacement_focal_to_others",
  "displacement_others_to_focal",
  "displacement_unspecified",
  "subject_count_update_events",
  "garbage_marker_events",
];

const intervalRows = data.interval_rows.map((row) => [
  row.observation_id,
  asUtcDay(row.observation_date),
  row.weekday,
  row.observer,
  row.collection_day,
  asUtcDate(row.camera_start_datetime),
  asUtcDate(row.camera_end_datetime),
  row.bin_number,
  asUtcDate(row.bin_start_datetime),
  asUtcDate(row.bin_end_datetime),
  row.camera_seconds,
  null,
  asUtcDate(row.collection_end_datetime),
  row.collection_phase,
  row.post_collection_camera_seconds,
  row.time_from_collection_midpoint_hours,
  row.raw_at_site_seconds,
  row.foraging_seconds,
  row.focal_visible_seconds,
  row.added_visible_seconds,
  null,
  null,
  null,
  row.at_site_bouts,
  row.foraging_bouts,
  row.focal_visible_episodes,
  row.fly_events,
  row.jump_events,
  row.out_of_sight_events,
  row.displacement_events,
  row.displacement_focal_to_others,
  row.displacement_others_to_focal,
  row.displacement_unspecified,
  row.subject_count_update_events,
  row.garbage_marker_events,
]);

const intervalLastRow = intervalRows.length + 1;
const intervalLastCol = colLetter(intervalHeaders.length);
intervalSheet.showGridLines = false;
intervalSheet.getRange(`A1:${intervalLastCol}1`).values = [intervalHeaders];
intervalSheet.getRange(`A2:${intervalLastCol}${intervalLastRow}`).values = intervalRows;
intervalSheet.getRange("L2").formulas = [["=K2/'Parameters'!$B$4"]];
intervalSheet.getRange(`L2:L${intervalLastRow}`).fillDown();
intervalSheet.getRange("U2").formulas = [["=IFERROR(S2/K2,\"\")"]];
intervalSheet.getRange(`U2:U${intervalLastRow}`).fillDown();
intervalSheet.getRange("V2").formulas = [["=IFERROR(R2/K2,\"\")"]];
intervalSheet.getRange(`V2:V${intervalLastRow}`).fillDown();
intervalSheet.getRange("W2").formulas = [["=IFERROR(R2/S2,\"\")"]];
intervalSheet.getRange(`W2:W${intervalLastRow}`).fillDown();
styleFlatTable(
  intervalSheet,
  intervalSheet.getRange(`A1:${intervalLastCol}${intervalLastRow}`),
  intervalSheet.getRange(`A1:${intervalLastCol}1`),
);
addTable(intervalSheet, `A1:${intervalLastCol}${intervalLastRow}`, "IntervalDataTable", "TableStyleMedium2");
intervalSheet.getRange(`B2:B${intervalLastRow}`).format.numberFormat = "yyyy-mm-dd";
for (const column of ["F", "G", "I", "J", "M"]) {
  intervalSheet.getRange(`${column}2:${column}${intervalLastRow}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";
}
for (const column of ["K", "O", "Q", "R", "S", "T"]) {
  intervalSheet.getRange(`${column}2:${column}${intervalLastRow}`).format.numberFormat = "0.000";
}
intervalSheet.getRange(`P2:P${intervalLastRow}`).format.numberFormat = "0.00";
for (const column of ["L", "U", "V", "W"]) {
  intervalSheet.getRange(`${column}2:${column}${intervalLastRow}`).format.numberFormat = "0.0%";
}
intervalSheet.getRange(`T2:T${intervalLastRow}`).conditionalFormats.add("cellIs", {
  operator: "greaterThan",
  formula: 0,
  format: { fill: colors.paleGold, font: { color: "#6F5400" } },
});
intervalSheet.getRange(`N2:N${intervalLastRow}`).conditionalFormats.add("containsText", {
  text: "Straddles",
  format: { fill: colors.paleGold, font: { bold: true, color: "#6F5400" } },
});
intervalSheet.freezePanes.freezeRows(1);
intervalSheet.freezePanes.freezeColumns(5);

const intervalWidths = {
  A: 15, B: 13, C: 11, D: 12, E: 13, F: 21, G: 21, H: 11, I: 21, J: 21,
  K: 14, L: 15, M: 21, N: 25, O: 18, P: 18, Q: 16, R: 15, S: 17, T: 16,
  U: 16, V: 15, W: 18, X: 13, Y: 13, Z: 16, AA: 11, AB: 11, AC: 15, AD: 14,
  AE: 18, AF: 18, AG: 17, AH: 18, AI: 15,
};
for (const [column, width] of Object.entries(intervalWidths)) {
  setColumnWidth(intervalSheet, column, intervalLastRow, width);
}

// Day-level reconciliation with formula-driven totals from the interval sheet.
const dayHeaders = [
  "observation_id",
  "observation_date",
  "weekday",
  "observer",
  "collection_day",
  "media_duration_seconds_source",
  "camera_seconds_binned",
  "camera_difference_seconds",
  "camera_start_datetime",
  "camera_end_datetime",
  "collection_end_datetime",
  "post_collection_camera_seconds",
  "focal_visible_seconds",
  "foraging_seconds",
  "added_visible_seconds",
  "at_site_bouts",
  "foraging_bouts",
  "displacement_events",
  "garbage_marker_events",
  "qc_status",
];
const dayRows = data.day_rows.map((row) => [
  row.observation_id,
  asUtcDay(row.observation_date),
  row.weekday,
  row.observer,
  row.collection_day,
  row.media_duration_seconds_source,
  null,
  null,
  asUtcDate(row.camera_start_datetime),
  asUtcDate(row.camera_end_datetime),
  asUtcDate(row.collection_end_datetime),
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
]);
const dayLastDataRow = dayRows.length + 1;
const dayTotalRow = dayLastDataRow + 1;
daySheet.showGridLines = false;
daySheet.getRange("A1:T1").values = [dayHeaders];
daySheet.getRange(`A2:T${dayLastDataRow}`).values = dayRows;
const intervalA = `'Interval_Data'!$A$2:$A$${intervalLastRow}`;
const seedFormulas = {
  G: `=SUMIF(${intervalA},A2,'Interval_Data'!$K$2:$K$${intervalLastRow})`,
  H: "=G2-F2",
  L: `=SUMIF(${intervalA},A2,'Interval_Data'!$O$2:$O$${intervalLastRow})`,
  M: `=SUMIF(${intervalA},A2,'Interval_Data'!$S$2:$S$${intervalLastRow})`,
  N: `=SUMIF(${intervalA},A2,'Interval_Data'!$R$2:$R$${intervalLastRow})`,
  O: `=SUMIF(${intervalA},A2,'Interval_Data'!$T$2:$T$${intervalLastRow})`,
  P: `=SUMIF(${intervalA},A2,'Interval_Data'!$X$2:$X$${intervalLastRow})`,
  Q: `=SUMIF(${intervalA},A2,'Interval_Data'!$Y$2:$Y$${intervalLastRow})`,
  R: `=SUMIF(${intervalA},A2,'Interval_Data'!$AD$2:$AD$${intervalLastRow})`,
  S: `=SUMIF(${intervalA},A2,'Interval_Data'!$AI$2:$AI$${intervalLastRow})`,
  T: "=IF(AND(ABS(H2)<='Parameters'!$B$5,S2=E2),\"PASS\",\"CHECK\")",
};
for (const [column, formula] of Object.entries(seedFormulas)) {
  daySheet.getRange(`${column}2`).formulas = [[formula]];
  daySheet.getRange(`${column}2:${column}${dayLastDataRow}`).fillDown();
}
styleFlatTable(daySheet, daySheet.getRange(`A1:T${dayLastDataRow}`), daySheet.getRange("A1:T1"));
addTable(daySheet, `A1:T${dayLastDataRow}`, "DaySummaryTable", "TableStyleMedium2");
daySheet.getRange(`A${dayTotalRow}:T${dayTotalRow}`).values = [[
  "TOTAL", null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
]];
for (const column of ["E", "F", "G", "H", "L", "M", "N", "O", "P", "Q", "R", "S"]) {
  daySheet.getRange(`${column}${dayTotalRow}`).formulas = [[`=SUM(${column}2:${column}${dayLastDataRow})`]];
}
daySheet.getRange(`T${dayTotalRow}`).formulas = [[`=IF(COUNTIF(T2:T${dayLastDataRow},\"CHECK\")=0,\"PASS\",\"CHECK\")`]];
daySheet.getRange(`A${dayTotalRow}:T${dayTotalRow}`).format = {
  fill: colors.paleTeal,
  font: { bold: true, color: colors.navy },
  borders: { preset: "doubleBottom", style: "medium", color: colors.teal },
};
daySheet.getRange(`B2:B${dayLastDataRow}`).format.numberFormat = "yyyy-mm-dd";
for (const column of ["I", "J", "K"]) {
  daySheet.getRange(`${column}2:${column}${dayLastDataRow}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";
}
for (const column of ["F", "G", "H", "L", "M", "N", "O"]) {
  daySheet.getRange(`${column}2:${column}${dayTotalRow}`).format.numberFormat = "0.000";
}
daySheet.getRange(`T2:T${dayTotalRow}`).conditionalFormats.add("containsText", {
  text: "CHECK",
  format: { fill: colors.paleRed, font: { bold: true, color: colors.red } },
});
daySheet.getRange(`T2:T${dayTotalRow}`).conditionalFormats.add("containsText", {
  text: "PASS",
  format: { fill: colors.paleGreen, font: { bold: true, color: colors.green } },
});
daySheet.freezePanes.freezeRows(1);
daySheet.freezePanes.freezeColumns(5);
for (const [column, width] of Object.entries({
  A: 15, B: 13, C: 11, D: 12, E: 13, F: 19, G: 18, H: 18, I: 21, J: 21,
  K: 21, L: 18, M: 17, N: 15, O: 16, P: 13, Q: 13, R: 15, S: 15, T: 12,
})) {
  setColumnWidth(daySheet, column, dayTotalRow, width);
}

// State-level quality-control table.
const qcHeaders = [
  "observation_id",
  "at_site_bouts",
  "foraging_bouts",
  "raw_at_site_seconds",
  "foraging_seconds",
  "focal_visible_union_seconds",
  "added_visible_seconds",
  "foraging_intervals_outside_at_site",
  "at_site_overlap_count",
  "foraging_overlap_count",
  "negative_duration_count",
  "zero_duration_count",
  "outside_media_count",
  "qc_decision",
  "overall_qc",
];
const qcRows = data.qc_rows.map((row) => [
  row.observation_id,
  row.at_site_bouts,
  row.foraging_bouts,
  row.raw_at_site_seconds,
  row.foraging_seconds,
  row.focal_visible_union_seconds,
  row.added_visible_seconds,
  row.foraging_intervals_outside_at_site,
  row.at_site_overlap_count,
  row.foraging_overlap_count,
  row.negative_duration_count,
  row.zero_duration_count,
  row.outside_media_count,
  row.qc_decision,
  null,
]);
const qcLastDataRow = qcRows.length + 1;
const qcTotalRow = qcLastDataRow + 1;
qcSheet.showGridLines = false;
qcSheet.getRange("A1:O1").values = [qcHeaders];
qcSheet.getRange(`A2:O${qcLastDataRow}`).values = qcRows;
qcSheet.getRange("O2").formulas = [[
  "=IF(SUM(I2:M2)>0,\"CHECK\",IF(G2>'Parameters'!$B$5,\"PASS - UNION REPAIR\",\"PASS\"))",
]];
qcSheet.getRange(`O2:O${qcLastDataRow}`).fillDown();
styleFlatTable(qcSheet, qcSheet.getRange(`A1:O${qcLastDataRow}`), qcSheet.getRange("A1:O1"));
addTable(qcSheet, `A1:O${qcLastDataRow}`, "StateQCTable", "TableStyleMedium2");
qcSheet.getRange(`A${qcTotalRow}:O${qcTotalRow}`).values = [[
  "TOTAL", null, null, null, null, null, null, null, null, null, null, null, null, null, null,
]];
for (const column of ["B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"]) {
  qcSheet.getRange(`${column}${qcTotalRow}`).formulas = [[`=SUM(${column}2:${column}${qcLastDataRow})`]];
}
qcSheet.getRange(`O${qcTotalRow}`).formulas = [[
  `=IF(COUNTIF(O2:O${qcLastDataRow},\"CHECK\")=0,\"PASS\",\"CHECK\")`,
]];
qcSheet.getRange(`A${qcTotalRow}:O${qcTotalRow}`).format = {
  fill: colors.paleTeal,
  font: { bold: true, color: colors.navy },
  borders: { preset: "doubleBottom", style: "medium", color: colors.teal },
};
for (const column of ["D", "E", "F", "G"]) {
  qcSheet.getRange(`${column}2:${column}${qcTotalRow}`).format.numberFormat = "0.000";
}
qcSheet.getRange(`G2:G${qcLastDataRow}`).conditionalFormats.add("cellIs", {
  operator: "greaterThan",
  formula: 0,
  format: { fill: colors.paleGold, font: { color: "#6F5400" } },
});
qcSheet.getRange(`O2:O${qcTotalRow}`).conditionalFormats.add("containsText", {
  text: "CHECK",
  format: { fill: colors.paleRed, font: { bold: true, color: colors.red } },
});
qcSheet.getRange(`O2:O${qcTotalRow}`).conditionalFormats.add("containsText", {
  text: "PASS",
  format: { fill: colors.paleGreen, font: { bold: true, color: colors.green } },
});
qcSheet.freezePanes.freezeRows(1);
qcSheet.freezePanes.freezeColumns(1);
for (const [column, width] of Object.entries({
  A: 15, B: 13, C: 13, D: 17, E: 15, F: 20, G: 17, H: 22, I: 16, J: 17,
  K: 17, L: 15, M: 16, N: 22, O: 20,
})) {
  setColumnWidth(qcSheet, column, qcTotalRow, width);
}

// Data dictionary.
const dictionaryRows = [
  ["Interval_Data", "observation_id", "text", "identifier", "Unique day-level observation ID", "BORIS observation ID"],
  ["Interval_Data", "observation_date", "date", "date", "Actual recording date", "Obs_Time.xlsx observer and video-classification mapping"],
  ["Interval_Data", "weekday", "text", "category", "Weekday of recording", "Derived from observation_date"],
  ["Interval_Data", "observer", "text", "category", "Observer assigned to the video", "Obs_Time.xlsx"],
  ["Interval_Data", "collection_day", "integer", "0/1", "1 when a garbage-collection end marker occurs during the file", "BORIS Garbage point event"],
  ["Interval_Data", "camera_start_datetime", "datetime", "local clock", "Beginning of complete video observation", "Obs_Time.xlsx"],
  ["Interval_Data", "camera_end_datetime", "datetime", "local clock", "End of complete video observation", "Camera start plus BORIS media_info.length"],
  ["Interval_Data", "bin_number", "integer", "sequence", "Clock-aligned 30-minute bin number within observation", "Derived"],
  ["Interval_Data", "bin_start_datetime", "datetime", "local clock", "Start of 30-minute clock bin", "Derived from bin_seconds"],
  ["Interval_Data", "bin_end_datetime", "datetime", "local clock", "End of 30-minute clock bin", "Derived from bin_seconds"],
  ["Interval_Data", "camera_seconds", "number", "seconds", "Observed video seconds falling inside the bin", "Intersection of bin and full media duration"],
  ["Interval_Data", "camera_coverage_proportion", "formula", "proportion", "Camera seconds divided by nominal bin length", "camera_seconds / Parameters.bin_seconds"],
  ["Interval_Data", "collection_end_datetime", "datetime", "local clock", "Recorded end of garbage collection", "BORIS Garbage point event"],
  ["Interval_Data", "collection_phase", "text", "category", "No collection, pre, straddling, or post collection end", "Bin relation to collection marker"],
  ["Interval_Data", "post_collection_camera_seconds", "number", "seconds", "Observed seconds after collection end within the bin", "Temporal intersection"],
  ["Interval_Data", "hours_from_collection_midpoint", "number", "hours", "Observed-bin midpoint relative to collection end", "Negative before, positive after; blank on noncollection days"],
  ["Interval_Data", "raw_at_site_seconds", "number", "seconds", "Duration explicitly coded At the observation site", "Strict union of that state within bin"],
  ["Interval_Data", "foraging_seconds", "number", "seconds", "Duration explicitly coded Searching for food", "Strict union of that state within bin"],
  ["Interval_Data", "focal_visible_seconds", "number", "seconds", "Conservative explicit focal-visible exposure", "Strict union of At the observation site OR Searching for food"],
  ["Interval_Data", "added_visible_seconds", "number", "seconds", "Foraging time outside the raw at-site state", "focal_visible_seconds minus raw_at_site_seconds"],
  ["Interval_Data", "focal_visible_per_camera", "formula", "proportion", "Focal-visible seconds per camera second", "focal_visible_seconds / camera_seconds"],
  ["Interval_Data", "foraging_per_camera", "formula", "proportion", "Foraging seconds per camera second", "foraging_seconds / camera_seconds"],
  ["Interval_Data", "foraging_per_focal_visible", "formula", "proportion", "Foraging intensity conditional on focal visibility", "foraging_seconds / focal_visible_seconds"],
  ["Interval_Data", "at_site_bouts", "integer", "count", "Starts of raw at-site states in the bin", "Paired BORIS state intervals"],
  ["Interval_Data", "foraging_bouts", "integer", "count", "Starts of foraging states in the bin", "Paired BORIS state intervals"],
  ["Interval_Data", "focal_visible_episodes", "integer", "count", "Starts of unioned focal-visible intervals", "Derived after strict interval union"],
  ["Interval_Data", "fly_events", "integer", "count", "Fly point events", "BORIS event stream"],
  ["Interval_Data", "jump_events", "integer", "count", "Jump point events", "BORIS event stream"],
  ["Interval_Data", "out_of_sight_events", "integer", "count", "Out of the sight point events", "BORIS event stream"],
  ["Interval_Data", "displacement_events", "integer", "count", "All displacement point events", "BORIS event stream"],
  ["Interval_Data", "displacement_focal_to_others", "integer", "count", "Directed displacement events from focal to others", "BORIS modifier"],
  ["Interval_Data", "displacement_others_to_focal", "integer", "count", "Directed displacement events from others to focal", "BORIS modifier"],
  ["Interval_Data", "displacement_unspecified", "integer", "count", "Displacement events without a direction modifier", "BORIS modifier absent"],
  ["Interval_Data", "subject_count_update_events", "integer", "count", "Number-of-subject point updates; not an abundance measure", "BORIS event stream"],
  ["Interval_Data", "garbage_marker_events", "integer", "count", "End-of-collection point events", "BORIS event stream"],
  ["Day_Summary", "camera_difference_seconds", "formula", "seconds", "Binned camera time minus source media duration", "Must be zero within tolerance"],
  ["State_QC", "foraging_intervals_outside_at_site", "integer", "count", "Foraging intervals not wholly contained in a single raw at-site interval", "Containment audit with 0.01-second tolerance"],
  ["State_QC", "qc_decision", "text", "category", "Whether union repair added explicit focal-visible exposure", "Documented transformation; source unchanged"],
];
dictSheet.showGridLines = false;
dictSheet.getRange("A1:F1").values = [["Sheet", "Variable", "Type", "Unit", "Definition", "Derivation or source"]];
dictSheet.getRange(`A2:F${dictionaryRows.length + 1}`).values = dictionaryRows;
styleFlatTable(dictSheet, dictSheet.getRange(`A1:F${dictionaryRows.length + 1}`), dictSheet.getRange("A1:F1"));
addTable(dictSheet, `A1:F${dictionaryRows.length + 1}`, "DataDictionaryTable", "TableStyleMedium4");
dictSheet.getRange(`A1:F${dictionaryRows.length + 1}`).format.wrapText = true;
dictSheet.freezePanes.freezeRows(1);
for (const [column, width] of Object.entries({ A: 18, B: 34, C: 12, D: 15, E: 58, F: 58 })) {
  setColumnWidth(dictSheet, column, dictionaryRows.length + 1, width);
}

// Issue 5: lock the primary response and model before any inferential fitting.
modelSheet.showGridLines = false;
modelSheet.getRange("A1:H1").merge();
modelSheet.getRange("A1").values = [["Issue 5 — Primary response and statistical model"]];
modelSheet.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 17 },
  verticalAlignment: "center",
};
modelSheet.getRange("A1:H1").format.rowHeight = 30;
modelSheet.getRange("A3:H4").merge();
modelSheet.getRange("A3").values = [[
  "Decision: model total foraging time per camera exposure as the primary response. Use bout counts only as a confirmatory analysis because duration best represents total foraging activity and is less sensitive to how observers split adjacent bouts.",
]];
modelSheet.getRange("A3:H4").format = {
  fill: colors.paleBlue,
  font: { color: colors.navy, size: 11 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};

modelSheet.getRange("A6:H6").merge();
modelSheet.getRange("A6").values = [["Locked primary analysis"]];
modelSheet.getRange("A6:H6").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
const primaryRows = [
  ["Primary estimand", diagnostics.decision.primary_estimand],
  ["Response", "foraging_seconds in each clock-aligned interval"],
  ["Family and link", diagnostics.decision.primary_family],
  ["Exposure", `${diagnostics.decision.offset}; retain all 529 bins, including partial edge bins`],
  ["Fixed effects", "Natural cubic spline of clock time (4 df) + collection_day + post_collection_fraction"],
  ["Repeated structure", "Random intercept for observation_id; inspect residual within-day autocorrelation and add AR(1) sensitivity if needed"],
  ["Interpretation", "Post-collection association at this site, not a causal effect of measured food abundance"],
];
for (let index = 0; index < primaryRows.length; index += 1) {
  const row = 8 + index;
  modelSheet.getRange(`A${row}:B${row}`).merge();
  modelSheet.getRange(`C${row}:H${row}`).merge();
  modelSheet.getRange(`A${row}`).values = [[primaryRows[index][0]]];
  modelSheet.getRange(`C${row}`).values = [[primaryRows[index][1]]];
  modelSheet.getRange(`A${row}:B${row}`).format = {
    fill: colors.paleGray,
    font: { bold: true, color: colors.gray },
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  modelSheet.getRange(`C${row}:H${row}`).format = {
    fill: colors.white,
    font: { color: colors.navy },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  modelSheet.getRange(`A${row}:H${row}`).format.rowHeight = row === 8 ? 44 : 32;
}

modelSheet.getRange("A16:H16").merge();
modelSheet.getRange("A16").values = [["Why this model: empirical distribution checks"]];
modelSheet.getRange("A16:H16").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (const range of ["A17:C17", "D17:E17", "F17:H17"]) modelSheet.getRange(range).merge();
modelSheet.getRange("A17").values = [["Diagnostic"]];
modelSheet.getRange("D17").values = [["Observed value"]];
modelSheet.getRange("F17").values = [["Decision consequence"]];
modelSheet.getRange("A17:H17").format = headerFormat;
const countCheck = diagnostics.count_family_check;
const profiles = diagnostics.full_bin_profiles;
const diagnosticRows = [
  ["Full 30-minute intervals", `${diagnostics.dataset.full_30_minute_rows} of ${diagnostics.dataset.interval_rows}`, "Profiles are compared at equal exposure; partial bins remain in the fitted model through the offset."],
  ["Foraging-duration zeros", `${(profiles.foraging_seconds.zero_fraction * 100).toFixed(2)}%`, "The primary response is non-negative continuous with a genuine point mass at zero."],
  ["Positive-duration skewness", profiles.foraging_seconds.positive.skewness.toFixed(3), "A Gaussian model on raw duration is not appropriate."],
  ["Bout-count variance ÷ mean", countCheck.poisson_dispersion_variance_to_mean.toFixed(3), "Strong overdispersion rejects the Poisson mean–variance assumption."],
  ["Poisson versus NB AIC", `${countCheck.poisson_aic.toFixed(2)} vs ${countCheck.negative_binomial_aic.toFixed(2)}`, `Negative binomial improves AIC by ${countCheck.aic_improvement_nb_over_poisson.toFixed(2)}.`],
  ["Observed versus NB-expected zeros", `${(countCheck.observed_zero_fraction * 100).toFixed(2)}% vs ${(countCheck.negative_binomial_expected_zero_fraction * 100).toFixed(2)}%`, "Negative binomial explains most zero bins; do not add zero inflation automatically."],
  ["Raw adjacent-bin correlation", `r = ${diagnostics.dependence.raw_lag1_foraging_bout_correlation.toFixed(3)}`, "Repeated intervals within a day are dependent and require day-level structure plus a temporal check."],
];
for (let index = 0; index < diagnosticRows.length; index += 1) {
  const row = 18 + index;
  for (const range of [`A${row}:C${row}`, `D${row}:E${row}`, `F${row}:H${row}`]) modelSheet.getRange(range).merge();
  modelSheet.getRange(`A${row}`).values = [[diagnosticRows[index][0]]];
  modelSheet.getRange(`D${row}`).values = [[diagnosticRows[index][1]]];
  modelSheet.getRange(`F${row}`).values = [[diagnosticRows[index][2]]];
  modelSheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  modelSheet.getRange(`A${row}:C${row}`).format.font = { bold: true, color: colors.gray };
  modelSheet.getRange(`D${row}:E${row}`).format.font = { bold: true, color: colors.navy };
  modelSheet.getRange(`A${row}:H${row}`).format.rowHeight = 38;
}

modelSheet.getRange("A27:H27").merge();
modelSheet.getRange("A27").values = [["Pre-specified primary model"]];
modelSheet.getRange("A27:H27").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelSheet.getRange("A28:H29").merge();
modelSheet.getRange("A28").values = [[
  "foraging_seconds ~ ns(clock_hour, df = 4) + collection_day + post_collection_fraction + offset(log(camera_seconds / 1800)) + (1 | observation_id)",
]];
modelSheet.getRange("A28:H29").format = {
  fill: colors.paleBlue,
  font: { name: "Consolas", size: 10, color: colors.navy },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};
modelSheet.getRange("A30:H30").merge();
modelSheet.getRange("A30").values = [[
  "Family: Tweedie with log link. The coefficient for post_collection_fraction is the primary result and will be exponentiated as a rate ratio with a 95% confidence interval.",
]];
modelSheet.getRange("A30:H30").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
modelSheet.getRange("A30:H30").format.rowHeight = 36;

modelSheet.getRange("A32:H32").merge();
modelSheet.getRange("A32").values = [["Confirmatory and sensitivity analyses"]];
modelSheet.getRange("A32:H32").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (const range of ["A33:B33", "C33:F33", "G33:H33"]) modelSheet.getRange(range).merge();
modelSheet.getRange("A33").values = [["Analysis"]];
modelSheet.getRange("C33").values = [["Purpose"]];
modelSheet.getRange("G33").values = [["Status"]];
modelSheet.getRange("A33:H33").format = headerFormat;
const safeguards = [
  ["Negative-binomial bout model", "Same predictors and exposure offset; checks whether the collection association also appears in bout frequency.", "Completed"],
  ["Duration hurdle model", "Separate any-foraging probability from positive foraging duration.", "Completed"],
  ["Within-day AR(1)", "Repeat the primary fit if model residuals retain serial correlation.", "Completed"],
  ["Exclude N3", "N3 has only about 3.3 minutes before collection and may have disproportionate leverage.", "Completed"],
  ["15- and 60-minute bins", "Check that the conclusion does not depend on the chosen 30-minute aggregation.", "Completed"],
  ["Time since collection", "Estimate whether the post-collection association decays; do not replace the primary pre/post test.", "Exploratory"],
];
for (let index = 0; index < safeguards.length; index += 1) {
  const row = 34 + index;
  for (const range of [`A${row}:B${row}`, `C${row}:F${row}`, `G${row}:H${row}`]) modelSheet.getRange(range).merge();
  modelSheet.getRange(`A${row}`).values = [[safeguards[index][0]]];
  modelSheet.getRange(`C${row}`).values = [[safeguards[index][1]]];
  modelSheet.getRange(`G${row}`).values = [[safeguards[index][2]]];
  modelSheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  modelSheet.getRange(`A${row}:B${row}`).format.font = { bold: true, color: colors.navy };
  modelSheet.getRange(`G${row}:H${row}`).format.font = { bold: true, color: colors.teal };
  modelSheet.getRange(`A${row}:H${row}`).format.rowHeight = 40;
}

modelSheet.getRange("A41:H41").merge();
modelSheet.getRange("A41").values = [["Interpretation guardrails"]];
modelSheet.getRange("A41:H41").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelSheet.getRange("A42:H45").merge(true);
modelSheet.getRange("A42:A45").values = [
  ["• Collection timing is a proxy for a hypothesized accessible-food pulse; accessible food was not quantified."],
  ["• Association is estimated within one site and does not establish a general causal effect of garbage collection."],
  ["• Unbanded birds preclude individual random effects, dominance ranks, or stable hierarchy claims."],
  ["• Zero-inflated models will be considered only if residual diagnostics show lack of fit after covariates and overdispersion are handled."],
];
modelSheet.getRange("A42:H45").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
modelSheet.getRange("A42:H45").format.rowHeight = 30;

modelSheet.getRange("A47:H47").merge();
modelSheet.getRange("A47").values = [["Method references"]];
modelSheet.getRange("A47:H47").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
const methodSources = [
  ["Overdispersion and zeros", "https://doi.org/10.1002/env.702"],
  ["Tweedie ecological longitudinal model", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4964939/"],
  ["Hierarchical smooth time effects", "https://doi.org/10.7717/peerj.6876"],
  ["Current glmmTMB family documentation", "https://glmmtmb.github.io/glmmTMB/reference/nbinom2.html"],
];
for (let index = 0; index < methodSources.length; index += 1) {
  const row = 48 + index;
  modelSheet.getRange(`A${row}:B${row}`).merge();
  modelSheet.getRange(`C${row}:H${row}`).merge();
  modelSheet.getRange(`A${row}`).values = [[methodSources[index][0]]];
  modelSheet.getRange(`C${row}`).values = [[methodSources[index][1]]];
  modelSheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  modelSheet.getRange(`A${row}:B${row}`).format.font = { bold: true, color: colors.gray };
  modelSheet.getRange(`C${row}:H${row}`).format.font = { color: "#1F5A8A", underline: true };
  modelSheet.getRange(`A${row}:H${row}`).format.rowHeight = 26;
}
for (const [column, width] of Object.entries({ A: 18, B: 18, C: 19, D: 19, E: 19, F: 19, G: 18, H: 18 })) {
  setColumnWidth(modelSheet, column, 51, width);
}
modelSheet.freezePanes.freezeRows(1);

// Fitted locked model and all pre-declared checks.
const primaryResult = modelResults.primary;
const modelDiagnostic = modelResults.diagnostic_summary;
modelResultsSheet.showGridLines = false;
modelResultsSheet.getRange("A1:H1").merge();
modelResultsSheet.getRange("A1").values = [["Locked model results — Foraging after garbage collection"]];
modelResultsSheet.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 17 },
  verticalAlignment: "center",
};
modelResultsSheet.getRange("A1:H1").format.rowHeight = 30;
modelResultsSheet.getRange("A3:H4").merge();
modelResultsSheet.getRange("A3").values = [[modelResults.headline]];
modelResultsSheet.getRange("A3:H4").format = {
  fill: colors.paleBlue,
  font: { bold: true, color: colors.navy, size: 13 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};
modelResultsSheet.getRange("A5:H5").merge();
modelResultsSheet.getRange("A5").values = [["Evidence status: positive direction, statistically inconclusive"]];
modelResultsSheet.getRange("A5:H5").format = {
  fill: colors.paleGold,
  font: { bold: true, color: "#5B4700", size: 12 },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.gold },
};

const cardLabels = ["Adjusted rate ratio", "Wald 95% CI", "Two-sided p-value", "Day-bootstrap 95% CI"];
const cardValues = [
  primaryResult.rate_ratio,
  `${primaryResult.ci_low.toFixed(2)}–${primaryResult.ci_high.toFixed(2)}`,
  primaryResult.p_value,
  `${modelDiagnostic.bootstrap_ci_low.toFixed(2)}–${modelDiagnostic.bootstrap_ci_high.toFixed(2)}`,
];
const cardRanges = ["A7:B7", "C7:D7", "E7:F7", "G7:H7"];
const valueRanges = ["A8:B9", "C8:D9", "E8:F9", "G8:H9"];
for (let index = 0; index < cardLabels.length; index += 1) {
  modelResultsSheet.getRange(cardRanges[index]).merge();
  modelResultsSheet.getRange(valueRanges[index]).merge();
  modelResultsSheet.getRange(cardRanges[index].split(":")[0]).values = [[cardLabels[index]]];
  modelResultsSheet.getRange(valueRanges[index].split(":")[0]).values = [[cardValues[index]]];
  modelResultsSheet.getRange(cardRanges[index]).format = {
    fill: colors.teal,
    font: { bold: true, color: colors.white },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
  modelResultsSheet.getRange(valueRanges[index]).format = {
    fill: colors.white,
    font: { bold: true, color: colors.navy, size: 18 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
}
modelResultsSheet.getRange("A8:B9").format.numberFormat = "0.00";
modelResultsSheet.getRange("E8:F9").format.numberFormat = "0.000";

modelResultsSheet.getRange("A11:H11").merge();
modelResultsSheet.getRange("A11").values = [["What the data support"]];
modelResultsSheet.getRange("A11:H11").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelResultsSheet.getRange("A12:H14").merge(true);
modelResultsSheet.getRange("A12:A14").values = [
  [`• The central estimate corresponds to ${(100 * (primaryResult.rate_ratio - 1)).toFixed(0)}% greater foraging activity after collection ended, after adjustment.`],
  [`• The model-based interval remains compatible with effects from ${(100 * (primaryResult.ci_low - 1)).toFixed(0)}% to +${(100 * (primaryResult.ci_high - 1)).toFixed(0)}%; the bootstrap interval is wider.`],
  [`• All 25 leave-one-day-out fits remain positive (rate-ratio range ${modelDiagnostic.leave_one_out_min.toFixed(2)}–${modelDiagnostic.leave_one_out_max.toFixed(2)}), but precision remains insufficient for a definitive effect claim.`],
];
modelResultsSheet.getRange("A12:H14").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
modelResultsSheet.getRange("A12:H14").format.rowHeight = 32;

modelResultsSheet.getRange("A16:H16").merge();
modelResultsSheet.getRange("A16").values = [["Primary, confirmatory, and sensitivity estimates"]];
modelResultsSheet.getRange("A16:H16").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelResultsSheet.getRange("A17:H17").values = [["Analysis", "Response", "Bin (min)", "Rate ratio", "CI lower", "CI upper", "p-value", "Direction and precision"]];
const estimateRows = modelResults.estimates.map((row) => [
  row.analysis,
  row.response,
  row.bin_minutes,
  row.rate_ratio,
  row.ci_low,
  row.ci_high,
  row.p_value,
  row.rate_ratio > 1 ? "Positive; interval includes 1" : "Negative; interval includes 1",
]);
modelResultsSheet.getRange(`A18:H${17 + estimateRows.length}`).values = estimateRows;
styleFlatTable(
  modelResultsSheet,
  modelResultsSheet.getRange(`A17:H${17 + estimateRows.length}`),
  modelResultsSheet.getRange("A17:H17"),
);
addTable(modelResultsSheet, `A17:H${17 + estimateRows.length}`, "LockedModelResultsTable", "TableStyleMedium4");
modelResultsSheet.getRange(`C18:C${17 + estimateRows.length}`).format.numberFormat = "0";
modelResultsSheet.getRange(`D18:F${17 + estimateRows.length}`).format.numberFormat = "0.00";
modelResultsSheet.getRange(`G18:G${17 + estimateRows.length}`).format.numberFormat = "0.000";
modelResultsSheet.getRange(`A18:H${17 + estimateRows.length}`).format.wrapText = true;
modelResultsSheet.getRange(`A18:H${17 + estimateRows.length}`).format.rowHeight = 34;
modelResultsSheet.getRange(`H18:H${17 + estimateRows.length}`).conditionalFormats.add("containsText", {
  text: "Positive",
  format: { fill: colors.paleGreen, font: { bold: true, color: colors.green } },
});

modelResultsSheet.getRange("A28:H28").merge();
modelResultsSheet.getRange("A28").values = [["Model adequacy and stability"]];
modelResultsSheet.getRange("A28:H28").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (const range of ["A29:C29", "D29:E29", "F29:H29"]) modelResultsSheet.getRange(range).merge();
modelResultsSheet.getRange("A29").values = [["Check"]];
modelResultsSheet.getRange("D29").values = [["Observed result"]];
modelResultsSheet.getRange("F29").values = [["Interpretation"]];
modelResultsSheet.getRange("A29:H29").format = headerFormat;
const randomEffect = modelResults.smooth_terms[0];
const adequacyRows = [
  ["Convergence", primaryResult.convergence, "Full convergence; no rank deficiency was detected."],
  ["Tweedie zero fit", `${modelDiagnostic.observed_zero_intervals.toFixed(0)} observed; ${modelDiagnostic.expected_zero_intervals.toFixed(1)} expected`, "The selected family reproduces the observed mass at zero closely."],
  ["Tweedie power", modelDiagnostic.tweedie_power.toFixed(3), "Within the compound Poisson–Gamma range of 1 to 2."],
  ["Residual lag-1 correlation", primaryResult.residual_lag1.toFixed(3), "Temporal dependence falls from 0.407 raw to a negligible residual value."],
  ["AR(1) sensitivity", `RR ${modelResults.estimates.find((row) => row.analysis === "AR(1) temporal sensitivity").rate_ratio.toFixed(2)}`, "Essentially identical to the primary estimate."],
  ["Day-level heterogeneity", `edf ${randomEffect.edf.toFixed(1)}; p < 0.001`, "Substantial variation among observation days supports the random day effect."],
  ["Day-stratified bootstrap", `${(100 * modelDiagnostic.bootstrap_positive_fraction).toFixed(0)}% positive`, `400/400 fits converged; percentile interval ${modelDiagnostic.bootstrap_ci_low.toFixed(2)}–${modelDiagnostic.bootstrap_ci_high.toFixed(2)}.`],
  ["Leave-one-day-out", `${modelDiagnostic.leave_one_out_positive_fits.toFixed(0)}/25 positive`, "The estimated direction is not driven by any single day."],
];
for (let index = 0; index < adequacyRows.length; index += 1) {
  const row = 30 + index;
  for (const range of [`A${row}:C${row}`, `D${row}:E${row}`, `F${row}:H${row}`]) modelResultsSheet.getRange(range).merge();
  modelResultsSheet.getRange(`A${row}`).values = [[adequacyRows[index][0]]];
  modelResultsSheet.getRange(`D${row}`).values = [[adequacyRows[index][1]]];
  modelResultsSheet.getRange(`F${row}`).values = [[adequacyRows[index][2]]];
  modelResultsSheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  modelResultsSheet.getRange(`A${row}:C${row}`).format.font = { bold: true, color: colors.gray };
  modelResultsSheet.getRange(`D${row}:E${row}`).format.font = { bold: true, color: colors.navy };
  modelResultsSheet.getRange(`A${row}:H${row}`).format.rowHeight = 36;
}

modelResultsSheet.getRange("A39:H39").merge();
modelResultsSheet.getRange("A39").values = [["Provisional manuscript Results text"]];
modelResultsSheet.getRange("A39:H39").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelResultsSheet.getRange("A40:H44").merge();
modelResultsSheet.getRange("A40").values = [[
  `We analyzed 529 clock-aligned intervals from 25 observation days using a Tweedie mixed-effects model with camera exposure as an offset, a four-degree-of-freedom spline for time of day, a collection-day indicator, and observation day as a random effect. Foraging activity after garbage collection ended was estimated to be ${primaryResult.rate_ratio.toFixed(2)} times the pre-collection activity on collection days (95% CI ${primaryResult.ci_low.toFixed(2)}–${primaryResult.ci_high.toFixed(2)}; p = ${primaryResult.p_value.toFixed(3)}). The estimate remained positive after excluding N3, changing the interval width to 15 or 60 minutes, adding an AR(1) correlation, and separating foraging occurrence from positive duration. However, all confidence intervals included 1, and a day-stratified bootstrap produced a 95% interval of ${modelDiagnostic.bootstrap_ci_low.toFixed(2)}–${modelDiagnostic.bootstrap_ci_high.toFixed(2)}. Thus, the results were consistent with increased post-collection foraging, but the study did not estimate the association precisely enough to exclude no change or a modest decrease.`,
]];
modelResultsSheet.getRange("A40:H44").format = {
  fill: colors.paleBlue,
  font: { color: colors.navy, size: 11 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};

modelResultsSheet.getRange("A46:H46").merge();
modelResultsSheet.getRange("A46").values = [["Reporting guardrails"]];
modelResultsSheet.getRange("A46:H46").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelResultsSheet.getRange("A47:H49").merge(true);
modelResultsSheet.getRange("A47:A49").values = [
  ["• Do not write that collection had no effect; the estimate is imprecise rather than evidence of equivalence."],
  ["• Do not describe the positive central estimate as a demonstrated increase because its interval includes 1."],
  ["• Retain the event-centred association language: food abundance and causal mechanisms were not measured."],
];
modelResultsSheet.getRange("A47:H49").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
modelResultsSheet.getRange("A47:H49").format.rowHeight = 30;

modelResultsSheet.getRange("A51:H51").merge();
modelResultsSheet.getRange("A51").values = [["Reproducibility"]];
modelResultsSheet.getRange("A51:H51").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
modelResultsSheet.getRange("A52:H54").merge(true);
modelResultsSheet.getRange("A52:A54").values = [
  [`R ${modelResults.software.R}; mgcv ${modelResults.software.mgcv}; nlme ${modelResults.software.nlme}`],
  ["Primary family: Tweedie log link; estimation method: REML; primary interval: 30 minutes."],
  ["All models use the audited interval data and the specification locked before fitting."],
];
modelResultsSheet.getRange("A52:H54").format = { fill: colors.paleGray, font: { color: "#273746" }, wrapText: true };
modelResultsSheet.getRange("A52:H54").format.rowHeight = 25;
for (const [column, width] of Object.entries({ A: 36, B: 20, C: 12, D: 14, E: 14, F: 14, G: 13, H: 31 })) {
  setColumnWidth(modelResultsSheet, column, 54, width);
}
modelResultsSheet.freezePanes.freezeRows(1);

// Mechanism-level decomposition of total foraging activity.
const attendanceResult = decompositionResults.attendance;
const intensityResult = decompositionResults.intensity;
const attendanceDiagnostic = decompositionResults.diagnostics.find((row) => row.mechanism === "Patch attendance");
const intensityDiagnostic = decompositionResults.diagnostics.find((row) => row.mechanism === "Conditional foraging intensity");
const decompositionStability = decompositionResults.stability;
mechanismSheet.showGridLines = false;
mechanismSheet.getRange("A1:H1").merge();
mechanismSheet.getRange("A1").values = [["Mechanism results — Patch attendance versus foraging intensity"]];
mechanismSheet.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 17 },
  verticalAlignment: "center",
};
mechanismSheet.getRange("A1:H1").format.rowHeight = 30;
mechanismSheet.getRange("A3:H4").merge();
mechanismSheet.getRange("A3").values = [[decompositionResults.headline]];
mechanismSheet.getRange("A3:H4").format = {
  fill: colors.paleBlue,
  font: { bold: true, color: colors.navy, size: 13 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};
mechanismSheet.getRange("A5:H5").merge();
mechanismSheet.getRange("A5").values = [["Mechanistic pattern: attendance-dominant, but attendance remains imprecisely estimated"]];
mechanismSheet.getRange("A5:H5").format = {
  fill: colors.paleGold,
  font: { bold: true, color: "#5B4700", size: 12 },
  horizontalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.gold },
};

const mechanismCardLabels = ["Focal attendance RR", "Attendance 95% CI", "Conditional intensity RR", "Intensity 95% CI"];
const mechanismCardValues = [
  attendanceResult.effect_ratio,
  `${attendanceResult.ci_low.toFixed(2)}–${attendanceResult.ci_high.toFixed(2)}`,
  intensityResult.effect_ratio,
  `${intensityResult.ci_low.toFixed(2)}–${intensityResult.ci_high.toFixed(2)}`,
];
const mechanismCardRanges = ["A7:B7", "C7:D7", "E7:F7", "G7:H7"];
const mechanismValueRanges = ["A8:B9", "C8:D9", "E8:F9", "G8:H9"];
for (let index = 0; index < mechanismCardLabels.length; index += 1) {
  mechanismSheet.getRange(mechanismCardRanges[index]).merge();
  mechanismSheet.getRange(mechanismValueRanges[index]).merge();
  mechanismSheet.getRange(mechanismCardRanges[index].split(":")[0]).values = [[mechanismCardLabels[index]]];
  mechanismSheet.getRange(mechanismValueRanges[index].split(":")[0]).values = [[mechanismCardValues[index]]];
  mechanismSheet.getRange(mechanismCardRanges[index]).format = {
    fill: colors.teal,
    font: { bold: true, color: colors.white },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
  mechanismSheet.getRange(mechanismValueRanges[index]).format = {
    fill: colors.white,
    font: { bold: true, color: colors.navy, size: 18 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
}
mechanismSheet.getRange("A8:B9").format.numberFormat = "0.00";
mechanismSheet.getRange("E8:F9").format.numberFormat = "0.00";

mechanismSheet.getRange("A11:H11").merge();
mechanismSheet.getRange("A11").values = [["Mechanistic decomposition"]];
mechanismSheet.getRange("A11:H11").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
mechanismSheet.getRange("A12:H15").merge(true);
mechanismSheet.getRange("A12:A15").values = [
  ["• Total foraging per camera time can be viewed descriptively as focal-visible time per camera time × foraging per focal-visible time."],
  [`• Focal-visible time was estimated to increase ${(100 * (attendanceResult.effect_ratio - 1)).toFixed(0)}% after collection; conditional intensity changed only ${(100 * (intensityResult.effect_ratio - 1)).toFixed(0)}%.`],
  [`• Attendance accounts for approximately ${(100 * decompositionResults.combined.attendance_log_share).toFixed(0)}% of the summed log-scale mechanism estimates; this is descriptive, not formal mediation.`],
  [`• The mechanism-product estimate is ${decompositionResults.combined.product_ratio.toFixed(2)}, close to the primary total-foraging estimate of ${decompositionResults.combined.total_primary_ratio.toFixed(2)}, but separate nonlinear models are not required to multiply exactly.`],
];
mechanismSheet.getRange("A12:H15").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
mechanismSheet.getRange("A12:H15").format.rowHeight = 31;

mechanismSheet.getRange("A17:H17").merge();
mechanismSheet.getRange("A17").values = [["Primary and sensitivity estimates"]];
mechanismSheet.getRange("A17:H17").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
mechanismSheet.getRange("A18:H18").values = [["Analysis", "Mechanism", "Ratio type", "Bin", "Ratio", "CI lower", "CI upper", "p-value"]];
const mechanismEstimateRows = decompositionResults.estimates.map((row) => [
  row.analysis,
  row.mechanism,
  row.ratio_type,
  row.bin_minutes,
  row.effect_ratio,
  row.ci_low,
  row.ci_high,
  row.p_value,
]);
mechanismSheet.getRange(`A19:H${18 + mechanismEstimateRows.length}`).values = mechanismEstimateRows;
styleFlatTable(
  mechanismSheet,
  mechanismSheet.getRange(`A18:H${18 + mechanismEstimateRows.length}`),
  mechanismSheet.getRange("A18:H18"),
);
addTable(mechanismSheet, `A18:H${18 + mechanismEstimateRows.length}`, "MechanismResultsTable", "TableStyleMedium4");
mechanismSheet.getRange(`D19:D${18 + mechanismEstimateRows.length}`).format.numberFormat = "0";
mechanismSheet.getRange(`E19:G${18 + mechanismEstimateRows.length}`).format.numberFormat = "0.00";
mechanismSheet.getRange(`H19:H${18 + mechanismEstimateRows.length}`).format.numberFormat = "0.000";
mechanismSheet.getRange(`A19:H${18 + mechanismEstimateRows.length}`).format.wrapText = true;
mechanismSheet.getRange(`A19:H${18 + mechanismEstimateRows.length}`).format.rowHeight = 32;

mechanismSheet.getRange("A31:H31").merge();
mechanismSheet.getRange("A31").values = [["Adequacy and stability"]];
mechanismSheet.getRange("A31:H31").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (const range of ["A32:C32", "D32:E32", "F32:H32"]) mechanismSheet.getRange(range).merge();
mechanismSheet.getRange("A32").values = [["Check"]];
mechanismSheet.getRange("D32").values = [["Observed result"]];
mechanismSheet.getRange("F32").values = [["Interpretation"]];
mechanismSheet.getRange("A32:H32").format = headerFormat;
const mechanismAdequacyRows = [
  ["Attendance zero fit", `${attendanceDiagnostic.observed_zero_intervals.toFixed(0)} observed; ${attendanceDiagnostic.expected_zero_intervals.toFixed(1)} expected`, "Tweedie family reproduces the attendance zeros reasonably closely."],
  ["Intensity zero fit", `${intensityDiagnostic.observed_zero_intervals.toFixed(0)} observed; ${intensityDiagnostic.expected_zero_intervals.toFixed(1)} expected`, "No additional zero-inflation component is indicated."],
  ["Residual temporal correlation", `attendance ${attendanceResult.residual_lag1.toFixed(3)}; intensity ${intensityResult.residual_lag1.toFixed(3)}`, "Little temporal dependence remains after adjustment."],
  ["Fractional-logit sensitivity", `OR ${decompositionResults.fractional_logit.effect_ratio.toFixed(2)}; p = ${decompositionResults.fractional_logit.p_value.toFixed(3)}`, "An alternative bounded-proportion model also shows little intensity change."],
  ["Attendance bootstrap", `${(100 * decompositionStability.attendance_bootstrap_fraction_above_one).toFixed(0)}% positive`, `400 fits; percentile interval ${decompositionStability.attendance_bootstrap_ci_low.toFixed(2)}–${decompositionStability.attendance_bootstrap_ci_high.toFixed(2)}.`],
  ["Intensity bootstrap", `${(100 * decompositionStability.intensity_bootstrap_fraction_above_one).toFixed(0)}% positive`, `400 fits; percentile interval ${decompositionStability.intensity_bootstrap_ci_low.toFixed(2)}–${decompositionStability.intensity_bootstrap_ci_high.toFixed(2)}.`],
  ["Attendance leave-one-day-out", `${decompositionStability.attendance_loo_positive.toFixed(0)}/25 positive`, `Rate-ratio range ${decompositionStability.attendance_loo_min.toFixed(2)}–${decompositionStability.attendance_loo_max.toFixed(2)}.`],
  ["Intensity leave-one-day-out", `${decompositionStability.intensity_loo_positive.toFixed(0)}/25 positive`, `Rate-ratio range ${decompositionStability.intensity_loo_min.toFixed(2)}–${decompositionStability.intensity_loo_max.toFixed(2)}; values remain close to 1.`],
];
for (let index = 0; index < mechanismAdequacyRows.length; index += 1) {
  const row = 33 + index;
  for (const range of [`A${row}:C${row}`, `D${row}:E${row}`, `F${row}:H${row}`]) mechanismSheet.getRange(range).merge();
  mechanismSheet.getRange(`A${row}`).values = [[mechanismAdequacyRows[index][0]]];
  mechanismSheet.getRange(`D${row}`).values = [[mechanismAdequacyRows[index][1]]];
  mechanismSheet.getRange(`F${row}`).values = [[mechanismAdequacyRows[index][2]]];
  mechanismSheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  mechanismSheet.getRange(`A${row}:C${row}`).format.font = { bold: true, color: colors.gray };
  mechanismSheet.getRange(`D${row}:E${row}`).format.font = { bold: true, color: colors.navy };
  mechanismSheet.getRange(`A${row}:H${row}`).format.rowHeight = 36;
}

mechanismSheet.getRange("A42:H42").merge();
mechanismSheet.getRange("A42").values = [["Provisional manuscript Results text"]];
mechanismSheet.getRange("A42:H42").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
mechanismSheet.getRange("A43:H47").merge();
mechanismSheet.getRange("A43").values = [[
  `To examine the behavioral pathway underlying the total-foraging estimate, we separated coded focal-visible time per camera exposure from foraging time conditional on focal visibility. Focal-visible time after garbage collection ended was estimated to be ${attendanceResult.effect_ratio.toFixed(2)} times the pre-collection value on collection days (95% CI ${attendanceResult.ci_low.toFixed(2)}–${attendanceResult.ci_high.toFixed(2)}; p = ${attendanceResult.p_value.toFixed(3)}). In contrast, foraging activity per unit of focal-visible time changed little (rate ratio ${intensityResult.effect_ratio.toFixed(2)}, 95% CI ${intensityResult.ci_low.toFixed(2)}–${intensityResult.ci_high.toFixed(2)}; p = ${intensityResult.p_value.toFixed(3)}). The intensity conclusion was similar under a quasibinomial proportion model (odds ratio ${decompositionResults.fractional_logit.effect_ratio.toFixed(2)}, 95% CI ${decompositionResults.fractional_logit.ci_low.toFixed(2)}–${decompositionResults.fractional_logit.ci_high.toFixed(2)}). Attendance estimates remained positive under all leave-one-day-out analyses and alternative interval widths. These results suggest that the positive total-foraging estimate was associated primarily with greater focal patch-use time rather than a higher allocation of visible time to foraging; however, the attendance confidence interval included 1.`,
]];
mechanismSheet.getRange("A43:H47").format = {
  fill: colors.paleBlue,
  font: { color: colors.navy, size: 11 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};

mechanismSheet.getRange("A49:H49").merge();
mechanismSheet.getRange("A49").values = [["Interpretation guardrails"]];
mechanismSheet.getRange("A49:H49").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
mechanismSheet.getRange("A50:H53").merge(true);
mechanismSheet.getRange("A50:A53").values = [
  ["• Focal-visible time is a coded focal-subject exposure measure; it is not total grackle abundance or all-bird occupancy."],
  ["• More focal-visible time may reflect longer visits, more frequent focal presence, or focal-selection dynamics; these cannot be separated."],
  ["• The comparison is a mechanistic decomposition, not a formal causal mediation analysis."],
  ["• Food abundance and food intake were not measured; retain association language."],
];
mechanismSheet.getRange("A50:H53").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
mechanismSheet.getRange("A50:H53").format.rowHeight = 29;

mechanismSheet.getRange("A55:H55").merge();
mechanismSheet.getRange("A55").values = [["Response definitions"]];
mechanismSheet.getRange("A55:H55").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
mechanismSheet.getRange("A56:H58").merge(true);
mechanismSheet.getRange("A56:A58").values = [
  ["Attendance: focal_visible_seconds with log(camera_seconds / nominal interval) as the exposure offset."],
  ["Conditional intensity: foraging_seconds among focal-visible intervals with log(focal_visible_seconds / nominal interval) as the exposure offset."],
  ["Both primary mechanism models: Tweedie log link, 4-df clock-time spline, collection-day baseline, post-collection fraction, and random observation-day effect."],
];
mechanismSheet.getRange("A56:H58").format = { fill: colors.paleGray, font: { color: "#273746" }, wrapText: true };
mechanismSheet.getRange("A56:H58").format.rowHeight = 27;
for (const [column, width] of Object.entries({ A: 37, B: 29, C: 14, D: 11, E: 13, F: 13, G: 13, H: 14 })) {
  setColumnWidth(mechanismSheet, column, 58, width);
}
mechanismSheet.freezePanes.freezeRows(1);

// Opportunity-adjusted displacement analysis.
const displacementProfile = displacementResults.profile;
const displacementCamera = displacementResults.model_estimates.find(
  (row) => row.analysis === "Total displacement per camera exposure",
);
const displacementPrimary = displacementResults.model_estimates.find(
  (row) => row.analysis === "Opportunity-adjusted displacement rate",
);
const displacementForaging = displacementResults.model_estimates.find(
  (row) => row.analysis === "Displacement rate during foraging",
);
const displacementLoo = displacementResults.leave_one_day_out.find(
  (row) => row.estimate === "opportunity_adjusted_rate_ratio",
);
const displacementBootstrap = displacementResults.bootstrap.opportunity_adjusted;
const directionTest = displacementResults.directional_tests[0];
const completenessTest = displacementResults.directional_tests[1];

displacementSheet.showGridLines = false;
displacementSheet.getRange("A1:H1").merge();
displacementSheet.getRange("A1").values = [["Displacement activity after garbage collection"]];
displacementSheet.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 17 },
  verticalAlignment: "center",
};
displacementSheet.getRange("A1:H1").format.rowHeight = 30;

displacementSheet.getRange("A3:H4").merge();
displacementSheet.getRange("A3").values = [[
  `After accounting for focal-visible opportunity, the post-collection displacement-rate estimate was ${displacementPrimary.effect_ratio.toFixed(2)} (95% CI ${displacementPrimary.ci_low.toFixed(2)}–${displacementPrimary.ci_high.toFixed(2)}; p = ${displacementPrimary.p_value.toFixed(3)}). The data do not demonstrate an increase beyond focal presence.`,
]];
displacementSheet.getRange("A3:H4").format = {
  fill: colors.paleBlue,
  font: { bold: true, color: colors.navy, size: 13 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};
displacementSheet.getRange("A5:H5").merge();
displacementSheet.getRange("A5").values = [["Evidence status: positive central estimate, but statistically inconclusive and not adjusted for dyadic opportunity"]];
displacementSheet.getRange("A5:H5").format = {
  fill: colors.paleGold,
  font: { bold: true, color: "#5B4700", size: 12 },
  horizontalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.gold },
};

const displacementCardLabels = [
  "Total activity RR",
  "Opportunity-adjusted RR",
  "Adjusted 95% CI",
  "Eligible events",
];
const displacementCardValues = [
  displacementCamera.effect_ratio,
  displacementPrimary.effect_ratio,
  `${displacementPrimary.ci_low.toFixed(2)}–${displacementPrimary.ci_high.toFixed(2)}`,
  displacementProfile.exposure_eligible_displacement_events,
];
const displacementCardRanges = ["A7:B7", "C7:D7", "E7:F7", "G7:H7"];
const displacementValueRanges = ["A8:B9", "C8:D9", "E8:F9", "G8:H9"];
for (let index = 0; index < displacementCardLabels.length; index += 1) {
  displacementSheet.getRange(displacementCardRanges[index]).merge();
  displacementSheet.getRange(displacementValueRanges[index]).merge();
  displacementSheet.getRange(displacementCardRanges[index].split(":")[0]).values = [[displacementCardLabels[index]]];
  displacementSheet.getRange(displacementValueRanges[index].split(":")[0]).values = [[displacementCardValues[index]]];
  displacementSheet.getRange(displacementCardRanges[index]).format = {
    fill: colors.teal,
    font: { bold: true, color: colors.white },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
  displacementSheet.getRange(displacementValueRanges[index]).format = {
    fill: colors.white,
    font: { bold: true, color: colors.navy, size: 18 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
}
displacementSheet.getRange("A8:D9").format.numberFormat = "0.00";
displacementSheet.getRange("G8:H9").format.numberFormat = "0";

displacementSheet.getRange("A11:H11").merge();
displacementSheet.getRange("A11").values = [["What changes when opportunity is considered"]];
displacementSheet.getRange("A11:H11").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A12:H15").merge(true);
displacementSheet.getRange("A12:A15").values = [
  [`• The raw collection-day rate rose from ${displacementProfile.collection_day_pre.events_per_visible_hour.toFixed(2)} to ${displacementProfile.collection_day_post.events_per_visible_hour.toFixed(2)} displacements per focal-visible hour after collection.`],
  [`• Per camera time, total displacement activity had a positive but imprecise estimate (RR ${displacementCamera.effect_ratio.toFixed(2)}, 95% CI ${displacementCamera.ci_low.toFixed(2)}–${displacementCamera.ci_high.toFixed(2)}).`],
  [`• Once focal-visible time was the exposure, the estimate fell to RR ${displacementPrimary.effect_ratio.toFixed(2)}; this remaining change is compatible with both a substantial decrease and a large increase.`],
  [`• Restricting the response and exposure to coded foraging produced RR ${displacementForaging.effect_ratio.toFixed(2)} (95% CI ${displacementForaging.ci_low.toFixed(2)}–${displacementForaging.ci_high.toFixed(2)}), the same substantive conclusion.`],
];
displacementSheet.getRange("A12:H15").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
displacementSheet.getRange("A12:H15").format.rowHeight = 31;

displacementSheet.getRange("A17:H17").merge();
displacementSheet.getRange("A17").values = [["Observed phase-specific rates"]];
displacementSheet.getRange("A17:H17").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A18:H18").values = [[
  "Phase", "Days", "Visible hours", "Events", "Events / visible h", "Focal-to-others", "Others-to-focal", "Unspecified",
]];
const displacementPhaseRows = displacementResults.phase_summary.map((row) => [
  row.phase,
  row.observation_days,
  row.focal_visible_hours,
  row.displacement_events,
  row.events_per_visible_hour,
  row.focal_to_others,
  row.others_to_focal,
  row.unspecified,
]);
displacementSheet.getRange("A19:H21").values = displacementPhaseRows;
styleFlatTable(displacementSheet, displacementSheet.getRange("A18:H21"), displacementSheet.getRange("A18:H18"));
addTable(displacementSheet, "A18:H21", "DisplacementPhaseTable", "TableStyleMedium4");
displacementSheet.getRange("B19:B21").format.numberFormat = "0";
displacementSheet.getRange("C19:C21").format.numberFormat = "0.00";
displacementSheet.getRange("D19:D21").format.numberFormat = "0";
displacementSheet.getRange("E19:E21").format.numberFormat = "0.00";
displacementSheet.getRange("F19:H21").format.numberFormat = "0";
displacementSheet.getRange("A19:H21").format.rowHeight = 30;

displacementSheet.getRange("A23:H23").merge();
displacementSheet.getRange("A23").values = [["Primary and sensitivity estimates"]];
displacementSheet.getRange("A23:H23").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A24:H24").values = [["Analysis", "Exposure", "Bin", "Events", "Ratio", "CI lower", "CI upper", "p-value"]];
const displacementAnalysisOrder = [
  "Total displacement per camera exposure",
  "Opportunity-adjusted displacement rate",
  "Displacement rate during foraging",
  "Opportunity-adjusted excluding N3",
  "Opportunity-adjusted 15-minute sensitivity",
  "Opportunity-adjusted 60-minute sensitivity",
  "Opportunity-adjusted plus observer",
  "Opportunity-adjusted quasi-Poisson sensitivity",
];
const displacementEstimateRows = displacementAnalysisOrder.map((analysis) => {
  const row = displacementResults.model_estimates.find((candidate) => candidate.analysis === analysis);
  return [
    row.analysis,
    row.exposure,
    row.bin_minutes,
    row.events,
    row.effect_ratio,
    row.ci_low,
    row.ci_high,
    row.p_value,
  ];
});
displacementSheet.getRange("A25:H32").values = displacementEstimateRows;
styleFlatTable(displacementSheet, displacementSheet.getRange("A24:H32"), displacementSheet.getRange("A24:H24"));
addTable(displacementSheet, "A24:H32", "DisplacementModelTable", "TableStyleMedium4");
displacementSheet.getRange("C25:D32").format.numberFormat = "0";
displacementSheet.getRange("E25:G32").format.numberFormat = "0.00";
displacementSheet.getRange("H25:H32").format.numberFormat = "0.000";
displacementSheet.getRange("A25:H32").format.wrapText = true;
displacementSheet.getRange("A25:H32").format.rowHeight = 32;

displacementSheet.getRange("A34:H34").merge();
displacementSheet.getRange("A34").values = [["Adequacy and stability"]];
displacementSheet.getRange("A34:H34").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (const range of ["A35:C35", "D35:E35", "F35:H35"]) displacementSheet.getRange(range).merge();
displacementSheet.getRange("A35").values = [["Check"]];
displacementSheet.getRange("D35").values = [["Observed result"]];
displacementSheet.getRange("F35").values = [["Interpretation"]];
displacementSheet.getRange("A35:H35").format = headerFormat;
const displacementAdequacyRows = [
  ["Event-to-exposure audit", `${displacementProfile.events_inside_focal_visible}/139 inside focal visibility`, "One unspecified event outside focal visibility was excluded only from exposure-adjusted models."],
  ["Negative-binomial zero fit", `${displacementPrimary.observed_zeros.toFixed(0)} observed; ${displacementPrimary.expected_zeros.toFixed(1)} expected`, "The selected family reproduces the observed number of zero intervals closely."],
  ["Residual temporal correlation", `lag-1 r = ${displacementPrimary.residual_lag1.toFixed(3)}`, "No meaningful residual within-day autocorrelation remains."],
  ["Day-stratified bootstrap", `${(100 * displacementBootstrap.fraction_above_one).toFixed(0)}% positive`, `400/400 fits; percentile interval ${displacementBootstrap.ci_low.toFixed(2)}–${displacementBootstrap.ci_high.toFixed(2)}.`],
  ["Leave-one-day-out", `${displacementLoo.positive_fits.toFixed(0)}/25 positive`, `Rate-ratio range ${displacementLoo.minimum.toFixed(2)}–${displacementLoo.maximum.toFixed(2)}; direction is not driven by one day.`],
  ["Alternative specifications", "RR 1.08–1.23", "Excluding N3, changing interval width, adding observer, and quasi-Poisson variance all preserve the inconclusive result."],
];
for (let index = 0; index < displacementAdequacyRows.length; index += 1) {
  const row = 36 + index;
  for (const range of [`A${row}:C${row}`, `D${row}:E${row}`, `F${row}:H${row}`]) displacementSheet.getRange(range).merge();
  displacementSheet.getRange(`A${row}`).values = [[displacementAdequacyRows[index][0]]];
  displacementSheet.getRange(`D${row}`).values = [[displacementAdequacyRows[index][1]]];
  displacementSheet.getRange(`F${row}`).values = [[displacementAdequacyRows[index][2]]];
  displacementSheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  displacementSheet.getRange(`A${row}:C${row}`).format.font = { bold: true, color: colors.gray };
  displacementSheet.getRange(`D${row}:E${row}`).format.font = { bold: true, color: colors.navy };
  displacementSheet.getRange(`A${row}:H${row}`).format.rowHeight = 36;
}

displacementSheet.getRange("A43:H43").merge();
displacementSheet.getRange("A43").values = [["Direction data: exploratory only"]];
displacementSheet.getRange("A43:H43").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A44:D44").merge();
displacementSheet.getRange("E44:H44").merge();
displacementSheet.getRange("A44").values = [["Observed direction counts"]];
displacementSheet.getRange("E44").values = [["Exact pre/post comparison"]];
displacementSheet.getRange("A44:H44").format = headerFormat;
displacementSheet.getRange("A45:D47").merge(true);
displacementSheet.getRange("A45:A47").values = [
  [`All recorded: ${displacementProfile.direction_counts.focal_to_others} focal-to-others; ${displacementProfile.direction_counts.others_to_focal} others-to-focal; ${displacementProfile.direction_counts.unspecified} unspecified.`],
  [`Collection pre: ${directionTest.pre_first.toFixed(0)} focal-to-others and ${directionTest.pre_second.toFixed(0)} others-to-focal.`],
  [`Collection post: ${directionTest.post_first.toFixed(0)} focal-to-others and ${directionTest.post_second.toFixed(0)} others-to-focal.`],
];
displacementSheet.getRange("E45:H47").merge(true);
displacementSheet.getRange("E45:E47").values = [
  [`Direction odds ratio ${directionTest.odds_ratio.toFixed(2)} (95% CI ${directionTest.ci_low.toFixed(2)}–${directionTest.ci_high.toFixed(2)}; p = ${directionTest.p_value.toFixed(3)}).`],
  [`Direction-recording completeness OR ${completenessTest.odds_ratio.toFixed(2)} (95% CI ${completenessTest.ci_low.toFixed(2)}–${completenessTest.ci_high.toFixed(2)}; p = ${completenessTest.p_value.toFixed(3)}).`],
  ["Only six directed events occurred before collection; these comparisons cannot establish dominance or rank."],
];
displacementSheet.getRange("A45:H47").format = { fill: colors.paleGray, font: { color: "#273746" }, wrapText: true };
displacementSheet.getRange("A45:H47").format.rowHeight = 35;

displacementSheet.getRange("A49:H49").merge();
displacementSheet.getRange("A49").values = [["Provisional manuscript Results text"]];
displacementSheet.getRange("A49:H49").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A50:H55").merge();
displacementSheet.getRange("A50").values = [[
  `Across 25 observation days, 139 displacement events were recorded. Of these, ${displacementProfile.exposure_eligible_displacement_events} occurred within coded focal visibility and were included in the opportunity-adjusted analysis. On collection days, the unadjusted rate increased from ${displacementProfile.collection_day_pre.events_per_visible_hour.toFixed(2)} events per focal-visible hour before collection ended to ${displacementProfile.collection_day_post.events_per_visible_hour.toFixed(2)} afterward. In a negative-binomial mixed generalized additive model that accounted for time of day, a collection-day baseline, focal-visible exposure, and repeated observation days, the adjusted post-collection rate ratio was ${displacementPrimary.effect_ratio.toFixed(2)} (95% CI ${displacementPrimary.ci_low.toFixed(2)}–${displacementPrimary.ci_high.toFixed(2)}; p = ${displacementPrimary.p_value.toFixed(3)}). Estimates were similar after excluding N3, using 15- or 60-minute intervals, adding observer, and restricting events and exposure to coded foraging. Thus, displacement activity was not estimated precisely enough to demonstrate an increase beyond the greater opportunity associated with focal presence.`,
]];
displacementSheet.getRange("A50:H55").format = {
  fill: colors.paleBlue,
  font: { color: colors.navy, size: 11 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};

displacementSheet.getRange("A57:H57").merge();
displacementSheet.getRange("A57").values = [["Interpretation guardrails"]];
displacementSheet.getRange("A57:H57").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A58:H62").merge(true);
displacementSheet.getRange("A58:A62").values = [
  ["• Focal-visible time adjusts for focal presence, not for the number of conspecifics or possible interaction dyads."],
  [`• ${displacementProfile.direction_counts.unspecified} of 139 events lacked direction; direction-specific conclusions are exploratory.`],
  ["• Unbanded birds preclude individual dominance ranks, stable hierarchies, or repeated-strategy claims."],
  ["• Failure to demonstrate an increase is not evidence that the rates were equivalent; the interval is wide."],
  ["• Collection timing remains a proxy for a hypothesized food pulse; food abundance and causal mechanisms were not measured."],
];
displacementSheet.getRange("A58:H62").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
displacementSheet.getRange("A58:H62").format.rowHeight = 29;

displacementSheet.getRange("A64:H64").merge();
displacementSheet.getRange("A64").values = [["Model definition"]];
displacementSheet.getRange("A64:H64").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
displacementSheet.getRange("A65:H67").merge(true);
displacementSheet.getRange("A65:A67").values = [
  ["Primary response: displacement events occurring within coded focal visibility; exposure offset: log(focal-visible seconds / nominal interval)."],
  ["Predictors: 4-df clock-time spline, collection-day baseline, post-collection indicator, and random observation-day effect."],
  ["Thirty-minute bins were split exactly at collection end; event timestamps and visible exposure therefore remain in the correct phase."],
];
displacementSheet.getRange("A65:H67").format = { fill: colors.paleGray, font: { color: "#273746" }, wrapText: true };
displacementSheet.getRange("A65:H67").format.rowHeight = 27;
for (const [column, width] of Object.entries({ A: 36, B: 23, C: 14, D: 12, E: 14, F: 14, G: 15, H: 15 })) {
  setColumnWidth(displacementSheet, column, 67, width);
}
displacementSheet.freezePanes.freezeRows(1);

// Event-centred analysis of decay in foraging after collection.
const timeDecayPrimary = timeDecayResults.model_estimates.find(
  (row) => row.analysis === "Linear post-collection decay",
);
const timeDecayImmediate = timeDecayResults.model_estimates.find(
  (row) => row.analysis === "Immediate post-collection level",
);
const timeDecayFirstSix = timeDecayResults.model_estimates.find(
  (row) => row.analysis === "Linear decay limited to first 6 hours",
);
const timeDecayBootstrap = timeDecayResults.bootstrap.hourly_decay;
const timeDecayLoo = timeDecayResults.leave_one_day_out.find(
  (row) => row.subset === "All excluded days",
);
const timeDecayZeroObserved = timeDecayResults.model_diagnostics.find(
  (row) => row.metric === "Observed zero intervals",
).value;
const timeDecayZeroExpected = timeDecayResults.model_diagnostics.find(
  (row) => row.metric === "Expected zero intervals",
).value;
const timeDecayResidual = timeDecayResults.model_diagnostics.find(
  (row) => row.metric === "Residual lag-1 correlation",
).value;
const timeDecayClockCorrelation = timeDecayResults.confounding.find(
  (row) => row.metric === "Clock-hour / elapsed-time correlation",
).value;
const timeDecayVif = timeDecayResults.confounding.find(
  (row) => row.metric === "Approximate VIF from weighted R-squared",
).value;
const timeDecayCollectionRange = timeDecayResults.confounding.find(
  (row) => row.metric === "Collection-time range hours",
).value;

timeDecaySheet.showGridLines = false;
timeDecaySheet.getRange("A1:H1").merge();
timeDecaySheet.getRange("A1").values = [["Time since collection and the foraging response"]];
timeDecaySheet.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 17 },
  verticalAlignment: "center",
};
timeDecaySheet.getRange("A1:H1").format.rowHeight = 30;

timeDecaySheet.getRange("A3:H4").merge();
timeDecaySheet.getRange("A3").values = [[
  `The adjusted foraging-rate estimate declined ${(100 * (1 - timeDecayPrimary.effect_ratio)).toFixed(0)}% for each additional hour after collection (hourly RR ${timeDecayPrimary.effect_ratio.toFixed(2)}, 95% CI ${timeDecayPrimary.ci_low.toFixed(2)}–${timeDecayPrimary.ci_high.toFixed(2)}; p = ${timeDecayPrimary.p_value.toFixed(3)}).`,
]];
timeDecaySheet.getRange("A3:H4").format = {
  fill: colors.paleBlue,
  font: { bold: true, color: colors.navy, size: 13 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};
timeDecaySheet.getRange("A5:H5").merge();
timeDecaySheet.getRange("A5").values = [["Evidence status: consistent with a temporary pulse; not proof of food depletion because elapsed time and clock time remain strongly related"]];
timeDecaySheet.getRange("A5:H5").format = {
  fill: colors.paleGold,
  font: { bold: true, color: "#5B4700", size: 12 },
  horizontalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.gold },
};

const timeDecayCardLabels = ["Hourly rate ratio", "Hourly 95% CI", "Bootstrap 95% CI", "Immediate level RR"];
const timeDecayCardValues = [
  timeDecayPrimary.effect_ratio,
  `${timeDecayPrimary.ci_low.toFixed(2)}–${timeDecayPrimary.ci_high.toFixed(2)}`,
  `${timeDecayBootstrap.ci_low.toFixed(2)}–${timeDecayBootstrap.ci_high.toFixed(2)}`,
  timeDecayImmediate.effect_ratio,
];
const timeDecayCardRanges = ["A7:B7", "C7:D7", "E7:F7", "G7:H7"];
const timeDecayValueRanges = ["A8:B9", "C8:D9", "E8:F9", "G8:H9"];
for (let index = 0; index < timeDecayCardLabels.length; index += 1) {
  timeDecaySheet.getRange(timeDecayCardRanges[index]).merge();
  timeDecaySheet.getRange(timeDecayValueRanges[index]).merge();
  timeDecaySheet.getRange(timeDecayCardRanges[index].split(":")[0]).values = [[timeDecayCardLabels[index]]];
  timeDecaySheet.getRange(timeDecayValueRanges[index].split(":")[0]).values = [[timeDecayCardValues[index]]];
  timeDecaySheet.getRange(timeDecayCardRanges[index]).format = {
    fill: colors.teal,
    font: { bold: true, color: colors.white },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
  timeDecaySheet.getRange(timeDecayValueRanges[index]).format = {
    fill: colors.white,
    font: { bold: true, color: colors.navy, size: 18 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
}
timeDecaySheet.getRange("A8:B9").format.numberFormat = "0.00";
timeDecaySheet.getRange("G8:H9").format.numberFormat = "0.00";

timeDecaySheet.getRange("A11:H11").merge();
timeDecaySheet.getRange("A11").values = [["What the fitted pattern says"]];
timeDecaySheet.getRange("A11:H11").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A12:H15").merge(true);
timeDecaySheet.getRange("A12:A15").values = [
  [`• The immediate post-collection level was estimated at ${timeDecayImmediate.effect_ratio.toFixed(2)} times the collection-day pre level (95% CI ${timeDecayImmediate.ci_low.toFixed(2)}–${timeDecayImmediate.ci_high.toFixed(2)}).`],
  [`• The model-implied central curve returns to the pre-collection level after about ${timeDecayResults.interpretation.central_return_to_baseline_hours.toFixed(1)} hours; uncertainty around the curve broadens with time.`],
  [`• The smooth model used only ${timeDecayResults.smooth_term.edf.toFixed(2)} effective degrees of freedom and was only 0.23 AIC units better than the linear model, so the estimated decline is nearly log-linear.`],
  [`• Restricting the analysis to the first six hours weakened the slope to RR ${timeDecayFirstSix.effect_ratio.toFixed(2)} (95% CI ${timeDecayFirstSix.ci_low.toFixed(2)}–${timeDecayFirstSix.ci_high.toFixed(2)}), showing that late near-zero activity contributes important information.`],
];
timeDecaySheet.getRange("A12:H15").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
timeDecaySheet.getRange("A12:H15").format.rowHeight = 31;

timeDecaySheet.getRange("A17:H17").merge();
timeDecaySheet.getRange("A17").values = [["Observed event-centred profile and adjusted window contrasts"]];
timeDecaySheet.getRange("A17:H17").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A18:H18").values = [[
  "Window", "Days", "Camera hours", "Foraging hours", "Raw sec / camera h", "Adjusted ratio", "Adjusted 95% CI", "p-value",
]];
const timeDecayWindowLookup = new Map(timeDecayResults.window_estimates.map((row) => [row.window, row]));
const timeDecayProfileRows = timeDecayResults.profile.map((row) => {
  const adjusted = timeDecayWindowLookup.get(row.window);
  const isReference = row.window === "Collection pre";
  return [
    row.window,
    row.observation_days,
    row.camera_hours,
    row.foraging_hours,
    row.foraging_seconds_per_camera_hour,
    adjusted ? adjusted.effect_ratio : (isReference ? 1 : null),
    adjusted ? `${adjusted.ci_low.toFixed(2)}–${adjusted.ci_high.toFixed(2)}` : (isReference ? "reference" : null),
    adjusted ? adjusted.p_value : null,
  ];
});
timeDecaySheet.getRange("A19:H24").values = timeDecayProfileRows;
styleFlatTable(timeDecaySheet, timeDecaySheet.getRange("A18:H24"), timeDecaySheet.getRange("A18:H18"));
addTable(timeDecaySheet, "A18:H24", "TimeDecayWindowTable", "TableStyleMedium4");
timeDecaySheet.getRange("B19:B24").format.numberFormat = "0";
timeDecaySheet.getRange("C19:F24").format.numberFormat = "0.00";
timeDecaySheet.getRange("H19:H24").format.numberFormat = "0.000";
timeDecaySheet.getRange("A19:H24").format.rowHeight = 30;

timeDecaySheet.getRange("A26:H26").merge();
timeDecaySheet.getRange("A26").values = [["Model-implied collection-day contrast across elapsed time"]];
timeDecaySheet.getRange("A26:H26").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A27:H27").values = [["Hours after collection", "Adjusted ratio", "CI lower", "CI upper", "Interpretation", null, null, null]];
const timeDecayContrastRows = timeDecayResults.linear_contrasts.map((row) => [
  row.hours_after_collection,
  row.effect_ratio,
  row.ci_low,
  row.ci_high,
  row.ci_low > 1 ? "Elevated estimate; interval above 1" : (row.ci_high < 1 ? "Reduced estimate; interval below 1" : "Interval includes 1"),
  null,
  null,
  null,
]);
timeDecaySheet.getRange("A28:H32").values = timeDecayContrastRows;
for (let row = 28; row <= 32; row += 1) timeDecaySheet.getRange(`E${row}:H${row}`).merge();
styleFlatTable(timeDecaySheet, timeDecaySheet.getRange("A27:H32"), timeDecaySheet.getRange("A27:H27"));
timeDecaySheet.getRange("A28:A32").format.numberFormat = "0.0";
timeDecaySheet.getRange("B28:D32").format.numberFormat = "0.00";
timeDecaySheet.getRange("A28:H32").format.rowHeight = 29;

timeDecaySheet.getRange("A34:H34").merge();
timeDecaySheet.getRange("A34").values = [["Primary and sensitivity estimates: hourly decay"]];
timeDecaySheet.getRange("A34:H34").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A35:H35").values = [["Analysis", "Bin", "Hourly ratio", "CI lower", "CI upper", "p-value", "Rows", "Purpose"]];
const timeDecayAnalysisOrder = [
  "Linear post-collection decay",
  "Linear decay excluding N3",
  "Linear decay 15-minute sensitivity",
  "Linear decay 60-minute sensitivity",
  "Linear decay limited to first 6 hours",
  "Linear decay plus observer",
  "Linear decay with 3-df clock spline",
  "Linear decay with 5-df clock spline",
  "Linear decay with 6-df clock spline",
];
const timeDecayEstimateRows = timeDecayAnalysisOrder.map((analysis) => {
  const row = timeDecayResults.model_estimates.find((candidate) => candidate.analysis === analysis);
  return [row.analysis, row.bin_minutes, row.effect_ratio, row.ci_low, row.ci_high, row.p_value, row.interval_rows, row.notes];
});
timeDecaySheet.getRange("A36:H44").values = timeDecayEstimateRows;
styleFlatTable(timeDecaySheet, timeDecaySheet.getRange("A35:H44"), timeDecaySheet.getRange("A35:H35"));
addTable(timeDecaySheet, "A35:H44", "TimeDecaySensitivityTable", "TableStyleMedium4");
timeDecaySheet.getRange("B36:B44").format.numberFormat = "0";
timeDecaySheet.getRange("C36:E44").format.numberFormat = "0.00";
timeDecaySheet.getRange("F36:F44").format.numberFormat = "0.000";
timeDecaySheet.getRange("G36:G44").format.numberFormat = "0";
timeDecaySheet.getRange("A36:H44").format.wrapText = true;
timeDecaySheet.getRange("A36:H44").format.rowHeight = 32;

timeDecaySheet.getRange("A46:H46").merge();
timeDecaySheet.getRange("A46").values = [["Adequacy, stability, and identification limits"]];
timeDecaySheet.getRange("A46:H46").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
for (const range of ["A47:C47", "D47:E47", "F47:H47"]) timeDecaySheet.getRange(range).merge();
timeDecaySheet.getRange("A47").values = [["Check"]];
timeDecaySheet.getRange("D47").values = [["Observed result"]];
timeDecaySheet.getRange("F47").values = [["Interpretation"]];
timeDecaySheet.getRange("A47:H47").format = headerFormat;
const timeDecayAdequacyRows = [
  ["Day-stratified bootstrap", `${(100 * timeDecayBootstrap.direction_fraction).toFixed(1)}% declining`, `400/400 fits; hourly-RR percentile interval ${timeDecayBootstrap.ci_low.toFixed(2)}–${timeDecayBootstrap.ci_high.toFixed(2)}.`],
  ["Leave-one-day-out", `${timeDecayLoo.declining_fits.toFixed(0)}/25 declining`, `Hourly-RR range ${timeDecayLoo.minimum.toFixed(2)}–${timeDecayLoo.maximum.toFixed(2)}; no single day creates the direction.`],
  ["Smooth-shape check", `edf ${timeDecayResults.smooth_term.edf.toFixed(2)}; p = ${timeDecayResults.smooth_term["p-value"].toFixed(3)}`, "The flexible smooth estimates an almost linear decline."],
  ["Zero fit and serial dependence", `${timeDecayZeroObserved.toFixed(0)} vs ${timeDecayZeroExpected.toFixed(1)} zeros; lag-1 ${timeDecayResidual.toFixed(3)}`, "The Tweedie zero mass fits closely and little residual temporal dependence remains."],
  ["Clock-time entanglement", `r = ${timeDecayClockCorrelation.toFixed(3)}; VIF ≈ ${timeDecayVif.toFixed(1)}`, "Elapsed time is strongly related to clock time; the global clock spline reduces but cannot erase this identification limit."],
  ["Variation in collection timing", `${timeDecayCollectionRange.toFixed(2)}-hour range`, "Variation among the 12 collection times provides the separation that makes the adjusted decay estimate possible."],
];
for (let index = 0; index < timeDecayAdequacyRows.length; index += 1) {
  const row = 48 + index;
  for (const range of [`A${row}:C${row}`, `D${row}:E${row}`, `F${row}:H${row}`]) timeDecaySheet.getRange(range).merge();
  timeDecaySheet.getRange(`A${row}`).values = [[timeDecayAdequacyRows[index][0]]];
  timeDecaySheet.getRange(`D${row}`).values = [[timeDecayAdequacyRows[index][1]]];
  timeDecaySheet.getRange(`F${row}`).values = [[timeDecayAdequacyRows[index][2]]];
  timeDecaySheet.getRange(`A${row}:H${row}`).format = {
    fill: index % 2 === 0 ? colors.white : colors.paleGray,
    font: { color: "#273746" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
  timeDecaySheet.getRange(`A${row}:C${row}`).format.font = { bold: true, color: colors.gray };
  timeDecaySheet.getRange(`D${row}:E${row}`).format.font = { bold: true, color: colors.navy };
  timeDecaySheet.getRange(`A${row}:H${row}`).format.rowHeight = 38;
}

timeDecaySheet.getRange("A55:H55").merge();
timeDecaySheet.getRange("A55").values = [["Provisional manuscript Results text"]];
timeDecaySheet.getRange("A55:H55").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A56:H61").merge();
timeDecaySheet.getRange("A56").values = [[
  `To examine whether the post-collection association was transient, 30-minute records were split exactly at collection end and elapsed time was added to the Tweedie mixed generalized additive model. After accounting for the overall clock-time pattern, collection-day baseline, camera exposure, and repeated observation days, expected foraging activity declined by ${(100 * (1 - timeDecayPrimary.effect_ratio)).toFixed(0)}% for each additional hour after collection (hourly rate ratio ${timeDecayPrimary.effect_ratio.toFixed(2)}, 95% CI ${timeDecayPrimary.ci_low.toFixed(2)}–${timeDecayPrimary.ci_high.toFixed(2)}; p = ${timeDecayPrimary.p_value.toFixed(3)}). The model estimated an immediate post-collection level ${timeDecayImmediate.effect_ratio.toFixed(2)} times the collection-day pre level (95% CI ${timeDecayImmediate.ci_low.toFixed(2)}–${timeDecayImmediate.ci_high.toFixed(2)}), with the central contrast approaching 1 after approximately ${timeDecayResults.interpretation.central_return_to_baseline_hours.toFixed(1)} hours. The hourly decline remained similar after excluding N3, changing interval width, adding observer, altering clock-time spline flexibility, and omitting each observation day in turn. A day-stratified bootstrap produced a 95% interval of ${timeDecayBootstrap.ci_low.toFixed(2)}–${timeDecayBootstrap.ci_high.toFixed(2)}. However, elapsed time was strongly correlated with clock time (r = ${timeDecayClockCorrelation.toFixed(2)}), and limiting the analysis to the first six hours weakened the estimate. The pattern is therefore consistent with a temporary post-collection resource pulse but does not directly demonstrate food depletion.`,
]];
timeDecaySheet.getRange("A56:H61").format = {
  fill: colors.paleBlue,
  font: { color: colors.navy, size: 11 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};

timeDecaySheet.getRange("A63:H63").merge();
timeDecaySheet.getRange("A63").values = [["Interpretation guardrails"]];
timeDecaySheet.getRange("A63:H63").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A64:H68").merge(true);
timeDecaySheet.getRange("A64:A68").values = [
  ["• Describe the result as a declining post-collection association, not direct measurement of diminishing food abundance."],
  ["• Clock time and elapsed time are strongly correlated; the fitted clock spline mitigates but cannot eliminate that limitation."],
  ["• The first-six-hour sensitivity remains negative but includes no decline, so very late observations contribute materially."],
  ["• The approximately 4.3-hour return to baseline is model-implied, not a measured depletion time."],
  ["• Results apply to this site and observation period; they do not establish a general species-level schedule-learning mechanism."],
];
timeDecaySheet.getRange("A64:H68").format = { fill: colors.paleGold, font: { color: "#5B4700" }, wrapText: true };
timeDecaySheet.getRange("A64:H68").format.rowHeight = 29;

timeDecaySheet.getRange("A70:H70").merge();
timeDecaySheet.getRange("A70").values = [["Model definition"]];
timeDecaySheet.getRange("A70:H70").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
timeDecaySheet.getRange("A71:H73").merge(true);
timeDecaySheet.getRange("A71:A73").values = [
  ["Primary decay estimand: multiplicative change in expected foraging seconds per camera time for each additional post-collection hour."],
  ["Predictors: 4-df clock-time spline, collection-day baseline, post-collection level, elapsed post-collection hours, and random observation-day effect."],
  ["Thirty-minute bins were split exactly at collection end; pre/post exposure and foraging duration remain in the correct phase."],
];
timeDecaySheet.getRange("A71:H73").format = { fill: colors.paleGray, font: { color: "#273746" }, wrapText: true };
timeDecaySheet.getRange("A71:H73").format.rowHeight = 27;
for (const [column, width] of Object.entries({ A: 39, B: 13, C: 15, D: 15, E: 18, F: 14, G: 18, H: 30 })) {
  setColumnWidth(timeDecaySheet, column, 73, width);
}
timeDecaySheet.freezePanes.freezeRows(1);

// README and visible formula-driven reconciliation summary.
readme.showGridLines = false;
readme.getRange("A1:H1").merge();
readme.getRange("A1").values = [["Great-tailed Grackle study: 30-minute analysis dataset"]];
readme.getRange("A1:H1").format = {
  fill: colors.navy,
  font: { bold: true, color: colors.white, size: 17 },
  verticalAlignment: "center",
};
readme.getRange("A1:H1").format.rowHeight = 30;
readme.getRange("A3:H4").merge();
readme.getRange("A3").values = [[
  "Purpose: transform the untouched BORIS event stream into clock-aligned 30-minute records with explicit exposure denominators, collection timing, and a transparent state-quality audit.",
]];
readme.getRange("A3:H4").format = {
  fill: colors.paleBlue,
  font: { color: colors.navy, size: 11 },
  wrapText: true,
  verticalAlignment: "center",
  borders: { preset: "outside", style: "thin", color: colors.border },
};
readme.getRange("A6:H6").merge();
readme.getRange("A6").values = [["Reconciliation summary"]];
readme.getRange("A6:H6").format = {
  fill: colors.teal,
  font: { bold: true, color: colors.white, size: 12 },
};
readme.getRange("A7:H9").values = [
  ["Observation days", null, "Collection days", null, "Interval rows", null, "Overall QC", null],
  [null, null, null, null, null, null, null, null],
  ["Camera hours", null, "Focal-visible hours", null, "Foraging hours", null, "Added visible hours", null],
];
readme.getRange("B7").formulas = [[`=COUNTA('Day_Summary'!A2:A${dayLastDataRow})`]];
readme.getRange("D7").formulas = [[`=SUM('Day_Summary'!E2:E${dayLastDataRow})`]];
readme.getRange("F7").formulas = [[`=COUNTA('Interval_Data'!A2:A${intervalLastRow})`]];
readme.getRange("H7").formulas = [[`=IF(AND('Day_Summary'!T${dayTotalRow}=\"PASS\",'State_QC'!O${qcTotalRow}=\"PASS\"),\"PASS\",\"CHECK\")`]];
readme.getRange("B9").formulas = [[`=SUM('Interval_Data'!K2:K${intervalLastRow})/'Parameters'!$B$6`]];
readme.getRange("D9").formulas = [[`=SUM('Interval_Data'!S2:S${intervalLastRow})/'Parameters'!$B$6`]];
readme.getRange("F9").formulas = [[`=SUM('Interval_Data'!R2:R${intervalLastRow})/'Parameters'!$B$6`]];
readme.getRange("H9").formulas = [[`=SUM('Interval_Data'!T2:T${intervalLastRow})/'Parameters'!$B$6`]];
for (const labelRange of ["A7:A7", "C7:C7", "E7:E7", "G7:G7", "A9:A9", "C9:C9", "E9:E9", "G9:G9"]) {
  readme.getRange(labelRange).format = { fill: colors.paleGray, font: { bold: true, color: colors.gray } };
}
for (const valueRange of ["B7:B7", "D7:D7", "F7:F7", "H7:H7", "B9:B9", "D9:D9", "F9:F9", "H9:H9"]) {
  readme.getRange(valueRange).format = {
    fill: colors.white,
    font: { bold: true, color: colors.navy, size: 13 },
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
}
readme.getRange("B9:H9").format.numberFormat = "0.000";
readme.getRange("A11:H11").merge();
readme.getRange("A11").values = [["Transformation rules"]];
readme.getRange("A11:H11").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
readme.getRange("A12:H16").merge(true);
readme.getRange("A12:A16").values = [
  ["1. The original BORIS and spreadsheet sources are never edited."],
  ["2. Media duration comes from BORIS media_info.length because every complete file was reviewed."],
  ["3. V-series timestamps are normalized by subtracting the BORIS time offset; bins are aligned to the local clock."],
  ["4. Focal-visible exposure is the strict union of At the observation site OR Searching for food. No unobserved gaps are filled."],
  ["5. Garbage collection is a timed proxy for a putative accessible-food pulse; food abundance itself was not measured."],
];
readme.getRange("A12:H16").format = { wrapText: true, fill: colors.paleGray, font: { color: "#273746" } };
readme.getRange("A18:H18").merge();
readme.getRange("A18").values = [["Quality-control findings"]];
readme.getRange("A18:H18").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
readme.getRange("A19:H22").values = [
  ["Foraging intervals outside raw at-site state", null, null, null, "Same-behavior overlaps", null, null, null],
  [null, null, null, null, null, null, null, null],
  ["Negative, zero, or out-of-media state intervals", null, null, null, "Repair status", null, null, null],
  [null, null, null, null, null, null, null, null],
];
for (const range of ["A19:D19", "E19:H19", "A21:D21", "E21:H21"]) {
  readme.getRange(range).merge();
  readme.getRange(range).format = { fill: colors.paleGray, font: { bold: true, color: colors.gray }, wrapText: true };
}
for (const range of ["A20:D20", "E20:H20", "A22:D22", "E22:H22"]) {
  readme.getRange(range).merge();
  readme.getRange(range).format = {
    fill: colors.white,
    font: { bold: true, color: colors.navy },
    borders: { preset: "outside", style: "thin", color: colors.border },
    wrapText: true,
  };
}
readme.getRange("A20").formulas = [[`='State_QC'!H${qcTotalRow}`]];
readme.getRange("E20").formulas = [[`=SUM('State_QC'!I${qcTotalRow}:J${qcTotalRow})`]];
readme.getRange("A22").formulas = [[`=SUM('State_QC'!K${qcTotalRow}:M${qcTotalRow})`]];
readme.getRange("E22").values = [["Union repair retained; raw states preserved"]];
readme.getRange("A24:H24").merge();
readme.getRange("A24").values = [["Interpretation limits"]];
readme.getRange("A24:H24").format = { fill: colors.teal, font: { bold: true, color: colors.white, size: 12 } };
readme.getRange("A25:H28").merge(true);
readme.getRange("A25:A28").values = [
  ["• Rows are repeated temporal intervals nested within 25 observation days; they are not independent ecological replicates."],
  ["• Focal-visible time is explicit coded exposure, not total abundance or all-bird occupancy."],
  ["• Subject-count updates are transition records and must not be treated directly as abundance observations."],
  ["• Collection timing supports an event-centred association analysis, not a causal test of measured food availability."],
];
readme.getRange("A25:H28").format = { wrapText: true, fill: colors.paleGold, font: { color: "#5B4700" } };
for (const column of ["A", "B", "C", "D", "E", "F", "G", "H"]) {
  setColumnWidth(readme, column, 28, 18);
}
readme.getRange("A12:H16").format.rowHeight = 24;
readme.getRange("A25:H28").format.rowHeight = 24;
readme.freezePanes.freezeRows(1);

// Compact verification before export.
console.log((await workbook.inspect({
  kind: "table",
  range: `Day_Summary!A1:T${dayTotalRow}`,
  include: "values,formulas",
  tableMaxRows: 30,
  tableMaxCols: 20,
  maxChars: 12000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "table",
  range: `State_QC!A1:O${qcTotalRow}`,
  include: "values,formulas",
  tableMaxRows: 30,
  tableMaxCols: 15,
  maxChars: 10000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "table",
  range: "Model_Decision!A1:H51",
  include: "values,formulas",
  tableMaxRows: 60,
  tableMaxCols: 8,
  maxChars: 18000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "table",
  range: "Model_Results!A1:H54",
  include: "values,formulas",
  tableMaxRows: 60,
  tableMaxCols: 8,
  maxChars: 20000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "table",
  range: "Mechanism_Results!A1:H58",
  include: "values,formulas",
  tableMaxRows: 65,
  tableMaxCols: 8,
  maxChars: 22000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "table",
  range: "Displacement_Results!A1:H67",
  include: "values,formulas",
  tableMaxRows: 75,
  tableMaxCols: 8,
  maxChars: 24000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "table",
  range: "Time_Decay!A1:H73",
  include: "values,formulas",
  tableMaxRows: 80,
  tableMaxCols: 8,
  maxChars: 26000,
})).ndjson);
console.log((await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
  maxChars: 4000,
})).ndjson);

const previews = [
  ["README", "A1:H28"],
  ["Parameters", "A1:D13"],
  ["Interval_Data", "A1:W18"],
  ["Day_Summary", `A1:T${dayTotalRow}`],
  ["State_QC", `A1:O${qcTotalRow}`],
  ["Data_Dictionary", `A1:F${dictionaryRows.length + 1}`],
  ["Model_Decision", "A1:H51"],
  ["Model_Results", "A1:H54"],
  ["Mechanism_Results", "A1:H58"],
  ["Displacement_Results", "A1:H67"],
  ["Time_Decay", "A1:H73"],
];
for (const [sheetName, range] of previews) {
  const blob = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  await fs.writeFile(path.join(previewDir, `${sheetName}.png`), bytes);
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(JSON.stringify({ outputPath, intervalLastRow, dayTotalRow, qcTotalRow }, null, 2));
