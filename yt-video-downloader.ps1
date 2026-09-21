<#
.SYNOPSIS
    Downloads a single YouTube video in the best available quality using yt-dlp.

.DESCRIPTION
    Video and audio are downloaded as separate best-quality streams and merged with ffmpeg
    into a single .mp4 file named "<title> [<id>].mp4".

    Both yt-dlp.exe and ffmpeg.exe are taken from:
    %GITHUB-VICTOR-PORCAR%\my-windows-utilities\software-yt-dlp

.PARAMETER VideoUrl
    URL of the video. E.g.: https://www.youtube.com/watch?v=jNQXAC9IVRw

.PARAMETER OutputDir
    Directory where the video is saved. Created if it does not exist. E.g.: C:\temp

.EXAMPLE
    .\yt-video-downloader.ps1 "https://www.youtube.com/watch?v=jNQXAC9IVRw" "C:\temp"

.EXAMPLE
    .\yt-video-downloader.ps1 "https://www.youtube.com/watch?v=jNQXAC9IVRw" "C:\temp" -Verbose
    Also shows the whole yt-dlp log.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$VideoUrl,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

# The braces are required: without them PowerShell reads the hyphens as operators
$repoRoot = ${env:GITHUB-VICTOR-PORCAR}
if (-not $repoRoot) {
    Write-Error "The GITHUB-VICTOR-PORCAR environment variable is not defined"
    exit 1
}

$SoftwareDir = Join-Path $repoRoot "my-windows-utilities\software-yt-dlp"
$YtDlpPath   = Join-Path $SoftwareDir "yt-dlp.exe"
$FfmpegPath  = Join-Path $SoftwareDir "ffmpeg.exe"

foreach ($exe in @($YtDlpPath, $FfmpegPath)) {
    if (-not (Test-Path $exe)) {
        Write-Error "$(Split-Path -Leaf $exe) not found at: $exe"
        exit 1
    }
}

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$OutputDir = [IO.Path]::GetFullPath((Resolve-Path $OutputDir).Path)

# yt-dlp writes UTF-8; this keeps PowerShell from mangling accents in titles
[Console]::OutputEncoding = [Text.Encoding]::UTF8

try {
    # bv*+ba: best video plus best audio, merged; b: fallback to the best single stream
    $ytArgs = @(
        "--format", "bv*+ba/b"
        "--merge-output-format", "mp4"
        "--ffmpeg-location", $SoftwareDir
        "--paths", $OutputDir
        "--output", "%(title)s [%(id)s].%(ext)s"
        "--no-playlist"
        "--no-mtime"
        "--embed-metadata"
        "--embed-thumbnail"
        "--newline"
    )
    if ($VerbosePreference -eq "Continue") { $ytArgs += "--verbose" }
    $ytArgs += $VideoUrl

    Write-Host "Downloading $VideoUrl"
    Write-Host "Destination: $OutputDir"

    & $YtDlpPath @ytArgs
    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp finished with exit code $LASTEXITCODE"
    }

    # --print after_move:filepath would need a second pass; the newest file is the one just merged
    $downloaded = Get-ChildItem -Path $OutputDir -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($downloaded) {
        $sizeMb = [math]::Round($downloaded.Length / 1MB, 1)
        Write-Host "Saved: $($downloaded.FullName) ($sizeMb MB)"
    }
}
catch {
    Write-Error $_
    exit 1
}
