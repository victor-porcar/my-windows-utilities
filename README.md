# my-windows-utilities

A handful of Windows scripts for downloading YouTube media and metadata, syncing folders
with rclone, and generating bookmark files.

## Setup

Create this environment variable, which every script uses to locate its resources:

```
setx GITHUB-VICTOR-PORCAR "D:\path\to\github-victor-porcar"
```

Then download the third-party executables below. They are not included in this repository.

### software-yt-dlp

Create `my-windows-utilities\software-yt-dlp` and place in it:

| File | Where to get it |
|---|---|
| `yt-dlp.exe` | https://github.com/yt-dlp/yt-dlp/releases |
| `ffmpeg.exe`, `ffprobe.exe`, `ffplay.exe` | https://www.gyan.dev/ffmpeg/builds/ (essentials build) |

### software-rclone

Create `my-windows-utilities\software-rclone` and place `rclone.exe` in it,
from https://rclone.org/downloads/

## Scripts

| Script | What it does |
|---|---|
| `yt-video-downloader.ps1` | Downloads a video in the best available quality |
| `yt-sound-downloader.ps1` | Downloads only the audio track (mp3 by default, `best` keeps the original stream) |
| `yt-channeldata-downloader.ps1` | Dumps every video of a channel as JSON metadata |
| `rclone_sync.ps1` | Syncs folder pairs listed in a text file, resolving `[VOLUME_LABEL]:` paths |
| `generate_bookmarks.ps1` | Converts a browser bookmarks export with Bookmark2md |

Every script carries its own help, shown with `Get-Help`:

```
powershell -Command "Get-Help .\yt-video-downloader.ps1 -Full"
```

And is run like this:

```
powershell -ExecutionPolicy Bypass -File yt-video-downloader.ps1 "<video url>" "C:\temp"
```

### rclone_sync.ps1 and -DryRun

`rclone sync` mirrors: whatever is in the destination but not in the source **is deleted**.
Add `-DryRun` to list every copy and delete it would make without touching anything, which
also skips the confirmation prompt and leaves no `control_sync.txt` behind:

```
powershell -ExecutionPolicy Bypass -File rclone_sync.ps1 "list.txt" "exclusions.txt" "args.txt" "MY BACKUP" -DryRun
```

Source and destination directories must both already exist, otherwise the pair is skipped.
This is deliberate: an unplugged drive is skipped instead of being recreated somewhere wrong.

## License

The scripts in this repository are MIT licensed; see `LICENSE`.

yt-dlp, ffmpeg and rclone are separate projects under their own licenses and are not
redistributed here.
