# rclone_sync.ps1

Mirrors folder pairs listed in a text file, using rclone.

```
powershell -ExecutionPolicy Bypass -File rclone_sync.ps1 "list.txt" "exclusions.txt" "args.txt" "MY BACKUP"
```

Run `Get-Help .\rclone_sync.ps1 -Full` for the full parameter reference.

## Read this first: sync mirrors, it does not merge

`rclone sync` makes the destination **identical** to the source. Anything in the destination that
is not in the source **is deleted**. That is what you want for a backup, and it is also why a
wrong source can empty a destination.

Use `-DryRun` whenever you are not completely sure. It lists every copy and every delete it would
make without touching a single file, skips the confirmation prompt (there is nothing to confirm)
and writes no `control_sync.txt`:

```
powershell -ExecutionPolicy Bypass -File rclone_sync.ps1 "list.txt" "exclusions.txt" "args.txt" "MY BACKUP" -DryRun
```

## The sync list

One `source,destination` pair per line. Blank lines and lines starting with `#` are ignored.
Paths can be literal or use either of two substitutions:

```
# literal paths
D:\data\PHOTOS,T:\BACKUP_PHOTOS

# [VOLUME_LABEL]: resolved to whatever drive letter Windows gave it today
D:\data\VIDEO,[BACKUP_DRIVE]:\BACKUP_VIDEO

# %VARIABLE% replaced with an environment variable
%DATA_ROOT%\PHOTOS,[BACKUP_DRIVE]:\BACKUP\PHOTOS
```

### `[VOLUME_LABEL]:`

Volume labels exist precisely because Windows hands out drive letters in whatever order devices
show up: an external disk that is `T:` today may be `U:` tomorrow, and a literal path would then
point at the wrong disk. Only valid at the start of the path, since it replaces the drive.

**Caveat:** if two mounted volumes share the same label, the last one found wins, and the sync
would silently go to the wrong disk. Keep backup drive labels unique.

### `%VARIABLE%`

The usual Windows notation, so a list can be shared between machines where the data sits in
different places. Define the variable once:

```
setx DATA_ROOT "D:\data"
```

and `%DATA_ROOT%\PHOTOS` becomes `D:\data\PHOTOS`. Unlike the volume label, it works **anywhere**
in the path, not only at the start (`D:\data\%PROJECT%\raw` is fine), and several can appear in
the same path. Both forms combine freely, as in the example above. A trailing backslash in the
variable's value is dropped, so `D:\data\` and `D:\data` behave the same.

Remember that `setx` only affects consoles opened **afterwards**.

### When a substitution cannot be resolved

The pair is reported and skipped:

```
ERROR: VOLUME NOT FOUND: BACKUP_DRIVE
ERROR: ENVIRONMENT VARIABLE NOT DEFINED: DATA_ROOT
```

An undefined variable is never expanded to an empty string. That matters: `%DATA_ROOT%\BACKUP`
silently becoming `\BACKUP` would point at the root of the current drive, and as the source of a
mirror that could wipe the destination.

## Why a pair can be skipped

Both directories must already exist, otherwise the pair is reported and skipped. This is
deliberate and it is the main safety net: when a backup drive is not plugged in, the expected
folder does not exist, so the job is skipped instead of recreating an empty backup structure
somewhere wrong. Plain `rclone` would happily create the destination folder.

The practical consequence: **on a brand new or reformatted drive you must create the destination
folders by hand once**, or every pair will be skipped.

A pair is skipped as well when the source does not exist, which protects against the worst case
of all: an empty source mirrored onto a full destination.

## Free space

Before asking for confirmation, the script lists every local drive the valid pairs touch, with
its volume label, free space, total size and percentage free. A drive under 10% free is shown in
red. Network paths (`\\server\share`) have no drive letter and are not listed.

```
💾 FREE SPACE

C:\ [OS]  126.7 GB free of 458.5 GB (28%)
T:\ [BACKUP_DRIVE]  542.6 GB free of 1,907.7 GB (28%)
```

## Space check

Right after that, the script asks:

```
Check whether the sync fits in the destination drives? (y/n)
```

Anything but `y` skips the check and goes straight to the usual confirmation. With `y`, every pair
is run once as a dry run to learn exactly which files would be copied and their size. The totals
are added up per destination drive and compared with its free space:

```
📦 SPACE CHECK

✅ T:\ [BACKUP_DRIVE]  12.3 GB to copy, 542.6 GB free

✅ ENOUGH SPACE - THE SYNC CAN BE DONE
```

If any drive falls short, it is shown in red with how much is missing, and the script **stops
without asking**, exiting with code 1:

```
❌ T:\ [BACKUP_DRIVE]  600.0 GB to copy, only 542.6 GB free (missing 57.4 GB)

⛔ NOT ENOUGH SPACE - THE SYNC CANNOT BE DONE
```

With `-DryRun` the same message is shown, but the run goes on, since it changes nothing and its
listing helps to see what is taking the space.

The check is deliberately conservative: what the sync will delete is **not** subtracted, because
rclone deletes only after all the copies of a pair are done, so the copies have to fit first. A
modified file counts with its full new size. If the space for a pair cannot be calculated (rclone
fails, the destination is a network path, the drive is not ready) a yellow warning says so and the
script continues.

Scanning both sides takes time on big folders and network drives, and the sync itself scans them
again afterwards. That is why it is optional: answer `n` when you know there is room to spare.

## After each pair

When rclone exits cleanly, a `control_sync.txt` with the timestamp is written in the destination.
Note that the next sync deletes it first, as it does not exist in the source, and then writes it
again; nothing is lost, but you will see it in the log. Add it to the exclusions file to keep the
output clean.

The script ends with a count of successes and failures, and exits with code 1 if any pair failed,
so it can be chained from another script or a scheduled task.
