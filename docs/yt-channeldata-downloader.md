# yt-channeldata-downloader.ps1

Dumps the metadata of every video of a public YouTube channel as JSON.

```
powershell -ExecutionPolicy Bypass -File yt-channeldata-downloader.ps1 "https://www.youtube.com/@YouTube" "C:\temp" 5
```

The third argument is how many files of that channel to keep. Run
`Get-Help .\yt-channeldata-downloader.ps1 -Full` for the full parameter reference.

## What you get

A file named `YOUTUBE_CHANNEL_<channel>_<yyyyMMdd_HHmmss>.zip`, holding a JSON of the same name
with the channel data (id, handle, name, follower count) and, for every video of the Videos,
Shorts and Live tabs: id, url, tab, title, description, upload date, duration, view / like /
comment counts, language, tags, categories, chapters, thumbnail and availability.

The destination directory is printed in a banner **before anything is downloaded**, resolved to
an absolute path, so you can see where the file will land even if you passed a relative path.

## Retention

After saving the new file, the oldest ones beyond the number you asked for are deleted, counting
the one just created. This only ever touches `YOUTUBE_CHANNEL_<this channel>_*.zip` files (plus
the loose `.json` files that older versions of this script produced). Files of other channels,
and anything else in the same directory, are never touched.

## Things worth knowing

- **It takes a while on big channels.** yt-dlp is queried with `-j`, which emits one JSON line
  per video as it goes, so the script prints each video as it is processed instead of leaving you
  staring at a frozen console. Expect roughly a second per video.
- **`-Fast` trades data for speed.** It adds `--flat-playlist`, which returns the video list in
  seconds but without description, tags, likes or upload date. Useful to check that a channel
  resolves correctly before committing to the full run.
- **Only public channels.** Private or members-only content is not accessible.
- **`-Verbose`** shows the whole yt-dlp log when something does not look right.
