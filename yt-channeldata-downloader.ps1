<#
.SYNOPSIS
    Downloads, as JSON, the most relevant information of all videos of a public YouTube channel using yt-dlp.

.DESCRIPTION
    The data is saved in OutputDir as YOUTUBE_CHANNEL_<channel handle>_<yyyyMMdd_HHmmss>.zip, holding
    a JSON file of the same name with the channel data plus, for every video (Videos, Shorts, Live tabs):
    id, url, title, description, upload date, duration, views, likes, comments, tags...

.PARAMETER ChannelUrl
    Channel URL. E.g.: https://www.youtube.com/@YouTube

.PARAMETER OutputDir
    Directory where the JSON file is saved. Created if it does not exist. E.g.: C:\temp

.PARAMETER BackupsToKeep
    How many files of this channel are kept in OutputDir, counting the one just saved.
    The oldest beyond that number are deleted. Only this channel's YOUTUBE_CHANNEL_*.zip files
    (and the .json files saved by older versions of this script) are considered, so other files
    and other channels in the same directory are never touched.

.PARAMETER Fast
    Uses --flat-playlist: much faster, but without description, tags, likes or upload date.

.PARAMETER YtDlpPath
    Path to yt-dlp.exe. Defaults to %GITHUB-VICTOR-PORCAR%\my-windows-utilities\software-yt-dlp\yt-dlp.exe

.EXAMPLE
    .\yt-channeldata-downloader.ps1 "https://www.youtube.com/@YouTube" "C:\temp" 5
    Keeps the 5 newest files of the channel, counting the new one.

.EXAMPLE
    .\yt-channeldata-downloader.ps1 "https://www.youtube.com/@YouTube" "C:\temp" 5 -Verbose
    Also shows the whole yt-dlp log.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ChannelUrl,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$BackupsToKeep,

    [switch]$Fast,

    [string]$YtDlpPath
)

$ErrorActionPreference = "Stop"

# Resolved and announced up front, so the destination is clear before any download starts
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$OutputDir = [IO.Path]::GetFullPath((Resolve-Path $OutputDir).Path)

Write-Host ""
Write-Host "==============================================================="
Write-Host " OUTPUT DIRECTORY: $OutputDir" -ForegroundColor Green
Write-Host "==============================================================="
Write-Host ""

if (-not $YtDlpPath) {
    # The braces are required: without them PowerShell reads the hyphens as operators
    $utilsRoot = ${env:GITHUB-VICTOR-PORCAR}
    if (-not $utilsRoot) {
        Write-Error "The GITHUB-VICTOR-PORCAR environment variable is not defined"
        exit 1
    }
    $YtDlpPath = Join-Path $utilsRoot "my-windows-utilities\software-yt-dlp\yt-dlp.exe"
}

if (-not (Test-Path $YtDlpPath)) {
    Write-Error "yt-dlp.exe not found at: $YtDlpPath"
    exit 1
}
$YtDlpPath = (Resolve-Path $YtDlpPath).Path

# yt-dlp writes the JSON as UTF-8; this keeps PowerShell from mangling accents when capturing it
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Format-YtDate([string]$d) {
    # yt-dlp dates come as yyyyMMdd
    if ($d -match '^(\d{4})(\d{2})(\d{2})$') { return "$($Matches[1])-$($Matches[2])-$($Matches[3])" }
    return $d
}

# Saves text as the only entry of a new zip. It is written as .partial and renamed at the end,
# so a failed run never leaves a zip that looks complete
function Save-TextAsZip([string]$zipPath, [string]$entryName, [string]$text) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $partial = "$zipPath.partial"
    try {
        $zip = [IO.Compression.ZipFile]::Open($partial, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry  = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
            try { $writer.Write($text) } finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
        Move-Item -LiteralPath $partial -Destination $zipPath -Force
    }
    catch {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        throw
    }
}

