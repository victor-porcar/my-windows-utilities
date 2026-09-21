<#
.SYNOPSIS
    Backs up a Lightroom Classic catalog into a zip file.

.DESCRIPTION
    Zips the catalog file (.lrcat) together with its .lrcat-data folder, where Lightroom 11 and
    later keep masks and other data outside the catalog, into
    <BackupDir>\<catalog name>_<yyyyMMdd_HHmmss>.zip

    The .lrcat-wal and .lrcat-shm files are included when present: the catalog is a SQLite
    database and the -wal file, which can remain after Lightroom is closed, may hold changes not
    yet in the .lrcat. Lightroom applies them when it opens the restored catalog.

    Previews (Previews.lrdata, Smart Previews.lrdata) are left out by default: Lightroom
    regenerates them and they are usually much bigger than the catalog itself.

    The backup is refused while Lightroom is running (a Lightroom.exe process exists) or the
    catalog looks open (the .lrcat.lock file exists), because copying a catalog in use may
    produce an inconsistent backup.

    Only the catalog is backed up, not the photos, which live in their own folders.

.PARAMETER CatalogPath
    Catalog folder, the one holding a single .lrcat file. E.g.: D:\LR_CATALOG\v_catalog
    The path of the .lrcat file itself is accepted as well.

.PARAMETER BackupDir
    Directory where the zip is saved. Created if it does not exist. E.g.: D:\AAA

.PARAMETER IncludePreviews
    Also back up the standard and smart previews folders.

.EXAMPLE
    .\lightroom-catalog-backup.ps1 "D:\LR_CATALOG\v_catalog" "D:\AAA"

.EXAMPLE
    .\lightroom-catalog-backup.ps1 "D:\LR_CATALOG\v_catalog" "D:\AAA" -IncludePreviews
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CatalogPath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$BackupDir,

    [switch]$IncludePreviews
)

$ErrorActionPreference = "Stop"

function Write-Info($text)     { Write-Host "i  $text" -ForegroundColor Cyan }
function Write-Success($text)  { Write-Host "OK $text" -ForegroundColor Green }
function Write-ErrorMsg($text) { Write-Host "X  $text" -ForegroundColor Red }

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    return "{0:N1} MB" -f ($bytes / 1MB)
}

# Every file below the given path (the path itself when it is a file)
function Get-FilesOf([string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { return @(Get-Item -LiteralPath $path) }
    return @(Get-ChildItem -LiteralPath $path -File -Recurse -Force)
}

# Name inside the zip: path relative to the catalog folder, with forward slashes
function Get-EntryName([string]$filePath, [string]$baseDir) {
    return $filePath.Substring($baseDir.Length).TrimStart('\') -replace '\\', '/'
}

# =========================================================
# CATALOG
# A folder must hold exactly one .lrcat file; a .lrcat file is used as is
# =========================================================
if (Test-Path -LiteralPath $CatalogPath -PathType Container) {
    $catalogs = @(Get-ChildItem -LiteralPath $CatalogPath -Filter *.lrcat -File)
    if ($catalogs.Count -ne 1) {
        Write-ErrorMsg "Expected exactly one .lrcat file in $CatalogPath, found $($catalogs.Count)"
        $catalogs | ForEach-Object { Write-Host "   $($_.Name)" }
        exit 1
    }
    $CatalogPath = $catalogs[0].FullName
}

if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf) -or
    [IO.Path]::GetExtension($CatalogPath) -ne ".lrcat") {
    Write-ErrorMsg "Not a Lightroom catalog folder or .lrcat file: $CatalogPath"
    exit 1
}

$CatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$catalogDir  = Split-Path -Parent $CatalogPath
$catalogName = [IO.Path]::GetFileNameWithoutExtension($CatalogPath)

# Two independent checks: Lightroom running at all (whatever catalog it has open), and the
# .lock file Lightroom keeps next to an open catalog. A .lock left by a crash is reported apart,
# since it only needs to be deleted once Lightroom is known to be closed
if (Get-Process -Name "Lightroom" -ErrorAction SilentlyContinue) {
    Write-ErrorMsg "Lightroom is running: close it and try again"
    exit 1
}

if (Test-Path -LiteralPath "$CatalogPath.lock") {
    Write-ErrorMsg "$catalogName.lrcat.lock exists but Lightroom is not running: it was probably left by a crash."
    Write-Host "   Open and close the catalog in Lightroom, or delete that file, and try again"
    exit 1
}

# =========================================================
# WHAT GOES INTO THE ZIP
# =========================================================
# The catalog is a SQLite database: its -wal file may hold changes not yet written into the
# .lrcat (it can remain even after Lightroom is closed), so it must travel with it
$candidates = @($CatalogPath, "$CatalogPath-wal", "$CatalogPath-shm", "$CatalogPath-data")
if ($IncludePreviews) {
    $candidates += Join-Path $catalogDir "$catalogName Previews.lrdata"
    $candidates += Join-Path $catalogDir "$catalogName Smart Previews.lrdata"
}
$items = @($candidates | Where-Object { Test-Path -LiteralPath $_ })

# =========================================================
# BACKUP DIRECTORY
# =========================================================
if (-not (Test-Path -LiteralPath $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}
$BackupDir = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BackupDir).Path)

$zipFile     = Join-Path $BackupDir ("{0}_{1}.zip" -f $catalogName, (Get-Date -Format "yyyyMMdd_HHmmss"))
$partialFile = "$zipFile.partial"

Write-Host ""
Write-Host "==============================================================="
Write-Host " CATALOG : $CatalogPath"
Write-Host " BACKUP  : $zipFile" -ForegroundColor Green
Write-Host "==============================================================="
Write-Host ""

# =========================================================
# ZIP
# Written as .partial and renamed at the end, so a failed run never leaves a zip that looks complete
# =========================================================
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$start      = Get-Date
$fileCount  = 0
$totalBytes = 0L
$zip        = $null

try {
    $zip = [IO.Compression.ZipFile]::Open($partialFile, [IO.Compression.ZipArchiveMode]::Create)

    foreach ($item in $items) {
        $files = Get-FilesOf $item
        $size  = ($files | Measure-Object -Property Length -Sum).Sum
        Write-Info ("Adding {0} ({1} files, {2})" -f (Split-Path -Leaf $item), $files.Count, (Format-Size $size))

        foreach ($file in $files) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.FullName, (Get-EntryName $file.FullName $catalogDir),
                [IO.Compression.CompressionLevel]::Optimal) | Out-Null
            $fileCount++
            $totalBytes += $file.Length
        }
    }

    $zip.Dispose()
    $zip = $null
    Move-Item -LiteralPath $partialFile -Destination $zipFile
}
catch {
    if ($zip) { $zip.Dispose() }
    Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
    Write-ErrorMsg "Backup failed: $_"
    exit 1
}

# =========================================================
# SUMMARY
# =========================================================
$zipSize = (Get-Item -LiteralPath $zipFile).Length
$elapsed = (Get-Date) - $start

Write-Host ""
Write-Success ("Backup done: {0} files, {1} -> {2} in {3:mm\:ss}" -f $fileCount, (Format-Size $totalBytes), (Format-Size $zipSize), $elapsed)
Write-Host "   $zipFile"
