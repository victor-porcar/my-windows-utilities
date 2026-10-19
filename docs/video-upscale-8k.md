# video-upscale-8k.ps1

Upscales a video to 8K (7680x4320) with ffmpeg in the highest quality it can, as H.265,
ProRes 422 HQ or ProRes 422 LT.

```
powershell -ExecutionPolicy Bypass -File video-upscale-8k.ps1 "G:\8k\video_6k.mov"
```

Started like that, the script shows the three formats with the time and size each would take for
this video, and asks which one to use:

```
Output format:
  1) H.265 Main10 (.mp4)   ~21.9 GB at 250 Mbps   time: nvenc ~2:05:40 (rough), x265 ~25:08:00 (rough)
  2) ProRes 422 HQ (.mov)  up to 309.3 GB   time: ~2:05:40
  3) ProRes 422 LT (.mov)  up to 143.3 GB   time: ~1:57:49 (rough)
  ProRes sizes are upper bounds: dark footage, such as night skies, takes much less.
Choice - 1/2/3 [3]:
```

ProRes 422 LT is the default. For H.265 it then asks for the bitrate and the encoder. Everything
can also be given on the command line, so it can run unattended:

```
powershell -ExecutionPolicy Bypass -File video-upscale-8k.ps1 "G:\8k\video_6k.mov" prores422lt
powershell -ExecutionPolicy Bypass -File video-upscale-8k.ps1 "G:\8k\video_6k.mov" prores422hq
powershell -ExecutionPolicy Bypass -File video-upscale-8k.ps1 "G:\8k\video_6k.mov" h265 250 -Encoder nvenc
```

The result is saved next to the input, or in `-OutputDir`, as `<name>_8K_H265.mp4`,
`<name>_8K_ProRes422HQ.mov` or `<name>_8K_ProRes422LT.mov`. An existing output is never
overwritten unless `-Force` is given. Run `Get-Help .\video-upscale-8k.ps1 -Full` for the full
parameter reference.

## Progress

While it works, a single line keeps updating with the percentage, the frames done, the speed, the
time elapsed and left, and the space the output already takes with an estimate of its final size:

```
   42.2%  9544/22620 frames  3.1 fps  0:51:20 elapsed  1:10:20 left  38.5 GB (~91.2 GB at the end)
```

With x265, the time left during the first pass already includes the second one.

## Estimates

**Time.** Each run stores its real speed in `%LOCALAPPDATA%\video-upscale-8k\speeds.json`, and the
next estimate for the same format and encoder is based on it. Until a format has been run once on
the computer, the estimate uses a rough speed measured on a PC with a GeForce RTX 2060, and is
marked `(rough)`.

**Size.** For H.265 it is the bitrate times the duration. For ProRes it is the maximum data rate
Apple publishes for each profile, scaled to 8K and to the frame rate: an upper bound, since
ProRes spends less on simple images, and dark footage such as night skies can take far less.
Before starting, the script warns if the destination drive has less free space than that.

## Why upscale at all

YouTube only has fixed quality tiers: 1080p, 1440p, 4K and 8K. A video uploaded at 5K or 6K does
not reach the 8K tier, so it is served at 4K at most. A video uploaded at 8K is processed in the
8K tier, and YouTube gives it a higher bitrate in every tier, 4K included. That shows in starry
skies and night footage, which suffer the most from compression.

The usual case is a Premiere Pro project whose transitions do not fit in the GPU memory at 8K:
the sequence is exported at the resolution it fits in, and this script does the 8K step on its
own, outside Premiere.

Upscaling adds no real detail; it only gets the video into the 8K tier. Export from the editor at
the highest resolution the source footage really has (6048 px wide for a Nikon Z6), and let this
script do the rest.

## What "highest quality" means here

**Scaling.** Lanczos, with accurate rounding and full chroma interpolation: the sharpest and
cleanest scaler in ffmpeg. It works at 10 bits and keeps the colour as it is: Rec.709, limited
range, which is what Premiere Pro exports. The output is tagged Rec.709, so players and YouTube
read the colours right. The scaling is what takes most of the time, whatever the format.

**ProRes 422 HQ and LT.** 10-bit 4:2:2, the formats Apple and Premiere use for masters and
intermediates. HQ is the mastering grade; LT takes about half the space and, for an upload to
YouTube, which re-encodes everything, the difference does not show. Audio is kept lossless: PCM
is copied and anything else becomes 24-bit PCM. YouTube accepts both, but the files are very
large, and so is the upload.

**H.265.** Main10 profile (10 bits), which avoids banding in smooth gradients such as twilight
skies, in an `.mp4` tagged `hvc1` and with `faststart`. Two encoders:

| Encoder | What it uses | Speed | Notes |
|---|---|---|---|
| `x265` | CPU, x265 `slow` preset, two passes | Very slow | The best quality per bit. `aq-mode=3` gives more bits to dark areas and `no-sao` keeps fine detail such as stars |
| `nvenc` | NVIDIA GPU (NVENC), `p7` preset, multipass | Fast | Slightly less efficient; at a high bitrate the difference does not survive YouTube's re-encoding |

The bitrate is asked for in Mbps, suggesting **250**, which is quality to spare for YouTube in 8K.
More makes the file bigger and slower to upload, with no visible gain once YouTube re-encodes it.
The peak bitrate is limited to 1.5 times the target. Audio: AAC is copied as it is; anything else
becomes AAC at 320 kbps.

NVENC needs an NVIDIA card that can encode HEVC at 8K (GeForce RTX 20 series or later). An 8K
10-bit frame takes about 100 MB on the GPU, and NVENC holds one per input buffer, one more for
every frame of look-ahead. So the look-ahead is kept short (8 frames) and the first pass of the
multipass runs at quarter resolution, which fits in a 6 GB card. If it still runs out of memory,
the script retries on its own with the leanest settings (no look-ahead, no multipass, no
B-frames), which lose very little at a high bitrate. Closing Premiere Pro and browsers before
starting leaves more GPU memory free.

## Things worth knowing

- **The aspect ratio is kept.** A video that is not 16:9 is scaled to fit inside 7680x4320, with
  a warning, rather than stretched or padded with black bars.
- **A video already at 8K or larger is rejected**, since there is nothing to upscale.
- **An input not tagged as Rec.709 gets a warning**: the output is always Rec.709, so check its
  colours.
- **Do not judge colours in VLC.** It sometimes shows ProRes darker or lighter than it is. Compare
  in Premiere with Lumetri Scopes, or check the upload on YouTube as a private video.
- **ffmpeg and ffprobe** are taken from `software-yt-dlp`, the same ones the downloaders use.
  `-Verbose` shows the full ffmpeg command and log.
