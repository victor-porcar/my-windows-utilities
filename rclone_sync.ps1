param(
    [Parameter(Mandatory=$true)]
    [string]$syncListFile,

    [Parameter(Mandatory=$true)]
    [string]$exclusionFile,

    [Parameter(Mandatory=$false)]
    [string]$rcloneArgsFile,

    [Parameter(Mandatory=$false)]
    [string]$title,

    # Shows what would be copied and deleted without touching anything
    [switch]$DryRun
)

# =========================================================
# RCLONE HOME
# rclone.exe and rclone-empty.conf live in software-rclone,
# located through GITHUB_VICTOR_PORCAR so this script runs from anywhere.
# =========================================================
$repoRoot = $env:GITHUB_VICTOR_PORCAR

if (-not $repoRoot) {
    Write-Host "X GITHUB_VICTOR_PORCAR ENVIRONMENT VARIABLE IS NOT DEFINED" -ForegroundColor Red
    exit 1
}

$rcloneHome = Join-Path $repoRoot "my-windows-utilities\software-rclone"

# =========================================================
# TITLE
# =========================================================
if ($title) {

    $border = "=" * ($title.Length + 8)

    Write-Host ""
    Write-Host $border -ForegroundColor Cyan
    Write-Host "=== $title ===" -ForegroundColor Cyan
    Write-Host $border -ForegroundColor Cyan
    Write-Host ""
}

# =========================================================
# DEFAULT RCLONE ARGS FILE
# =========================================================
if (-not $rcloneArgsFile) {
    $rcloneArgsFile = Join-Path $rcloneHome "rclone.args"
}

# =========================================================
# FILE VALIDATION
# =========================================================
foreach ($file in @($syncListFile, $exclusionFile, $rcloneArgsFile)) {
    if (!(Test-Path -LiteralPath $file)) {
        Write-Host "❌ FILE NOT FOUND: $file" -ForegroundColor Red
        exit 1
    }
}

# =========================================================
# LOAD RCLONE ARGS
# =========================================================
$rcloneParams = Get-Content $rcloneArgsFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }

$emptyConfig = Join-Path $rcloneHome "rclone-empty.conf"

if (-not (Test-Path -LiteralPath $emptyConfig)) {
    New-Item -ItemType File -Path $emptyConfig -Force | Out-Null
}

$rcloneParams += "--config"
$rcloneParams += $emptyConfig

$rcloneParams += "--exclude-from"
$rcloneParams += $exclusionFile

if ($DryRun) {
    $rcloneParams += "--dry-run"

    Write-Host "***************************************************" -ForegroundColor Magenta
    Write-Host "*** DRY RUN - NOTHING WILL BE COPIED OR DELETED ***" -ForegroundColor Magenta
    Write-Host "***************************************************" -ForegroundColor Magenta
    Write-Host ""
}

# =========================================================
# VOLUME MAP
# =========================================================
$volumeMap = @{}

Get-Volume |
Where-Object { $_.FileSystemLabel -and $_.DriveLetter } |
ForEach-Object {
    $volumeMap[$_.FileSystemLabel.ToUpper()] = "$($_.DriveLetter):\"
}

$volumeUsage = @{}

function Resolve-VolumePath {
    param(
        [string]$path,
        [hashtable]$volumeMap,
        [ref]$volumeUsage
    )

    $path = $path.Trim()

    if ($path -match "^\[(.+?)\]:(.*)$") {

        $volumeName = $matches[1].ToUpper()
        $restPath   = $matches[2]

        if (-not $volumeMap.ContainsKey($volumeName)) {
            throw "VOLUME NOT FOUND: $volumeName"
        }

        $resolved = $volumeMap[$volumeName] + $restPath.TrimStart("\")

        $volumeUsage.Value[$volumeName] = $volumeMap[$volumeName]

        return $resolved
    }

    return $path
}

# =========================================================
# LOAD JOBS + VALIDATION
# =========================================================
$rawJobs = Get-Content $syncListFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }

$jobs = @()

