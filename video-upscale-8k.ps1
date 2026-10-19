<#
.SYNOPSIS
    Upscales a video to 8K (7680x4320) with ffmpeg, in the highest quality possible, as H.265,
    ProRes 422 HQ or ProRes 422 LT.

.DESCRIPTION
    Meant for videos edited at a lower resolution (5K, 6K...) that should be uploaded to YouTube as
    8K, so that YouTube processes them in its 8K tier and gives them its highest bitrate.

    Started without a format, the script shows the three it can produce with an estimate of the
    time and the size each would take for this video, and asks which one to use (ProRes 422 LT by
    default). While it works it shows the percentage done, the remaining time and the space the
    output already takes, with an estimate of its final size.

    Quality choices, all aimed at the best possible result rather than speed:
    - Scaling with Lanczos, accurate rounding and full chroma interpolation, keeping 10 bits.
    - Colour stays Rec.709 limited range, the same as an export from Premiere Pro, and the output is
      tagged accordingly so that players and YouTube read it right.
    - H.265: Main10 (10 bits, avoids banding in skies and other smooth gradients), encoded either
      by the CPU with x265 in two passes (the best quality per bit, very slow) or by the NVIDIA GPU
      with NVENC (fast, slightly less efficient).
    - ProRes 422 HQ and ProRes 422 LT: 10 bits 4:2:2, with lossless 24-bit PCM audio. HQ is the
      mastering grade; LT takes about half the space and, for an upload to YouTube, looks the same.

    The aspect ratio is kept: a video that is not 16:9 is scaled to fit inside 7680x4320.

    Time estimates come from the speed of the previous runs on this computer, stored in
    %LOCALAPPDATA%\video-upscale-8k\speeds.json; until a format has been run once, a rough value
    measured on a PC with a GeForce RTX 2060 is used. ProRes sizes are upper bounds: dark footage,
    such as night skies, takes much less.

    ffmpeg.exe and ffprobe.exe are taken from:
    %GITHUB_VICTOR_PORCAR%\my-windows-utilities\software-yt-dlp

.PARAMETER InputFile
    Video to upscale. E.g.: G:\8k\video_6k.mov

.PARAMETER Codec
    h265, prores422hq or prores422lt. If omitted, the script shows the three with their estimates
    and asks, prores422lt being the default.

.PARAMETER BitrateMbps
    Only for h265: target bitrate in Mbps. If omitted, the script asks for it, suggesting 250,
    which is quality to spare for YouTube in 8K.

.PARAMETER Encoder
    Only for h265: x265 (CPU, best quality, very slow) or nvenc (NVIDIA GPU, fast). If omitted,
    the script asks, x265 being the default.

.PARAMETER OutputDir
    Directory where the result is saved. By default, the directory of the input file.
    The output is named "<input name>_8K_H265.mp4", "<input name>_8K_ProRes422HQ.mov" or
    "<input name>_8K_ProRes422LT.mov".

.PARAMETER Force
    Overwrite the output file if it already exists.

.EXAMPLE
    .\video-upscale-8k.ps1 "G:\8k\video_6k.mov"
    Shows the three formats with their estimates and asks.

.EXAMPLE
    .\video-upscale-8k.ps1 "G:\8k\video_6k.mov" prores422lt

.EXAMPLE
    .\video-upscale-8k.ps1 "G:\8k\video_6k.mov" h265 250 -Encoder nvenc

.EXAMPLE
    .\video-upscale-8k.ps1 "G:\8k\video_6k.mov" prores422hq -OutputDir "G:\8k\out"

.EXAMPLE
    .\video-upscale-8k.ps1 "G:\8k\video_6k.mov" prores422lt -Verbose
    Also shows the whole ffmpeg log.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputFile,

    [Parameter(Position = 1)]
    [ValidateSet("h265", "prores422hq", "prores422lt", "")]
    [string]$Codec = "",

    [Parameter(Position = 2)]
    [ValidateRange(0, 800)]
    [int]$BitrateMbps = 0,

    [ValidateSet("x265", "nvenc", "")]
    [string]$Encoder = "",

    [string]$OutputDir = "",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$TargetWidth  = 7680
$TargetHeight = 4320
$RecommendedBitrateMbps = 250

