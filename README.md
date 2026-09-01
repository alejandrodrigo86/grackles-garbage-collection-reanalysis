# Great-tailed Grackle garbage-collection reanalysis

This repository accompanies the manuscript **“Foraging and Recorded Group Size in Urban Great-Tailed Grackles (*Quiscalus mexicanus*) Around Garbage Collection.”** It contains the derived analysis datasets, commented source code, model output, audit files, and publication figures used in the reconstructed analysis.

## What the analysis found

- The primary model estimated 30% more focal foraging after garbage collection than before it, but the confidence interval included lower, unchanged, and substantially higher activity (ratio = 1.30, 95% CI [0.84, 2.02], *p* = .244). The primary hypothesis was therefore not statistically supported.
- The clearest exploratory pattern was a 25% higher recorded group size after collection (ratio = 1.25, 95% CI [1.04, 1.49], *p* = .017). This estimate weakened when intervals containing the open-ended 9+ category were excluded.
- The positive overall foraging estimate was concentrated in longer recorded focal visibility; the proportion of visible time spent foraging changed little.
- Postcollection foraging was concentrated near collection end and declined across later hours, but elapsed time was strongly correlated with clock time.

These are patch-level temporal associations from one observational site. The archive does not support individual-level learning, dominance, adaptation, or causal claims about food abundance.

## Repository structure

- `.codex_work/issue4/`: analysis-ready interval data, audit datasets, fitted-model summaries, diagnostics, bootstrap output, and sensitivity results.
- `scripts/`: commented Python, R, PowerShell, and JavaScript source files.
- `figures/`: final figures in PNG, SVG, and PDF formats, plus captions and alt text.
- `environment/`: recorded R session and software-dependency notes.
- `provenance/`: detailed pipeline documentation, the exact execution order, and a source manifest.
- `SHA256SUMS.txt`: checksums for the released files.

## Reproducing the inferential analyses

Run commands from the repository root. R 4.4.1 and `mgcv` 1.9-1 were used for the reported models.

```powershell
Rscript scripts/fit_locked_models.R
Rscript scripts/fit_decomposition_models.R
Rscript scripts/fit_displacement_models.R
Rscript scripts/fit_time_decay_models.R
Rscript scripts/fit_revision_models.R
Rscript scripts/fit_reviewer_models.R
```

The supplied `.codex_work/issue4/` datasets allow the inferential models to be refitted without the original videos or BORIS project. Bootstrap and leave-one-day-out scripts can then be run in the order documented in `provenance/RUN_ORDER.md`. Some bootstrap stages are computationally intensive.

The first three pipeline stages reconstruct the model-ready datasets from the original BORIS and observation files. Those raw source files and the videos are not distributed in this public archive, so those stages cannot be reproduced from this repository alone. Their outputs, event audits, and provenance records are included.

## Verification

On September 1, 2026, the six non-bootstrap model-fitting scripts were run from a clean copy of this archive. The regenerated primary, decomposition, displacement, elapsed-time, reviewer-contrast, and 9+ sensitivity estimate files matched the packaged files exactly by SHA-256 hash. Node, Python, and R source files also passed syntax or parse checks. The bootstrap replicates are supplied but were not rerun during this release check because they are computationally intensive.

## Data access and ethical limits

The public archive contains derived behavioral data needed to reproduce the reported statistics. The original videos are preserved by the authors but are not included because they may contain identifiable bystanders and are large media files. Requests for controlled access will be evaluated by the corresponding author subject to ethical and privacy constraints.

## Citation

Until the manuscript has a final bibliographic citation, cite this release using `CITATION.cff`. The Zenodo DOI will be added to that file and to the manuscript when version 1.0.0 is deposited.

## Licensing

The authors have approved the repository licenses. Analysis code in `scripts/` is available under the MIT License in `LICENSE-CODE`. Derived datasets, figures, documentation, and other non-code materials are available under the Creative Commons Attribution 4.0 International License in `LICENSE-DATA`. See `LICENSES.md` for the scope of each license.

## Contact

Alejandro Rodrigo, corresponding author: alejandro.rodrigo.research@gmail.com
