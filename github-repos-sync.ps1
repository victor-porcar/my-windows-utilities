<#
.SYNOPSIS
    Clones or updates every repository of a GitHub account into a single directory.

.DESCRIPTION
    For each repository of the account: clones it if the folder is missing, or fast-forwards
    it with git pull if it is already there. Repositories with uncommitted changes are left
    untouched and reported, so nothing local is ever overwritten.

    Requires GitHub CLI (gh) installed and authenticated: run 'gh auth login' once.
    Private repositories are included when the authenticated account can see them.

.PARAMETER TargetDir
    Directory holding the repositories. Created if it does not exist. E.g.: D:\path\to\github

.PARAMETER Account
    GitHub user or organization. Defaults to the account currently authenticated in gh.

.PARAMETER IncludeArchived
    Also process archived repositories, which are skipped by default.

.PARAMETER Limit
    Maximum number of repositories to list. Default 200.

.EXAMPLE
    .\github-repos-sync.ps1 "D:\path\to\github"

.EXAMPLE
    .\github-repos-sync.ps1 "D:\path\to\github" -Account some-org -IncludeArchived
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetDir,

    [Parameter(Position = 1)]
    [string]$Account,

    [switch]$IncludeArchived,

    [int]$Limit = 200
)

$ErrorActionPreference = "Stop"

# =========================================================
# GITHUB CLI
# =========================================================
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source

if (-not $gh) {
    # Freshly installed gh is not in PATH until a new console is opened
    $fallback = Join-Path $env:ProgramFiles "GitHub CLI\gh.exe"
    if (Test-Path -LiteralPath $fallback) { $gh = $fallback }
}

if (-not $gh) {
    Write-Host "X GITHUB CLI NOT FOUND - install it with: winget install --id GitHub.cli" -ForegroundColor Red
    exit 1
}

& $gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "X GITHUB CLI IS NOT AUTHENTICATED - run: gh auth login" -ForegroundColor Red
    exit 1
}

# =========================================================
# TARGET DIRECTORY
# =========================================================
if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}
$TargetDir = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TargetDir).Path)

if (-not $Account) {
    $Account = (& $gh api user --jq .login)
}

Write-Host ""
Write-Host "==============================================================="
Write-Host " ACCOUNT   : $Account"
Write-Host " DIRECTORY : $TargetDir" -ForegroundColor Green
Write-Host "==============================================================="
Write-Host ""

# =========================================================
# REPOSITORY LIST
# =========================================================
$json = & $gh repo list $Account --limit $Limit --json "name,url,isArchived,isPrivate"

if ($LASTEXITCODE -ne 0) {
    Write-Host "X COULD NOT LIST REPOSITORIES OF $Account" -ForegroundColor Red
    exit 1
}

$repos = $json | ConvertFrom-Json

if (-not $IncludeArchived) {
    $repos = @($repos | Where-Object { -not $_.isArchived })
}

if ($repos.Count -eq 0) {
    Write-Host "NO REPOSITORIES FOUND" -ForegroundColor Yellow
    exit 0
}

Write-Host "REPOSITORIES: $($repos.Count)`n"

$cloned  = 0
$updated = 0
$skipped = 0
$failed  = 0

foreach ($repo in $repos) {

    $path    = Join-Path $TargetDir $repo.name
    $private = if ($repo.isPrivate) { " (private)" } else { "" }

    # ---------------------------------------------------------
    # NOT THERE YET: CLONE
    # ---------------------------------------------------------
    if (-not (Test-Path -LiteralPath (Join-Path $path ".git"))) {

        Write-Host "CLONE  $($repo.name)$private" -ForegroundColor Cyan
        & git clone --quiet $repo.url $path

        if ($LASTEXITCODE -eq 0) { $cloned++ }
        else {
            $failed++
            Write-Host "   X CLONE FAILED" -ForegroundColor Red
        }
        continue
    }

    # ---------------------------------------------------------
    # ALREADY THERE: PULL, BUT NEVER OVER LOCAL CHANGES
    # ---------------------------------------------------------
    $dirty = & git -C $path status --porcelain

    if ($dirty) {
        $skipped++
        Write-Host "SKIP   $($repo.name) - uncommitted local changes" -ForegroundColor Yellow
        continue
    }

    Write-Host "PULL   $($repo.name)$private" -ForegroundColor Cyan
    & git -C $path pull --ff-only --quiet

    if ($LASTEXITCODE -eq 0) { $updated++ }
    else {
        $failed++
        Write-Host "   X PULL FAILED - diverged branch or no upstream" -ForegroundColor Red
    }
}

# =========================================================
# SUMMARY
# =========================================================
Write-Host ""
Write-Host "DONE - $cloned cloned, $updated updated, $skipped skipped, $failed failed" -ForegroundColor $(if ($failed) { "Red" } else { "Green" })

if ($failed) { exit 1 }