# Rough speed, in 8K frames per second, used until a mode has been run once on this computer.
# Measured, or extrapolated, on a PC with a GeForce RTX 2060; the scaling takes most of the time.
$DefaultFps = @{
    "prores422hq" = 3.0
    "prores422lt" = 3.2
    "h265-nvenc"  = 3.0
    "h265-x265"   = 0.25   # both passes together
}

# ProRes data rates published by Apple for 1920x1080 at 29.97 fps, in Mbps. They are the most
# ProRes spends; scaled by pixel count and frame rate they give the upper bound of the size.
$ProResMbps1080p30 = @{ "prores422hq" = 220.0; "prores422lt" = 102.0 }

$repoRoot = $env:GITHUB_VICTOR_PORCAR
if (-not $repoRoot) {
    Write-Error "The GITHUB_VICTOR_PORCAR environment variable is not defined"
    exit 1
}

$SoftwareDir = Join-Path (Join-Path $repoRoot "my-windows-utilities") "software-yt-dlp"
$FfmpegPath  = Join-Path $SoftwareDir "ffmpeg.exe"
$FfprobePath = Join-Path $SoftwareDir "ffprobe.exe"

foreach ($exe in @($FfmpegPath, $FfprobePath)) {
    if (-not (Test-Path $exe)) {
        Write-Error "$(Split-Path -Leaf $exe) not found at: $exe"
        exit 1
    }
}

$Invariant = [Globalization.CultureInfo]::InvariantCulture

# Where the speed of each run is remembered, to estimate the next ones
$speedsDir = $env:LOCALAPPDATA
if (-not $speedsDir) { $speedsDir = [IO.Path]::GetTempPath() }
$SpeedsFile = Join-Path (Join-Path $speedsDir "video-upscale-8k") "speeds.json"

# --- Helpers -------------------------------------------------------------------------------

# ffprobe and ffmpeg numbers always use '.', whatever the Windows regional settings say
function ConvertTo-Number([string]$Text) {
    $value = 0.0
    if ($Text -match '^(\d+)/(\d+)$') {
        if ([double]$Matches[2] -eq 0) { return 0.0 }
        return [double]$Matches[1] / [double]$Matches[2]
    }
    if ([double]::TryParse($Text, [Globalization.NumberStyles]::Float, $Invariant, [ref]$value)) { return $value }
    return 0.0
}

function Format-Duration([double]$Seconds) {
    $span = [TimeSpan]::FromSeconds([math]::Max(0, [math]::Round($Seconds)))
    return "{0}:{1:00}:{2:00}" -f [math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ($Bytes / 1GB).ToString("0.0", $Invariant) + " GB" }
    return ($Bytes / 1MB).ToString("0", $Invariant) + " MB"
}

function Read-Speeds {
    try {
        if (Test-Path -LiteralPath $SpeedsFile) {
            $json = Get-Content -LiteralPath $SpeedsFile -Raw | ConvertFrom-Json
            $speeds = @{}
            foreach ($p in $json.PSObject.Properties) { $speeds[$p.Name] = [double]$p.Value }
            return $speeds
        }
    }
    catch { Write-Verbose "Could not read $SpeedsFile; using the default speeds" }
    return @{}
}

function Save-Speed([string]$Mode, [double]$Fps) {
    try {
        $speeds = Read-Speeds
        $speeds[$Mode] = [math]::Round($Fps, 3)
        $folder = Split-Path -Parent $SpeedsFile
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        $speeds | ConvertTo-Json | Set-Content -LiteralPath $SpeedsFile -Encoding ASCII
    }
    catch { Write-Verbose "Could not save the speed to $SpeedsFile" }
}

# Estimated seconds for a mode, and whether the speed was measured here or is the default one
function Get-TimeEstimate([string]$Mode) {
    $measured = $script:Speeds.ContainsKey($Mode)
    if ($measured) { $fps = $script:Speeds[$Mode] } else { $fps = $DefaultFps[$Mode] }
    $text = "~" + (Format-Duration ($script:TotalFrames / $fps))
    if (-not $measured) { $text += " (rough)" }
    return $text
}

function Get-SizeEstimate([string]$Codec, [int]$Mbps) {
    if ($Codec -eq "h265") { $videoMbps = $Mbps }
    else {
        $pixelFactor = ($script:OutWidth * $script:OutHeight) / (1920.0 * 1080.0)
        $videoMbps = $ProResMbps1080p30[$Codec] * $pixelFactor * ($script:FrameRate / 29.97)
    }
    return $videoMbps * 1e6 / 8 * $script:Duration
}

