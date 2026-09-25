# yt-sound-downloader.ps1

Downloads only the audio track of a YouTube video.

```
powershell -ExecutionPolicy Bypass -File yt-sound-downloader.ps1 "<video url>" "C:\temp"
```

The file is named `<title> [<id>].<ext>`. Run `Get-Help .\yt-sound-downloader.ps1 -Full` for the
full parameter reference.

## mp3 is the default, but it is not the highest quality

YouTube stores audio as Opus. Any mp3 is therefore a **re-encode**, and re-encoding a lossy
format into another lossy format always loses something, no matter the bitrate.

The default is still mp3, at the highest VBR setting, because it plays everywhere. When you care
about fidelity rather than compatibility, ask for the original stream instead:

```
powershell -ExecutionPolicy Bypass -File yt-sound-downloader.ps1 "<video url>" "C:\temp" best
```

`best` copies YouTube's own stream without touching it, so there is no quality loss at all and it
is also faster, because nothing has to be converted. The file will typically be `.opus` or
`.m4a`, which some older players and car stereos do not read.

Accepted formats: `mp3` (default), `best`, `m4a`, `opus`, `flac`, `wav`. Note that `flac` and
`wav` are lossless containers around an already lossy source: they waste space without recovering
anything. An invalid value is rejected before any download starts.

## Things worth knowing

- **Metadata and cover art are embedded** in the resulting file.
- **Playlists are ignored** (`--no-playlist`), so a URL with `&list=...` downloads just that one
  video. Quote the URL in the shell.
- **ffmpeg is required** for the extraction, and it is taken from `software-yt-dlp`, not from the
  `PATH`.
