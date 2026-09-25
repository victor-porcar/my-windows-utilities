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

## After each pair

When rclone exits cleanly, a `control_sync.txt` with the timestamp is written in the destination.
Note that the next sync deletes it first, as it does not exist in the source, and then writes it
again; nothing is lost, but you will see it in the log. Add it to the exclusions file to keep the
output clean.

The script ends with a count of successes and failures, and exits with code 1 if any pair failed,
so it can be chained from another script or a scheduled task.
