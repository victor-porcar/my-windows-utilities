# my-windows-utilities

A handful of Windows scripts for downloading YouTube media and metadata, syncing folders
with rclone, keeping local copies of GitHub repositories and backing up Lightroom catalogs.

## Scripts

| Script | What it does | Details |
|---|---|---|
| `yt-video-downloader.ps1` | Downloads a video in the best available quality | [docs](docs/yt-video-downloader.md) |
| `yt-sound-downloader.ps1` | Downloads only the audio track, mp3 by default | [docs](docs/yt-sound-downloader.md) |
| `yt-channeldata-downloader.ps1` | Dumps every video of a channel as JSON metadata | [docs](docs/yt-channeldata-downloader.md) |
| `rclone_sync.ps1` | Mirrors folder pairs listed in a text file | [docs](docs/rclone_sync.md) |
| `github-repos-sync.ps1` | Clones or updates every repository of a GitHub account | [docs](docs/github-repos-sync.md) |
| `lightroom-catalog-backup.ps1` | Zips a Lightroom Classic catalog, keeping the newest N | [docs](docs/lightroom-catalog-backup.md) |

Every script also carries its own parameter reference:

```
powershell -Command "Get-Help .\yt-video-downloader.ps1 -Full"
```

And is run like this:

```
powershell -ExecutionPolicy Bypass -File yt-video-downloader.ps1 "<video url>" "C:\temp"
```

## Setup

All these scripts assume an environment variable named `GITHUB_VICTOR_PORCAR`, pointing to the
folder that holds this repository. They use it to find the executables they rely on, so that any
of them can be run, or called from a shortcut or a scheduled task, from any directory.

If it is not defined yet, create it once with `setx`, and give it the path of the folder
`my-windows-utilities` lives in:

```
setx GITHUB_VICTOR_PORCAR "D:\path\to\github-victor-porcar"
```

A script started without it stops straight away with a message saying so, rather than guessing a
location. Note that `setx` only affects consoles opened afterwards, so close the current one.

The third-party executables below are not included in this repository and have to be downloaded
into the folders named here.

### software-yt-dlp

Create `my-windows-utilities\software-yt-dlp` and place in it:

| File | Where to get it |
|---|---|
| `yt-dlp.exe` | https://github.com/yt-dlp/yt-dlp/releases |
| `ffmpeg.exe`, `ffprobe.exe`, `ffplay.exe` | https://www.gyan.dev/ffmpeg/builds/ (essentials build) |

### software-rclone

Create `my-windows-utilities\software-rclone` and place `rclone.exe` in it,
from https://rclone.org/downloads/

### GitHub CLI

Only needed by `github-repos-sync.ps1`:

```
winget install --id GitHub.cli
```

## License

The scripts in this repository are MIT licensed; see `LICENSE`.

yt-dlp, ffmpeg, rclone and GitHub CLI are separate projects under their own licenses and are not
redistributed here.
