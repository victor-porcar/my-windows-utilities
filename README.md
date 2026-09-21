# my-windows-utilities

A handful of Windows scripts for downloading YouTube media and metadata, syncing folders
with rclone, keeping local copies of GitHub repositories and backing up Lightroom catalogs.

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
| `yt-channeldata-downloader.ps1` | Dumps every video of a channel as JSON metadata, keeping only the newest N files |
| `rclone_sync.ps1` | Syncs folder pairs listed in a text file, resolving `[VOLUME_LABEL]:` paths |
| `github-repos-sync.ps1` | Clones or updates every repository of a GitHub account into one directory |
| `lightroom-catalog-backup.ps1` | Zips a Lightroom Classic catalog (`.lrcat` plus `.lrcat-data`) with a timestamp |

Every script carries its own help, shown with `Get-Help`:

```
powershell -Command "Get-Help .\yt-video-downloader.ps1 -Full"
```

And is run like this:

```
powershell -ExecutionPolicy Bypass -File yt-video-downloader.ps1 "<video url>" "C:\temp"
```

### yt-channeldata-downloader.ps1

```
powershell -ExecutionPolicy Bypass -File yt-channeldata-downloader.ps1 "https://www.youtube.com/@YouTube" "C:\temp" 5
```

Saves `YOUTUBE_CHANNEL_<channel>_<yyyyMMdd>.json` and then deletes the oldest files of that
channel so that only the given number remain (5 here), counting the new one. Files of other
channels and any other file in the directory are never touched. Running it twice on the same
day overwrites that day's file.

### rclone_sync.ps1 and -DryRun

`rclone sync` mirrors: whatever is in the destination but not in the source **is deleted**.
Add `-DryRun` to list every copy and delete it would make without touching anything, which
also skips the confirmation prompt and leaves no `control_sync.txt` behind:

```
powershell -ExecutionPolicy Bypass -File rclone_sync.ps1 "list.txt" "exclusions.txt" "args.txt" "MY BACKUP" -DryRun
```

Source and destination directories must both already exist, otherwise the pair is skipped.
This is deliberate: an unplugged drive is skipped instead of being recreated somewhere wrong.

### github-repos-sync.ps1

Needs GitHub CLI, authenticated once with `gh auth login`:

```
winget install --id GitHub.cli
```

Then, to bring every repository of the account into one directory:

```
powershell -ExecutionPolicy Bypass -File github-repos-sync.ps1 "D:\path\to\github"
```

Missing repositories are cloned, existing ones are fast-forwarded, and any repository with
uncommitted changes is reported and left alone. Pass `-Account <user-or-org>` for someone
else's repositories.

### lightroom-catalog-backup.ps1

```
powershell -ExecutionPolicy Bypass -File lightroom-catalog-backup.ps1 "D:\LR_CATALOG\v_catalog" "D:\AAA"
```

The first argument is the catalog folder, which must hold a single `.lrcat` file (the `.lrcat`
file itself is accepted too); the second one is the directory for the backup.

Creates `<catalog name>_<yyyyMMdd_HHmmss>.zip` with the catalog and its `.lrcat-data` folder,
where Lightroom 11 and later keep the masks. The `.lrcat-wal` / `.lrcat-shm` files go in too when
present: the `-wal` file may hold changes that are not in the
`.lrcat` yet. Previews are left out because Lightroom regenerates them; add `-IncludePreviews`
to keep them too. It refuses to run while Lightroom is running or the catalog has a `.lock` file
next to it (Lightroom creates it while the catalog is open). Photos are not part
of the catalog and are not backed up.

## License

The scripts in this repository are MIT licensed; see `LICENSE`.

yt-dlp, ffmpeg and rclone are separate projects under their own licenses and are not
redistributed here.