# Deletes the oldest files of the channel so that only $keep remain, counting the one just
# saved. The date in the name sorts them; files of other channels and the one just saved are never touched.
# The .json files and the date-only names (_yyyyMMdd) of older versions of this script are matched too
function Remove-OldChannelFiles([string]$dir, [string]$channelKey, [string]$justSaved, [int]$keep) {
    $pattern = '^YOUTUBE_CHANNEL_' + [regex]::Escape($channelKey) + '_\d{8}(_\d{6})?\.(zip|json)$'
    Get-ChildItem -LiteralPath $dir -File |
        Where-Object { $_.Name -match $pattern -and $_.Name -ne $justSaved } |
        Sort-Object Name -Descending |
        Select-Object -Skip ($keep - 1) |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName
            Write-Host "Old file deleted: $($_.Name)"
        }
}

try {
    # -j prints one JSON line per video as soon as it is processed, which gives real progress
    $ytArgs = @("-j", "--ignore-errors", "--no-warnings")
    if ($Fast) { $ytArgs += "--flat-playlist" }
    if ($VerbosePreference -eq "Continue") { $ytArgs += "--verbose" }
    $ytArgs += $ChannelUrl

    Write-Host "Querying $ChannelUrl ..."
    $start = Get-Date
    $channel = $null
    $videos = New-Object System.Collections.Generic.List[object]

    & $YtDlpPath @ytArgs | ForEach-Object {
        $v = $_ | ConvertFrom-Json

        if (-not $channel) {
            $channel = [ordered]@{
                id             = $v.channel_id
                handle         = $v.uploader_id
                name           = $v.channel
                url            = $v.channel_url
                follower_count = $v.channel_follower_count
            }
        }

        # Tab name: yt-dlp names the playlist "<channel> - Videos", "<channel> - Shorts"...
        $tab = if ($v.playlist -match ' - (\w+)$') { $Matches[1] } else { $v.playlist }

        $videos.Add([ordered]@{
            id            = $v.id
            url           = if ($v.webpage_url) { $v.webpage_url } else { $v.url }
            tab           = $tab
            title         = $v.title
            description   = $v.description
            upload_date   = Format-YtDate $v.upload_date
            duration      = $v.duration
            duration_text = $v.duration_string
            view_count    = $v.view_count
            like_count    = $v.like_count
            comment_count = $v.comment_count
            language      = $v.language
            tags          = $v.tags
            categories    = $v.categories
            chapters      = @($v.chapters | Where-Object { $_ } | ForEach-Object { [ordered]@{ start = $_.start_time; title = $_.title } })
            thumbnail     = if ($v.thumbnail) { $v.thumbnail } else { ($v.thumbnails | Select-Object -Last 1).url }
            availability  = $v.availability
            live_status   = $v.live_status
        })

        $total = if ($v.n_entries) { "/$($v.n_entries)" } else { "" }
        Write-Host ("[{0:mm\:ss}] {1} {2}{3}  {4}  {5}" -f ((Get-Date) - $start), $tab, $v.playlist_index, $total, (Format-YtDate $v.upload_date), $v.title)
    }

    if ($videos.Count -eq 0) {
        throw "yt-dlp returned no videos for $ChannelUrl (exit code $LASTEXITCODE)"
    }

    # File name: YOUTUBE_CHANNEL_<handle without @ (or channel id)>_<yyyyMMdd_HHmmss>.zip, holding the .json
    $channelKey = if ($channel.handle) { $channel.handle.TrimStart("@") } else { $channel.id }
    $channelKey = $channelKey -replace '[\\/:*?"<>|]', '_'
    $baseName = "YOUTUBE_CHANNEL_{0}_{1}" -f $channelKey, (Get-Date -Format "yyyyMMdd_HHmmss")
    $fileName = "$baseName.zip"

    $outFile = Join-Path $OutputDir $fileName

    $result = [ordered]@{
        channel      = $channel
        generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        video_count  = $videos.Count
        videos       = $videos
    }
    $json = $result | ConvertTo-Json -Depth 10
    # ConvertTo-Json in Windows PowerShell escapes some characters (', <, >, &) as \u00XX; undo it for readability
    $json = [regex]::Replace($json, '\\u00(27|3c|3e|26)', { param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16) })

    Save-TextAsZip $outFile "$baseName.json" $json
    Write-Host ""
    Write-Host "Saved $($videos.Count) videos to $outFile" -ForegroundColor Green

    Remove-OldChannelFiles $OutputDir $channelKey $fileName $BackupsToKeep
}
catch {
    Write-Error $_
    exit 1
}