# Asks until the answer is valid; an empty answer takes the default
function Read-Choice([string]$Prompt, [string]$Default, [scriptblock]$IsValid) {
    while ($true) {
        $answer = (Read-Host "$Prompt [$Default]").Trim()
        if (-not $answer) { $answer = $Default }
        if (& $IsValid $answer) { return $answer }
        Write-Host "  Not valid: $answer"
    }
}

# Runs ffmpeg showing percentage, speed, elapsed and remaining time and the space the output
# takes, and stops the script if it fails. ffmpeg writes its progress as key=value lines on stdout
# (-progress pipe:1); errors still go to the console through stderr.
# PassesAfter: how many more passes of the same length follow, so the remaining time covers them.
function Invoke-Ffmpeg([string[]]$Arguments, [int]$PassesAfter = 0, [switch]$NoSize) {
    $Arguments = @("-nostats", "-progress", "pipe:1") + $Arguments
    Write-Verbose ("ffmpeg " + ($Arguments -join " "))

    $started = Get-Date
    $state = @{ frame = 0; fps = 0.0; size = 0.0; lineLength = 0 }
    $total = $script:TotalFrames

    & $FfmpegPath @Arguments | ForEach-Object {
        if ($_ -match '^frame=(\d+)') { $state.frame = [int]$Matches[1] }
        elseif ($_ -match '^fps=(.+)$') { $state.fps = ConvertTo-Number $Matches[1] }
        elseif ($_ -match '^total_size=(\d+)') { $state.size = [double]$Matches[1] }
        elseif ($_ -match '^progress=') {
            $elapsed = ((Get-Date) - $started).TotalSeconds
            $done = $state.frame

            if ($total -gt 0) {
                $percent = [math]::Min(100.0, 100.0 * $done / $total)
                $line = "  " + $percent.ToString("0.0", $Invariant).PadLeft(5) + "%  $done/$total frames"
            }
            else { $line = "  $done frames" }
            $line += "  " + $state.fps.ToString("0.0", $Invariant) + " fps  " + (Format-Duration $elapsed) + " elapsed"

            if ($total -gt 0 -and $done -gt 0) {
                $passSeconds = $elapsed * $total / $done
                $remaining = ($passSeconds - $elapsed) + $PassesAfter * $passSeconds
                $line += "  " + (Format-Duration $remaining) + " left"
            }
            if (-not $NoSize -and $state.size -gt 0) {
                $line += "  " + (Format-Size $state.size)
                if ($total -gt 0 -and $done -gt 0 -and $done -lt $total) {
                    $line += " (~" + (Format-Size ($state.size * $total / $done)) + " at the end)"
                }
            }

            # Rewrite the same console line; pad to wipe a longer previous one
            Write-Host -NoNewline ("`r" + $line.PadRight($state.lineLength))
            $state.lineLength = $line.Length
        }
    }
    Write-Host ""

    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg finished with exit code $LASTEXITCODE"
    }
}

