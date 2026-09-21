<#
.SYNOPSIS
    Downloads the audio track of a single YouTube video in the best available quality using yt-dlp.

.DESCRIPTION
    The best audio stream is downloaded and extracted with ffmpeg into a file named
    "<title> [<id>].<ext>".

    Both yt-dlp.exe and ffmpeg.exe are taken from:
    %GITHUB-VICTOR-PORCAR%\my-windows-utilities\software-yt-dlp

.PARAMETER VideoUrl
    URL of the video. E.g.: https://www.youtube.com/watch?v=jNQXAC9IVRw

.PARAMETER OutputDir
    Directory where the audio is saved. Created if it does not exist. E.g.: C:\temp

.PARAMETER AudioFormat
    Output format. Default is mp3 (re-encoded at the highest VBR quality).
    Use 'best' to keep YouTube's original stream (opus/m4a) with no re-encoding at all,
    which is the only truly lossless option.

.EXAMPLE
    .\yt-sound-downloader.ps1 "https://www.youtube.com/watch?v=jNQXAC9IVRw" "C:\temp"

.EXAMPLE
    .\yt-sound-downloader.ps1 "https://www.youtube.com/watch?v=jNQXAC9IVRw" "C:\temp" best
    Keeps the original audio stream instead of converting it to mp3.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$VideoUrl,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputDir,

    [Parameter(Position = 2)]
    [ValidateSet("mp3", "best", "m4a", "opus", "flac", "wav")]
    [string]$AudioFormat = "mp3"
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
    # ba: best audio-only stream; b: fallback to the best stream with audio
    $ytArgs = @(
        "--format", "ba/b"
        "--extract-audio"
        "--audio-format", $AudioFormat
        "--audio-quality", "0"
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

    Write-Host "Downloading audio of $VideoUrl"
    Write-Host "Format: $AudioFormat"
    Write-Host "Destination: $OutputDir"

    & $YtDlpPath @ytArgs
    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp finished with exit code $LASTEXITCODE"
    }

    # The newest file in the folder is the one just extracted
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
