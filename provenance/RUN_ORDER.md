# Exact run order

Run commands from the project root unless a note states otherwise. Replace `python` and `Rscript` with the local executable names when needed.

| Order | Script | Purpose / invocation note |
|---:|---|---|
| 01 | `extract_interval_data.py` | `python scripts/extract_interval_data.py` |
| 02 | `prepare_model_data.py` | Flatten interval JSON. Example: `python scripts/prepare_model_data.py .codex_work/issue4/interval_data.json .codex_work/issue4/model_data_30min.csv`. |
| 03 | `analyze_issue5.py` | `python scripts/analyze_issue5.py` |
| 04 | `fit_locked_models.R` | `Rscript scripts/fit_locked_models.R` |
| 05 | `bootstrap_primary.R` | `Rscript scripts/bootstrap_primary.R` |
| 06 | `leave_one_day_out.R` | `Rscript scripts/leave_one_day_out.R` |
| 07 | `collect_model_results.py` | `python scripts/collect_model_results.py` |
| 08 | `fit_decomposition_models.R` | `Rscript scripts/fit_decomposition_models.R` |
| 09 | `bootstrap_decomposition.R` | `Rscript scripts/bootstrap_decomposition.R` |
| 10 | `leave_one_day_out_decomposition.R` | `Rscript scripts/leave_one_day_out_decomposition.R` |
| 11 | `collect_decomposition_results.py` | `python scripts/collect_decomposition_results.py` |
| 12 | `prepare_displacement_data.py` | `python scripts/prepare_displacement_data.py` |
| 13 | `profile_displacement_models.R` | `Rscript scripts/profile_displacement_models.R` |
| 14 | `fit_displacement_models.R` | `Rscript scripts/fit_displacement_models.R` |
| 15 | `bootstrap_displacement.R` | Run one or more reproducible chunks; set `GRACKLES_BOOT_START`, `GRACKLES_BOOT_N`, `GRACKLES_BOOT_SEED`, and optionally `GRACKLES_BOOT_OUTPUT`. |
| 16 | `leave_one_day_out_displacement.R` | `Rscript scripts/leave_one_day_out_displacement.R` |
| 17 | `collect_displacement_results.py` | `python scripts/collect_displacement_results.py` |
| 18 | `profile_time_decay.R` | `Rscript scripts/profile_time_decay.R` |
| 19 | `fit_time_decay_models.R` | `Rscript scripts/fit_time_decay_models.R` |
| 20 | `bootstrap_time_decay.R` | Run one or more reproducible chunks; set `GRACKLES_BOOT_START`, `GRACKLES_BOOT_N`, `GRACKLES_BOOT_SEED`, and optionally `GRACKLES_BOOT_OUTPUT`. |
| 21 | `leave_one_day_out_time_decay.R` | `Rscript scripts/leave_one_day_out_time_decay.R` |
| 22 | `collect_time_decay_results.py` | `python scripts/collect_time_decay_results.py` |
| 23 | `build_revision_audits.py` | `python scripts/build_revision_audits.py` |
| 24 | `fit_revision_models.R` | `Rscript scripts/fit_revision_models.R` |
| 25 | `fit_reviewer_models.R` | `Rscript scripts/fit_reviewer_models.R` |
| 26 | `run_secondary_bootstraps.ps1` | `powershell.exe -ExecutionPolicy Bypass -File scripts/run_secondary_bootstraps.ps1` with the documented analysis and replicate parameters. |
| 27 | `build_publication_figures.R` | Run from the project root because it resolves paths from the current working directory. |
| 28 | `build_workbook.mjs` | `node scripts/build_workbook.mjs` (reporting/QA only) |
| 29 | `verify_output.mjs` | `node scripts/verify_output.mjs` (reporting/QA only) |
| 30 | `build_supplementary_workbook.mjs` | `node scripts/build_supplementary_workbook.mjs` (reporting/QA only) |

## Dependency checkpoints

1. Do not fit models until `interval_data.json` and `model_data_30min.csv` have passed the reconstruction checks.
2. Collectors run only after their corresponding fit, bootstrap, and leave-one-day-out outputs exist.
3. Displacement and time-decay analyses both use the split-at-collection dataset from `prepare_displacement_data.py`.
4. Workbook and figure generation consume already-computed results; they do not replace model fitting.
