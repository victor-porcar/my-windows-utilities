# notepadpp-clean-traces.ps1

Wipes the traces Notepad++ leaves behind about the files it has opened, so that editing a
confidential file does not leave its name, its path or its content lying around in the
configuration folder.

```
powershell -ExecutionPolicy Bypass -File notepadpp-clean-traces.ps1
```

Every parameter is optional. Run `Get-Help .\notepadpp-clean-traces.ps1 -Full` for the full
reference, and add `-WhatIf` to list what would be wiped without touching anything.

## What Notepad++ remembers, and where

All of it lives in its configuration folder, by default `%APPDATA%\Notepad++`, and stays there
after closing the file, even when the file itself was never modified:

| Trace | What it gives away |
|---|---|
| `backup\` | The **content** of every unsaved tab. With *session snapshot and periodic backup* on, which is the default, Notepad++ writes there whatever is being typed every few seconds |
| `session.xml` | The tabs of the last session: full path of each one, cursor position, and the snapshot each one belongs to |
| `session.xml.inCaseOfCorruption.bak` | The same thing again. Notepad++ 8.9 keeps a copy of the session, and of `config.xml`, next to the originals |
| `config.xml` → `<ColumnEditor>` | The last text typed in the column editor (Notepad++ 8.9 and later) |
| `config.xml` → `<History>` | The recent files menu: ten full paths |
| `config.xml` → `<FindHistory>` | Everything searched and replaced, plus the folders and filters of *Find in Files* |
| `config.xml` → `<ProjectPanels>` | The workspace files of the project panels |
| `workspace.xml` | The files of the project panels, when they are used |
| `nppLogNulContentCorruptionIssue.log` | The path of every file written, in some situations |

The script empties all of that. `config.xml` is **not** deleted, only those entries are removed
from it, so the theme, the shortcuts, the styles and every other setting survive.

The session and workspace files are matched with wildcards (`session*.xml*`, `workspace*.xml*`,
`config.xml.*bak*`), because the copies Notepad++ keeps of them have been named differently in
different versions. Tested against 8.46 and 8.9.7.

## It refuses to run with Notepad++ open

While Notepad++ is running it holds the session in memory and writes `session.xml` and
`config.xml` again when it closes, which would put the traces straight back. Close it first, or
pass `-Force` to have the script ask it to close (it waits 15 seconds; it never kills it, which
would leave the snapshots behind).

## Options

| Option | What it adds |
|---|---|
| `-WhatIf` | Lists what would be wiped, touches nothing |
| `-Overwrite` | Overwrites the bytes of each file with random data before deleting it |
| `-DisableSnapshots` | Turns off the periodic backup, so the content of unsaved tabs stops being written to disk at all |
| `-KeepSnapshots` | Keeps them on and stops reminding that they are: Notepad++ behaves as usual and everything is wiped by hand with this script |
| `-IncludeWindowsRecent` | Also removes the Windows recent-documents shortcuts pointing at those same files |
| `-Force` | Closes Notepad++ instead of refusing to run |
| `-ConfigDir` | Uses another configuration folder instead of the one found automatically |

The thorough run:

```
powershell -ExecutionPolicy Bypass -File notepadpp-clean-traces.ps1 -Force -Overwrite -DisableSnapshots -IncludeWindowsRecent
```

## The Windows traces

Windows keeps its own record of what has been opened, which Notepad++ never cleans.

With `-IncludeWindowsRecent` the script removes the shortcuts of
`%APPDATA%\Microsoft\Windows\Recent` that point at the very files Notepad++ had in its session or
in its recent files menu (those paths are read before the wiping starts, since it is Notepad++
that names them). The shortcuts of every other program are left alone.

**The taskbar jump list is not touched.** Windows keeps one file per program, named after a hash
of the path of its executable, and there is no reliable way to tell which one belongs to
Notepad++: the files that merely mention its name turn out to belong to other programs, such as
File Explorer, and deleting those would wipe *their* recent lists. Empty it by right clicking the
Notepad++ icon in the taskbar and choosing *Remove from this list* on each entry, or turn the
whole feature off in **Settings > Personalization > Start > Show recently opened items**.

## Where the configuration folder is taken from

In this order:

1. `-ConfigDir`, when it is given, and then that folder and no other.
2. The installation folder, if Notepad++ runs in **local mode** (a `doLocalConf.xml` sits next to
   `notepad++.exe`), which moves the whole configuration there.
3. The folder of the **cloud** setting (*Settings > Preferences > Cloud*), when one is set.
4. `%APPDATA%\Notepad++`.

The installed `notepad++.exe` is looked up in the registry and in the usual installation folders,
and only then in a running process. That order matters when a portable copy is open: taking the
running process first would clean **that** one and leave the installed copy, the one whose traces
are worth wiping, untouched.

**A Notepad++ from the Microsoft Store is cleaned too**, on top of the one above, and so is any
other packaged copy. They run inside an MSIX container, so what they write to `%APPDATA%` is
redirected by Windows into
`%LOCALAPPDATA%\Packages\<package>\LocalCache\Roaming\Notepad++`, where nothing else would look
for it. Every folder found is listed before anything is wiped.

The snapshots folder is read from `config.xml` as well, in case a custom backup directory is
configured in *Settings > Preferences > Backup*.

## Deleting is not the same as erasing

Deleting a file only frees its space: the content stays on the disk until something else is
written over it. That is what `-Overwrite` is for. But even with it, the content may survive
somewhere no script can reach:

- On an **SSD** (and on any pendrive or memory card) overwriting a file does not necessarily
  overwrite the cells that held it. The controller writes the new data elsewhere and the old copy
  stays until it is recycled internally.
- **Windows keeps copies of its own**: Volume Shadow Copies (System Restore), File History, the
  NTFS journal, the page file and the hibernation file, plus any backup or sync program running.

So this script makes the traces of Notepad++ disappear, which is what it is for, but it is not a
forensic wipe. For a file that must not leak at all, do not edit it in the clear on the disk:
keep it inside an encrypted container (VeraCrypt, BitLocker) and open it from there. Turning the
snapshots off with `-DisableSnapshots` helps for the same reason: the content that is never
written to disk cannot be recovered from it.
