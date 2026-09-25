# yt-video-downloader.ps1

Downloads a single YouTube video in the best quality available.

```
powershell -ExecutionPolicy Bypass -File yt-video-downloader.ps1 "<video url>" "C:\temp"
```

The file is named `<title> [<id>].mp4`. Run `Get-Help .\yt-video-downloader.ps1 -Full` for the
full parameter reference.

## What "best quality" means here

YouTube serves video and audio as separate streams, and the highest quality ones are never
bundled together in a single ready-made file. The script asks yt-dlp for `bv*+ba/b`: the best
video stream plus the best audio stream, merged with ffmpeg into one `.mp4`. The `/b` at the end
is the fallback to the best single pre-merged stream, used when a video has no separate streams.

This means **ffmpeg is not optional**: without it there is nothing to merge the two downloads
with. Both executables are taken from `software-yt-dlp`, and the script passes
`--ffmpeg-location` explicitly, so it never depends on whatever ffmpeg may be in the `PATH`.

Metadata and the thumbnail are embedded in the resulting file.

## Things worth knowing

- **Playlists are ignored on purpose.** A URL copied from a playlist carries `&list=...`, which
  would otherwise make yt-dlp download the whole playlist. `--no-playlist` keeps it to the one
  video you asked for. Remember to quote the URL in the shell, or `&` will break the command.
- **The output directory is created if missing**, and the final path is printed with its size.
- **Expect the resolution the video actually has.** "Best available" is not "4K": an old video
  simply has no high quality stream to download.