foreach ($line in $rawJobs) {

    $parts = $line.Split(",", 2)

    if ($parts.Count -ne 2) {
        Write-Host "⚠️ INVALID LINE: $line" -ForegroundColor Yellow
        continue
    }

    try {
        $source = Resolve-VolumePath $parts[0] $volumeMap ([ref]$volumeUsage)
        $dest   = Resolve-VolumePath $parts[1] $volumeMap ([ref]$volumeUsage)

        if (-not (Test-Path -LiteralPath $source)) {
            Write-Host "❌ SKIP SOURCE NOT FOUND: $source" -ForegroundColor Red
            continue
        }

        if (-not (Test-Path -LiteralPath $dest)) {
            Write-Host "❌ SKIP DESTINATION NOT FOUND: $dest" -ForegroundColor Red
            continue
        }

        $jobs += [PSCustomObject]@{
            Source      = $source
            Destination = $dest
        }
    }
    catch {
        Write-Host "❌ ERROR: $_" -ForegroundColor Red
    }
}

# =========================================================
# VALIDATION
# =========================================================
Write-Host "`n🔍 VALIDATION REPORT`n" -ForegroundColor Yellow

if ($jobs.Count -eq 0) {
    Write-Host "⛔ NO VALID JOBS" -ForegroundColor Red
    exit 1
}

Write-Host "✅ JOBS: $($jobs.Count)`n" -ForegroundColor Green

foreach ($job in $jobs) {
    Write-Host "➡️ $($job.Source) → $($job.Destination)"
}

# =========================================================
# RCLONE
# Checked before asking, so a missing rclone.exe is not discovered after confirming
# =========================================================
$rclonePath = Join-Path $rcloneHome "rclone.exe"

if (!(Test-Path -LiteralPath $rclonePath)) {
    Write-Host "❌ RCLONE NOT FOUND: $rclonePath" -ForegroundColor Red
    exit 1
}

# A dry run changes nothing, so there is nothing to confirm
if (-not $DryRun) {

    $answer = Read-Host "`nProceed? (y/n)"

    if ($answer -ne "y") {
        Write-Host "⛔ CANCELLED"
        exit 0
    }
}

if ($DryRun) {
    Write-Host "`n🔎 STARTING DRY RUN`n" -ForegroundColor Magenta
}
else {
    Write-Host "`n🚀 STARTING SYNC`n" -ForegroundColor Green
}

$okCount     = 0
$failedCount = 0

foreach ($job in $jobs) {

    Write-Host "➡️ $($job.Source) → $($job.Destination)" -ForegroundColor Green

    $rcloneArgs = @(
        "sync"
        $job.Source
        $job.Destination
    ) + $rcloneParams

    & $rclonePath @rcloneArgs

    # =====================================================
    # CONTROL FILE ONLY WHEN THE JOB SUCCEEDS
    # =====================================================
    if ($LASTEXITCODE -eq 0) {

        # A dry run must not touch the destination either
        if (-not $DryRun) {

            try {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $controlFile = Join-Path $job.Destination "control_sync.txt"

                Set-Content -LiteralPath $controlFile -Value $timestamp -Force

                Write-Host "📝 control_sync.txt updated" -ForegroundColor Cyan
            }
            catch {
                Write-Host "⚠️ COULD NOT WRITE control_sync.txt IN $($job.Destination)" -ForegroundColor Yellow
            }
        }

        $okCount++
        Write-Host "✅ OK`n" -ForegroundColor Green
    }
    else {
        $failedCount++
        Write-Host "❌ FAILED`n" -ForegroundColor Red
    }
}

# =========================================================
# SUMMARY
# =========================================================
$mode = if ($DryRun) { "DRY RUN" } else { "DONE" }

if ($failedCount -gt 0) {
    Write-Host "🎉 $mode - $okCount OK, $failedCount FAILED" -ForegroundColor Red
    exit 1
}

if ($DryRun) {
    Write-Host "🔎 $mode - $okCount OK - NOTHING WAS CHANGED" -ForegroundColor Magenta
}
else {
    Write-Host "🎉 $mode - $okCount OK" -ForegroundColor Green
}