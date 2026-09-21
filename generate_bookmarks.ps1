<#
.SYNOPSIS
    Converts the most recent raw bookmarks export into Markdown and HTML using Bookmark2md.

.DESCRIPTION
    Takes the newest file in <BookmarkDirectory>\RawBookmarks and runs bookmark2md.cmd on it,
    leaving the generated files in <BookmarkDirectory>\generated.

    Bookmark2md is located through the GITHUB-VICTOR-PORCAR environment variable:
    %GITHUB-VICTOR-PORCAR%\Bookmark2md\bookmark2md.cmd

.PARAMETER BookmarkDirectory
    Directory holding the RawBookmarks folder; generated files are written to its 'generated'
    subfolder. E.g.: D:\path\to\Bookmarks

.PARAMETER BookmarkFolderName
    Name of the bookmarks folder to export, also used to name the generated files. E.g.: PERSONAL

.EXAMPLE
    .\generate_bookmarks.ps1 "D:\path\to\Bookmarks" "PERSONAL"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BookmarkDirectory,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$BookmarkFolderName
)

$ErrorActionPreference = "Stop"

function Write-Info($text)     { Write-Host "i  $text" -ForegroundColor Cyan }
function Write-Success($text)  { Write-Host "OK $text" -ForegroundColor Green }
function Write-Warn($text)     { Write-Host "!  $text" -ForegroundColor Yellow }
function Write-ErrorMsg($text) { Write-Host "X  $text" -ForegroundColor Red }

# The braces are required: without them PowerShell reads the hyphens as operators
$repoRoot = ${env:GITHUB-VICTOR-PORCAR}
if (-not $repoRoot) {
    Write-ErrorMsg "The GITHUB-VICTOR-PORCAR environment variable is not defined"
    exit 1
}

$Bookmark2MdCmdPath = Join-Path $repoRoot "Bookmark2md\bookmark2md.cmd"
if (-not (Test-Path $Bookmark2MdCmdPath)) {
    Write-ErrorMsg "bookmark2md.cmd not found at: $Bookmark2MdCmdPath"
    exit 1
}

$RawBookmarksDir = Join-Path $BookmarkDirectory 'RawBookmarks'
$GeneratedDir    = Join-Path $BookmarkDirectory 'generated'

if (-not (Test-Path $RawBookmarksDir)) {
    Write-ErrorMsg "RawBookmarks folder not found at: $RawBookmarksDir"
    exit 1
}
if (-not (Test-Path $GeneratedDir)) {
    New-Item -ItemType Directory -Path $GeneratedDir -Force | Out-Null
}

Write-Info "Using RawBookmarks folder: $RawBookmarksDir"
Write-Info "Output folder: $GeneratedDir"

# Remove double quotes from the folder name so the generated file names are valid
$CleanFolderName = $BookmarkFolderName -replace '"', ''

$MarkdownFileName      = "generated_MD_$CleanFolderName.md"
$HtmlPrettyFileName    = "generated_PRETTY_HTML_$CleanFolderName.html"
$RawImportableHtmlFile = "bookmarks$CleanFolderName.html"

Write-Info "Files to generate:"
Write-Host "   Markdown:        $MarkdownFileName" -ForegroundColor White
Write-Host "   HTML Pretty:     $HtmlPrettyFileName" -ForegroundColor White
Write-Host "   HTML Importable: $RawImportableHtmlFile" -ForegroundColor White

# Newest file by creation date (the export just downloaded)
$LatestFile = Get-ChildItem -Path $RawBookmarksDir -File |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1

if (-not $LatestFile) {
    Write-ErrorMsg "No file found in $RawBookmarksDir"
    exit 1
}

Write-Success "Newest file found: $($LatestFile.Name)"
Write-Info "Running script: $Bookmark2MdCmdPath"

try {
    & $Bookmark2MdCmdPath `
        "$($LatestFile.FullName)" `
        "$GeneratedDir" `
        "$MarkdownFileName" `
        "$HtmlPrettyFileName" `
        "$RawImportableHtmlFile" `
        "$BookmarkFolderName"
}
catch {
    Write-ErrorMsg "Error running the script: $_"
    exit 1
}

if ($LASTEXITCODE -ne 0) {
    Write-Warn "The script finished with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

Write-Success "Script finished successfully."
