# Great-tailed Grackle analysis code

This package contains the complete source code used to reconstruct the observations, fit the statistical models, run robustness checks, collect the numerical results, build the analysis workbook, and generate the publication figures.

## What is preserved

The executable statements are copied from the versions used for the analysis. The packaged copies add explanatory headers and navigation comments, but do not revise model formulas, transformations, inclusion rules, seeds, or output calculations. `MANIFEST.csv` records the SHA-256 hash of each original and annotated copy.

## Scientific scope

The analysis treats the study as an observational, single-site comparison. The observation day is the ecological replication unit. Thirty-minute intervals preserve temporal resolution, while camera time or focal-visible time is used as the relevant exposure denominator. The postcollection-versus-precollection total-foraging contrast is the single retrospectively designated primary test; no prospective analysis plan existed, and all other contrasts are secondary, sensitivity, or exploratory. Collection-day and post-collection estimates are associations rather than randomized causal estimates of food abundance. Recorded focal visibility combines bird presence in view with detectability because camera obstruction was not coded. Because the birds were unbanded, displacement results remain patch-level and cannot establish individual dominance ranks or a stable hierarchy.

## Software used

- Python 3 with `openpyxl` for source reconstruction; the remaining Python utilities use the standard library.
- R 4.4.1 with `mgcv` 1.9-1. The executed R session is preserved in `environment/session_info.txt`; `splines`, `parallel`, and other recommended/base packages are also used.
- Node.js with the bundled `@oai/artifact-tool` only for workbook construction and workbook QA. These JavaScript utilities do not fit statistical models.

## Project-relative data locations

The original scripts use the project root `<PROJECT_ROOT>` and write intermediate files under `.codex_work/issue4`. The raw inputs are:

- `Observations/Grackles_AROD.v7.0.boris`
- `Observations/Obs_Time.xlsx`
- `Observations/xlsx_aggregated/*.xlsx`

If the project is moved, update the `ROOT` / `work_dir` / `rootDir` declarations near the top of the relevant scripts. Some extraction and bootstrap outputs can also be redirected through the documented `GRACKLES_*` environment variables.

## Recommended execution

Use `RUN_ORDER.md` as the exact dependency map. The original inferential sequence ends after script 22. Scripts 23-26 implement the approved revision audits, blind-review analyses, and resumable robustness runs; scripts 27-30 create and verify presentation artifacts. Bootstrap scripts may take substantially longer than the other steps and the displacement/time-decay bootstraps are intentionally chunkable.

## Package contents

- `scripts/`: 30 annotated source files, kept in a single directory so the Python import used during displacement reconstruction remains valid.
- `RUN_ORDER.md`: ordered commands, dependencies, and notes.
- `MANIFEST.csv`: script roles, source paths, and hashes.
- `environment/session_info.txt`: R environment recorded by the executed primary-model script.
- `environment/requirements-python.txt`: Python dependency note.
- `environment/requirements-r.txt`: R package note.
- `environment/requirements-node.txt`: Node reporting-runtime note.

## Reproducibility caution

Re-running the full package may regenerate intermediate tables or bootstrap draws. Keep the archived executed outputs when exact manuscript values must be retained, and compare regenerated tables against those outputs before revising the manuscript.
