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
    Write-ErrorMsg "La variable de entorno GITHUB-VICTOR-PORCAR no esta definida"
    exit 1
}

$Bookmark2MdCmdPath = Join-Path $repoRoot "Bookmark2md\bookmark2md.cmd"
if (-not (Test-Path $Bookmark2MdCmdPath)) {
    Write-ErrorMsg "No se encuentra bookmark2md.cmd en: $Bookmark2MdCmdPath"
    exit 1
}

$RawBookmarksDir = Join-Path $BookmarkDirectory 'RawBookmarks'
$GeneratedDir    = Join-Path $BookmarkDirectory 'generated'

if (-not (Test-Path $RawBookmarksDir)) {
    Write-ErrorMsg "No se encuentra la carpeta RawBookmarks en: $RawBookmarksDir"
    exit 1
}
if (-not (Test-Path $GeneratedDir)) {
    New-Item -ItemType Directory -Path $GeneratedDir -Force | Out-Null
}

Write-Info "Usando carpeta RawBookmarks: $RawBookmarksDir"
Write-Info "Carpeta de salida generada: $GeneratedDir"

# Quitar comillas dobles del nombre de carpeta para generar nombres de archivo validos
$CleanFolderName = $BookmarkFolderName -replace '"', ''

$MarkdownFileName      = "generated_MD_$CleanFolderName.md"
$HtmlPrettyFileName    = "generated_PRETTY_HTML_$CleanFolderName.html"
$RawImportableHtmlFile = "bookmarks$CleanFolderName.html"

Write-Info "Archivos que se generaran:"
Write-Host "   Markdown:        $MarkdownFileName" -ForegroundColor White
Write-Host "   HTML Pretty:     $HtmlPrettyFileName" -ForegroundColor White
Write-Host "   HTML Importable: $RawImportableHtmlFile" -ForegroundColor White

# Archivo mas reciente por fecha de creacion (la exportacion recien descargada)
$LatestFile = Get-ChildItem -Path $RawBookmarksDir -File |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1

if (-not $LatestFile) {
    Write-ErrorMsg "No se encontro ningun archivo en $RawBookmarksDir"
    exit 1
}

Write-Success "Archivo mas reciente encontrado: $($LatestFile.Name)"
Write-Info "Ejecutando script: $Bookmark2MdCmdPath"

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
    Write-ErrorMsg "Error ejecutando el script: $_"
    exit 1
}

if ($LASTEXITCODE -ne 0) {
    Write-Warn "El script termino con codigo de salida $LASTEXITCODE."
    exit $LASTEXITCODE
}

Write-Success "Script ejecutado correctamente."
