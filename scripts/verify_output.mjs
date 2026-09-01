/**
 * Script: verify_output.mjs
 * Pipeline stage: 6. Figures and reporting
 * Analytical purpose: Open the generated workbook, inspect key ranges and formula errors, and
 * render representative sheets for visual quality assurance.
 * Inputs: outputs/.../Grackles_30min_analysis_dataset.xlsx
 * Outputs: .codex_work/issue4/previews/*.png and console inspection output
 * Run-order position: 29
 * Key scientific assumption: Verification is read-only with respect to the workbook; generated PNG
 * previews are QA artifacts.
 * Provenance note: This annotated copy preserves the executed analytical statements. Only
 * explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
 */

import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const rootDir = process.cwd();
const workbookPath = path.join(rootDir, "outputs", "019fb5b5-949c-74f1-ac2a-18b1d5a808c5", "Grackles_30min_analysis_dataset.xlsx");
const previewPath = path.join(rootDir, ".codex_work", "issue4", "previews", "Interval_Data_events.png");
const modelPreviewPath = path.join(rootDir, ".codex_work", "issue4", "previews", "Model_Decision_serialized.png");
const resultsPreviewPath = path.join(rootDir, ".codex_work", "issue4", "previews", "Model_Results_serialized.png");
const mechanismPreviewPath = path.join(rootDir, ".codex_work", "issue4", "previews", "Mechanism_Results_serialized.png");
const displacementPreviewPath = path.join(rootDir, ".codex_work", "issue4", "previews", "Displacement_Results_serialized.png");
const timeDecayPreviewPath = path.join(rootDir, ".codex_work", "issue4", "previews", "Time_Decay_serialized.png");

// --- Load the generated workbook for structural and visual QA ---
const input = await FileBlob.load(workbookPath);
const workbook = await SpreadsheetFile.importXlsx(input);

console.log((await workbook.inspect({
  kind: "table",
  range: "README!A1:H28",
  include: "values,formulas",
  tableMaxRows: 30,
  tableMaxCols: 8,
  maxChars: 8000,
})).ndjson);

console.log((await workbook.inspect({
  kind: "table",
  range: "Interval_Data!X1:AI18",
  include: "values,formulas",
  tableMaxRows: 18,
  tableMaxCols: 12,
  maxChars: 7000,
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
  summary: "serialized workbook formula error scan",
  maxChars: 4000,
})).ndjson);

const preview = await workbook.render({
  sheetName: "Interval_Data",
  range: "X1:AI18",
  scale: 1,
  format: "png",
});
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));

const modelPreview = await workbook.render({
  sheetName: "Model_Decision",
  range: "A1:H51",
  scale: 1,
  format: "png",
});
await fs.writeFile(modelPreviewPath, new Uint8Array(await modelPreview.arrayBuffer()));

const resultsPreview = await workbook.render({
  sheetName: "Model_Results",
  range: "A1:H54",
  scale: 1,
  format: "png",
});
await fs.writeFile(resultsPreviewPath, new Uint8Array(await resultsPreview.arrayBuffer()));

const mechanismPreview = await workbook.render({
  sheetName: "Mechanism_Results",
  range: "A1:H58",
  scale: 1,
  format: "png",
});
await fs.writeFile(mechanismPreviewPath, new Uint8Array(await mechanismPreview.arrayBuffer()));

const displacementPreview = await workbook.render({
  sheetName: "Displacement_Results",
  range: "A1:H67",
  scale: 1,
  format: "png",
});
await fs.writeFile(displacementPreviewPath, new Uint8Array(await displacementPreview.arrayBuffer()));

const timeDecayPreview = await workbook.render({
  sheetName: "Time_Decay",
  range: "A1:H73",
  scale: 1,
  format: "png",
});
await fs.writeFile(timeDecayPreviewPath, new Uint8Array(await timeDecayPreview.arrayBuffer()));