try {
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        throw "Input file not found: $InputFile"
    }
    $InputFile = (Resolve-Path -LiteralPath $InputFile).Path

    # --- What the input is ---------------------------------------------------------------
    $probeJson = & $FfprobePath -v error -show_streams -show_format -of json -- $InputFile
    if ($LASTEXITCODE -ne 0) { throw "ffprobe could not read: $InputFile" }
    $probe = ($probeJson -join "`n") | ConvertFrom-Json

    $video = $probe.streams | Where-Object { $_.codec_type -eq "video" -and -not ($_.disposition.attached_pic -eq 1) } | Select-Object -First 1
    $audio = $probe.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1
    if (-not $video) { throw "No video stream in: $InputFile" }

    $inWidth  = [int]$video.width
    $inHeight = [int]$video.height

    $script:FrameRate = ConvertTo-Number "$($video.avg_frame_rate)"
    if ($script:FrameRate -le 0) { $script:FrameRate = ConvertTo-Number "$($video.r_frame_rate)" }
    $script:Duration = ConvertTo-Number "$($video.duration)"
    if ($script:Duration -le 0) { $script:Duration = ConvertTo-Number "$($probe.format.duration)" }

    # Number of frames, for the percentage and the remaining time. Not every container stores it,
    # so otherwise it is worked out from the duration and the frame rate.
    $script:TotalFrames = 0
    if ($video.nb_frames -match '^\d+$') { $script:TotalFrames = [int]$video.nb_frames }
    if ($script:TotalFrames -le 0) { $script:TotalFrames = [int][math]::Round($script:Duration * $script:FrameRate) }

    # Fit inside the target keeping the aspect ratio; dimensions must be even
    $factor = [math]::Min($TargetWidth / $inWidth, $TargetHeight / $inHeight)
    if ($factor -le 1) {
        throw "The video is already ${inWidth}x${inHeight}: there is nothing to upscale to 8K"
    }
    $script:OutWidth  = [int]([math]::Floor($inWidth  * $factor / 2) * 2)
    $script:OutHeight = [int]([math]::Floor($inHeight * $factor / 2) * 2)
    $outWidth  = $script:OutWidth
    $outHeight = $script:OutHeight

    if ($video.color_space -and $video.color_space -notin @("bt709", "unknown")) {
        Write-Warning "The input is tagged as '$($video.color_space)', not Rec.709. The output is Rec.709: check the colours."
    }

    $audioText = "no audio"
    if ($audio) { $audioText = "audio $($audio.codec_name)" }
    Write-Host "Input:  $InputFile"
    Write-Host ("        ${inWidth}x${inHeight}, $($video.codec_name), $($video.pix_fmt), $audioText, " +
        (Format-Duration $script:Duration) + ", $($script:TotalFrames) frames at " + $script:FrameRate.ToString("0.##", $Invariant) + " fps")
    if ($outWidth -ne $TargetWidth -or $outHeight -ne $TargetHeight) {
        Write-Warning "The input is not 16:9; it is scaled to ${outWidth}x${outHeight} to keep its proportions."
    }

    $script:Speeds = Read-Speeds

    # --- What to produce -----------------------------------------------------------------
    if (-not $Codec) {
        $h265Size = Format-Size (Get-SizeEstimate "h265" $RecommendedBitrateMbps)
        $hqSize   = Format-Size (Get-SizeEstimate "prores422hq" 0)
        $ltSize   = Format-Size (Get-SizeEstimate "prores422lt" 0)

        Write-Host ""
        Write-Host "Output format:"
        Write-Host "  1) H.265 Main10 (.mp4)   ~$h265Size at $RecommendedBitrateMbps Mbps   time: nvenc $(Get-TimeEstimate 'h265-nvenc'), x265 $(Get-TimeEstimate 'h265-x265')"
        Write-Host "  2) ProRes 422 HQ (.mov)  up to $hqSize   time: $(Get-TimeEstimate 'prores422hq')"
        Write-Host "  3) ProRes 422 LT (.mov)  up to $ltSize   time: $(Get-TimeEstimate 'prores422lt')"
        Write-Host "  ProRes sizes are upper bounds: dark footage, such as night skies, takes much less."
        $choice = Read-Choice "Choice - 1/2/3" "3" { param($a) $a -in @("1", "2", "3") }
        $Codec = @{ "1" = "h265"; "2" = "prores422hq"; "3" = "prores422lt" }[$choice]
    }

    if ($Codec -eq "h265") {
        if ($BitrateMbps -le 0) {
            Write-Host ""
            Write-Host "Bitrate for H.265 in 8K: $RecommendedBitrateMbps Mbps is quality to spare for YouTube; more barely shows after YouTube re-encodes it."
            $BitrateMbps = [int](Read-Choice "Bitrate in Mbps (20-800)" "$RecommendedBitrateMbps" { param($a) ($a -match '^\d+$') -and ([int]$a -ge 20) -and ([int]$a -le 800) })
        }
        if ($BitrateMbps -lt 20) {
            throw "A bitrate under 20 Mbps makes no sense for 8K"
        }
        if (-not $Encoder) {
            Write-Host ""
            Write-Host "Encoder:"
            Write-Host "  1) x265   CPU, the best quality per bit, very slow   $(Get-TimeEstimate 'h265-x265')"
            Write-Host "  2) nvenc  NVIDIA GPU, fast, slightly less efficient    $(Get-TimeEstimate 'h265-nvenc')"
            $choice = Read-Choice "Choice - 1/2" "1" { param($a) $a -in @("1", "2", "x265", "nvenc") }
            $Encoder = @{ "1" = "x265"; "2" = "nvenc"; "x265" = "x265"; "nvenc" = "nvenc" }[$choice]
        }
        $Mode = "h265-$Encoder"
    }
    else {
        $Mode = $Codec
    }

    if (-not $OutputDir) { $OutputDir = Split-Path -Parent $InputFile }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    $OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

    $baseName = [IO.Path]::GetFileNameWithoutExtension($InputFile)
    $outName = @{
        "h265"        = "${baseName}_8K_H265.mp4"
        "prores422hq" = "${baseName}_8K_ProRes422HQ.mov"
        "prores422lt" = "${baseName}_8K_ProRes422LT.mov"
    }[$Codec]
    $OutputFile = Join-Path $OutputDir $outName

    if ((Test-Path -LiteralPath $OutputFile) -and -not $Force) {
        throw "The output already exists (use -Force to overwrite it): $OutputFile"
    }

    # Free space on the destination drive against the estimated size
    $estimatedBytes = Get-SizeEstimate $Codec $BitrateMbps
    try {
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($OutputDir))
        if ($drive.AvailableFreeSpace -lt $estimatedBytes) {
            Write-Warning ("Only " + (Format-Size $drive.AvailableFreeSpace) + " free on " + $drive.Name +
                ", and the output may take up to " + (Format-Size $estimatedBytes) + ".")
        }
    }
    catch { Write-Verbose "Could not check the free space of $OutputDir" }

    # --- Common ffmpeg arguments ---------------------------------------------------------
    $logLevel = "error"
    if ($VerbosePreference -eq "Continue") { $logLevel = "info" }

    $baseArgs = @("-hide_banner", "-nostdin", "-y", "-loglevel", $logLevel, "-i", $InputFile)

    # Lanczos with accurate rounding and full chroma interpolation: the sharpest and cleanest
    # scaler ffmpeg has. Colour matrix and range are pinned so the scaler never converts them.
    if ($Codec -eq "h265") { $pixFmt = "yuv420p10le" } else { $pixFmt = "yuv422p10le" }
    $scaleFilter = "scale=w=${outWidth}:h=${outHeight}" +
        ":flags=lanczos+accurate_rnd+full_chroma_int+full_chroma_inp" +
        ":in_color_matrix=bt709:out_color_matrix=bt709:in_range=tv:out_range=tv" +
        ",format=$pixFmt"

    $colourArgs = @(
        "-color_primaries", "bt709", "-color_trc", "bt709",
        "-colorspace", "bt709", "-color_range", "tv"
    )
    $mapArgs = @("-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "0", "-vf", $scaleFilter)

    Write-Host ""
    Write-Host "Output: $OutputFile"

    $started = Get-Date

    if ($Codec -like "prores*") {
        if ($Codec -eq "prores422hq") { $proresProfile = "hq"; $profileText = "HQ" } else { $proresProfile = "lt"; $profileText = "LT" }
        Write-Host "        ${outWidth}x${outHeight}, ProRes 422 $profileText 10-bit, estimated $(Get-TimeEstimate $Mode)"
        # Lossless audio, as befits a ProRes master
        if ($audio -and $audio.codec_name -like "pcm_*") { $audioArgs = @("-c:a", "copy") } else { $audioArgs = @("-c:a", "pcm_s24le") }

        Invoke-Ffmpeg ($baseArgs + $mapArgs + @(
            "-c:v", "prores_ks", "-profile:v", $proresProfile, "-vendor", "apl0", "-pix_fmt", $pixFmt
        ) + $colourArgs + $audioArgs + @($OutputFile))
    }
    else {
        $bitrate = "${BitrateMbps}M"
        $maxrate = "$([int]($BitrateMbps * 1.5))M"
        $bufsize = "$([int]($BitrateMbps * 2))M"

        # AAC is kept as it is; anything else becomes AAC 320 kbps, which is what fits in an .mp4
        if ($audio -and $audio.codec_name -eq "aac") { $audioArgs = @("-c:a", "copy") } else { $audioArgs = @("-c:a", "aac", "-b:a", "320k") }
        $mp4Args = @("-tag:v", "hvc1", "-movflags", "+faststart")

        if ($Encoder -eq "nvenc") {
            Write-Host "        ${outWidth}x${outHeight}, H.265 Main10, $BitrateMbps Mbps, NVIDIA NVENC, estimated $(Get-TimeEstimate $Mode)"

            # An 8K 10-bit frame takes about 100 MB of GPU memory, and NVENC keeps one per input
            # buffer: every frame of look-ahead costs one more. With 6 GB cards in mind, the
            # look-ahead is short and the first pass of the multipass runs at quarter resolution.
            $nvencArgs = @(
                "-c:v", "hevc_nvenc", "-preset", "p7", "-tune", "hq", "-profile:v", "main10",
                "-tier", "high", "-rc", "vbr",
                "-b:v", $bitrate, "-maxrate", $maxrate, "-bufsize", $bufsize, "-spatial-aq", "1"
            )
            $nvencNormal = @("-multipass", "qres", "-rc-lookahead", "8", "-temporal-aq", "1")
            # Last resort when the GPU memory is still short: no look-ahead, no multipass,
            # no B-frames and the fewest input buffers. At a high bitrate the loss is small.
            $nvencLean   = @("-multipass", "disabled", "-rc-lookahead", "0", "-bf", "0", "-surfaces", "4")

            try {
                Invoke-Ffmpeg ($baseArgs + $mapArgs + $nvencArgs + $nvencNormal + $colourArgs + $audioArgs + $mp4Args + @($OutputFile))
            }
            catch {
                Write-Host ""
                Write-Warning "NVENC failed, most likely for lack of GPU memory. Retrying with the settings that need the least of it."
                Write-Warning "Closing Premiere Pro, browsers and other programs that use the GPU also helps."
                Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue
                $started = Get-Date
                Invoke-Ffmpeg ($baseArgs + $mapArgs + $nvencArgs + $nvencLean + $colourArgs + $audioArgs + $mp4Args + @($OutputFile))
            }
        }
        else {
            Write-Host "        ${outWidth}x${outHeight}, H.265 Main10, $BitrateMbps Mbps, x265 two passes, estimated $(Get-TimeEstimate $Mode)"

            $x265Log = "error"
            if ($VerbosePreference -eq "Continue") { $x265Log = "info" }

            # aq-mode=3 favours dark areas (night skies); no-sao keeps fine detail such as stars
            $x265Common = "log-level=$x265Log:aq-mode=3:no-sao=1:vbv-maxrate=$($BitrateMbps * 1500):vbv-bufsize=$($BitrateMbps * 2000)" +
                ":colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited"
            $x265Args = @("-c:v", "libx265", "-preset", "slow", "-profile:v", "main10", "-b:v", $bitrate)

            # The x265 stats file is given as a relative name: x265-params uses ':' as separator,
            # so a Windows path like C:\... cannot go there. ffmpeg runs inside a temp folder instead.
            $workDir = Join-Path ([IO.Path]::GetTempPath()) ("video-upscale-8k-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $workDir | Out-Null
            if ($env:OS -eq "Windows_NT") { $nullOutput = "NUL" } else { $nullOutput = "/dev/null" }

            Push-Location $workDir
            try {
                Write-Host ""
                Write-Host "Pass 1 of 2 (analysis; the time left includes pass 2)"
                Invoke-Ffmpeg ($baseArgs + @("-map", "0:v:0", "-vf", $scaleFilter) + $x265Args + @(
                    "-x265-params", "pass=1:stats=x265.log:$x265Common", "-an", "-f", "null", $nullOutput
                )) -PassesAfter 1 -NoSize

                Write-Host ""
                Write-Host "Pass 2 of 2 (encoding)"
                Invoke-Ffmpeg ($baseArgs + $mapArgs + $x265Args + @(
                    "-x265-params", "pass=2:stats=x265.log:$x265Common"
                ) + $colourArgs + $audioArgs + $mp4Args + @($OutputFile))
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $elapsed = ((Get-Date) - $started).TotalSeconds
    if ($elapsed -gt 0 -and $script:TotalFrames -gt 0) { Save-Speed $Mode ($script:TotalFrames / $elapsed) }

    $result = Get-Item -LiteralPath $OutputFile
    Write-Host ""
    Write-Host "Saved: $($result.FullName) ($(Format-Size $result.Length)) in $(Format-Duration $elapsed)"
}
catch {
    Write-Error $_
    exit 1
}
