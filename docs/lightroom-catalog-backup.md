# lightroom-catalog-backup.ps1

Zips a Lightroom Classic catalog, with a timestamp, keeping only the newest N backups.

```
powershell -ExecutionPolicy Bypass -File lightroom-catalog-backup.ps1 "D:\path\to\catalog-folder" "D:\path\to\backups" 5
```

The first argument is the catalog folder (the `.lrcat` file itself is accepted too), the second
one the backup directory, and the third one how many backups to keep. Run
`Get-Help .\lightroom-catalog-backup.ps1 -Full` for the full parameter reference.

## What goes into the zip, and why

The result is `<catalog name>_<yyyyMMdd_HHmmss>.zip`, containing:

- the **`.lrcat`** file, which is the catalog itself;
- the **`.lrcat-data`** folder, where Lightroom 11 and later keep masks and other edit data that
  no longer fits inside the catalog file. Backing up the `.lrcat` alone would silently lose them;
- the **`.lrcat-wal`** and **`.lrcat-shm`** files when they exist. The catalog is a SQLite
  database, and the write-ahead log may still hold changes that have not been folded into the
  `.lrcat` yet. Lightroom applies them when it opens the restored catalog.

**Previews are excluded by default** (`Previews.lrdata`, `Smart Previews.lrdata`): Lightroom
rebuilds them from the photos, and they are usually far bigger than everything else put together.
Add `-IncludePreviews` if you would rather not wait for that rebuild.

**Your photos are not in here.** A Lightroom catalog stores edits and references, not images. The
photos live in their own folders and need their own backup.

## It refuses to run with Lightroom open

The script stops if a `Lightroom.exe` process is running, or if a `.lock` file sits next to the
catalog (Lightroom creates one while a catalog is open). Copying a live SQLite database can
capture it mid-write and produce a backup that looks fine until the day you need it.

If you are sure Lightroom is closed and a stale `.lock` remains from a crash, delete it manually
and run again.

## Retention

Two kinds of backup are counted **separately**, each capped at the number you passed:

- the zips this script made for this catalog, counting the one just created;
- the `yyyy-MM-dd HHmm` folders that Lightroom itself creates, when its own backups are set to go
  to the same directory.

A folder only counts as a Lightroom backup when it holds nothing but `.zip` or `.lrcat` files.
Any other folder or file in that directory is left alone, so pointing the backup directory at a
folder you also use for other things is safe.
