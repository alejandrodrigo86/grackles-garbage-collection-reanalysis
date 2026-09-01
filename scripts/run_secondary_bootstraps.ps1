# ================================================================================================
# Script: run_secondary_bootstraps.ps1
# Pipeline stage: 6. Approved-revision audits
# Analytical purpose: Run the displacement and elapsed-time day-cluster bootstraps in fixed-seed,
# resumable batches while retaining successful model-fit warnings in the execution log.
# Inputs: bootstrap_displacement.R or bootstrap_time_decay.R plus the corresponding model-ready
# dataset
# Outputs: .codex_work/issue4/model_output/displacement_bootstrap_*.csv or
# time_decay_bootstrap_*.csv
# Run-order position: 26
# Key scientific assumption: Completed batches are preserved on restart, and the R process exit
# code—not nonfatal warnings—determines batch failure.
# Provenance note: This annotated copy preserves the executed analytical statements. Only
# explanatory comments were added; see MANIFEST.csv for original and packaged hashes.
# ================================================================================================

param(
    [ValidateSet('displacement', 'time_decay')]
    [string]$Analysis,
    [int]$TotalReplicates = 2000,
    [int]$BatchSize = 100,
    [int]$ConcurrentBatches = 3
)

$ErrorActionPreference = 'Stop'
$rscript = if ($env:R_SCRIPT) { $env:R_SCRIPT } else { 'Rscript' }
$workDir = Join-Path (Get-Location) '.codex_work\issue4'
$scriptName = if ($Analysis -eq 'displacement') { 'bootstrap_displacement.R' } else { 'bootstrap_time_decay.R' }
$scriptPath = Join-Path (Join-Path (Get-Location) 'scripts') $scriptName
$starts = 1..([Math]::Ceiling($TotalReplicates / $BatchSize)) | ForEach-Object { 1 + ($_ - 1) * $BatchSize }
$outputStem = if ($Analysis -eq 'displacement') { 'displacement_bootstrap' } else { 'time_decay_bootstrap' }

# Preserve completed, fixed-seed batches when a long run is resumed.
$starts = @($starts | Where-Object {
    $start = $_
    $remaining = $TotalReplicates - $start + 1
    $expected = [Math]::Min($BatchSize, $remaining)
    $output = Join-Path $workDir "model_output\${outputStem}_${start}.csv"
    if (-not (Test-Path -LiteralPath $output)) { return $true }
    $observed = @(Import-Csv -LiteralPath $output).Count
    return $observed -lt $expected
})

if ($starts.Count -eq 0) {
    Write-Output "$Analysis bootstrap already complete: $TotalReplicates requested replicates."
    exit 0
}

for ($offset = 0; $offset -lt $starts.Count; $offset += $ConcurrentBatches) {
    $last = [Math]::Min($offset + $ConcurrentBatches - 1, $starts.Count - 1)
    $jobs = foreach ($start in $starts[$offset..$last]) {
        $remaining = $TotalReplicates - $start + 1
        $replicates = [Math]::Min($BatchSize, $remaining)
        Start-Job -ScriptBlock {
            param($RscriptPath, $AnalysisScript, $StartIndex, $ReplicateCount)
            $env:GRACKLES_BOOT_START = [string]$StartIndex
            $env:GRACKLES_BOOT_N = [string]$ReplicateCount
            # R writes model-fit warnings to stderr even when the batch succeeds.
            # Merge those messages into ordinary job output and use the process
            # exit code, rather than the warning stream, to determine failure.
            & $RscriptPath $AnalysisScript 2>&1
            if ($LASTEXITCODE -ne 0) { throw "R bootstrap batch $StartIndex failed with exit code $LASTEXITCODE" }
        } -ArgumentList $rscript, $scriptPath, $start, $replicates
    }
    $jobs | Wait-Job | Out-Null
    $jobs | Receive-Job -ErrorAction Continue
    $failed = $jobs | Where-Object { $_.State -ne 'Completed' }
    $jobs | Remove-Job
    if ($failed) { throw "$($failed.Count) bootstrap batch job(s) failed" }
}

Write-Output "$Analysis bootstrap completed: $TotalReplicates requested replicates in $($starts.Count) batches."
