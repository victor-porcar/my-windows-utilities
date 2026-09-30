<#
.SYNOPSIS
    Wipes the traces Notepad++ leaves behind about the files it has opened.

.DESCRIPTION
    Notepad++ remembers, outside the files themselves, quite a lot about what has been edited.
    After opening a confidential file, these traces stay in its configuration folder (by default
    %APPDATA%\Notepad++) even though the file itself was never modified:

    - backup\            The snapshots of every unsaved tab. These hold the CONTENT, not just the
                         name: with "Enable session snapshot and periodic backup" on (the default)
                         Notepad++ writes there every few seconds whatever is being typed.
    - session.xml        The tabs of the last session: full path of each one, cursor position and
                         the path of its snapshot. Notepad++ 8.9 keeps a copy of it, and of
                         config.xml, in a .inCaseOfCorruption.bak file next to the original.
    - config.xml         <History>: the recent files menu (full paths).
                         <FindHistory>: everything searched and replaced, the filters and the
                         folders used in "Find in Files".
                         <ProjectPanels>: the workspace files of the project panels.
                         <ColumnEditor>: the last text typed in the column editor (8.9 and later).
    - workspace.xml      The files of the project panels, when they are used.
    - the log file       nppLogNulContentCorruptionIssue.log, which logs the path of every file
                         written in some situations.

    This script empties all of that, leaving Notepad++ working and keeping every other setting
    (theme, shortcuts, styles, plugins): of config.xml only the entries listed above are removed,
    the file is not deleted.

    It refuses to run while Notepad++ is open, because Notepad++ rewrites session.xml and
    config.xml when it closes and would put the traces back.

.PARAMETER ConfigDir
    Notepad++ configuration folder. By default the one in use is located automatically:
    the installation folder when Notepad++ runs in local mode (a doLocalConf.xml next to
    notepad++.exe), the folder given by the cloud setting when there is one, and otherwise
    %APPDATA%\Notepad++.

    A Notepad++ installed from the Microsoft Store is cleaned as well, on top of that one, and
    so is any other packaged copy: they run in an MSIX container, so what they write to
    %APPDATA% is redirected by Windows into the LocalCache of their package, out of sight of the
    lookup above. Passing -ConfigDir means that folder and no other.

.PARAMETER Overwrite
    Before deleting each file, overwrite its bytes with random data, so that the content cannot
    be recovered by reading the free space of the disk.

    Read the "About really erasing" section below: on an SSD this is not a guarantee.

.PARAMETER DisableSnapshots
    Also turn off "Enable session snapshot and periodic backup" in config.xml, so that Notepad++
    stops writing the content of unsaved tabs to backup\ from now on. The equivalent of
    unticking it in Settings > Preferences > Backup.

.PARAMETER KeepSnapshots
    Keep the snapshots on, and stop reminding that they are: the deliberate choice of letting
    Notepad++ behave as usual, writing unsaved tabs to disk, and wiping everything by hand with
    this script. The snapshots already written are wiped like everything else, this only silences
    the reminder. Ignored when -DisableSnapshots is given.

.PARAMETER IncludeWindowsRecent
    Also remove the trace Windows keeps on its own: a shortcut per file opened, in
    %APPDATA%\Microsoft\Windows\Recent, which feeds the recent documents of the Start menu.

    Only the shortcuts pointing at the very files Notepad++ had in its session or in its recent
    files menu are removed, so the recent documents of every other program stay as they are.
    The paths are read before the wiping starts, since it is Notepad++ itself that names them.

    The jump list of Notepad++ (right click on it in the taskbar) is NOT removed: Windows keeps
    one file per program, named after a hash of the path of its executable, and telling which
    one belongs to Notepad++ cannot be done reliably; the ones that merely mention its name
    belong to other programs, and removing them would erase their recent lists. Empty it by hand
    from the taskbar, or turn it off in Settings > Personalization > Start.

.PARAMETER Force
    Close Notepad++ if it is running, instead of refusing to do anything. It is asked to close
    normally, as if its window had been closed, and the script waits up to 15 seconds; if any tab
    has unsaved changes Notepad++ asks what to do and the script gives up unless that dialog is
    answered. It is never killed, which would leave the snapshots behind.

.EXAMPLE
    .\notepadpp-clean-traces.ps1
    Wipes the traces of the configuration folder in use.

.EXAMPLE
    .\notepadpp-clean-traces.ps1 -WhatIf
    Lists what would be wiped without touching anything.

.EXAMPLE
    .\notepadpp-clean-traces.ps1 -Overwrite -IncludeWindowsRecent -DisableSnapshots -Force
    The thorough run: closes Notepad++, overwrites every file before deleting it, removes the
    Windows jump list as well and stops the snapshots from being written from now on.

.NOTES
    About really erasing

    Deleting a file only frees its space: the content stays on the disk until something else is
    written over it, and that is what -Overwrite deals with. But even with -Overwrite the content
    may survive elsewhere, out of reach of any script:

    - On an SSD (and on any pendrive or memory card) overwriting a file does not necessarily
      overwrite the cells that held it: the controller writes the new data somewhere else and
      the old copy stays until it is recycled internally.
    - Windows may keep copies of its own: Volume Shadow Copies (System Restore), File History,
      the NTFS journal, the page file and hibernation file, and any backup or sync program.

    For a file that must not leak at all, the safe approach is not editing it in the clear on the
    disk: keep it inside an encrypted container (VeraCrypt, BitLocker) and open it from there.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigDir,

    [switch]$Overwrite,

    [switch]$DisableSnapshots,

    [switch]$KeepSnapshots,

    [switch]$IncludeWindowsRecent,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Info($text)     { Write-Host "i  $text" -ForegroundColor Cyan }
function Write-Success($text)  { Write-Host "OK $text" -ForegroundColor Green }
function Write-Warn($text)     { Write-Host "!  $text" -ForegroundColor Yellow }
function Write-ErrorMsg($text) { Write-Host "X  $text" -ForegroundColor Red }

$script:WipedFiles = 0
$script:WipedBytes = 0

# ---------------------------------------------------------------------------------------------
# Locating the configuration folder in use
# ---------------------------------------------------------------------------------------------

function Get-InstallDir {
    # The path of notepad++.exe of the copy INSTALLED in Windows: the uninstall entry of the
    # registry first, then the usual installation folders, and only as a last resort a running
    # process. A running process cannot come first: a portable copy kept in an encrypted volume
    # would then be taken for the installed one, and the traces of the installed one, which are
    # the ones worth wiping, would be left untouched
    $registryKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++"
    )
    foreach ($key in $registryKeys) {
        $location = (Get-ItemProperty -Path $key -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
        if ($location -and (Test-Path $location)) { return $location.TrimEnd("\") }
    }

    foreach ($dir in @("$env:ProgramFiles\Notepad++", "${env:ProgramFiles(x86)}\Notepad++")) {
        if (Test-Path (Join-Path $dir "notepad++.exe")) { return $dir }
    }

    $process = Get-Process -Name "notepad++" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process -and $process.Path) { return (Split-Path $process.Path -Parent) }

    return $null
}

function Get-CloudDir($appDataDir) {
    # Settings > Cloud: when a folder is set there, session.xml and config.xml live in it
    $configFile = Join-Path $appDataDir "config.xml"
    if (-not (Test-Path $configFile)) { return $null }

    try {
        $xml = [xml](Get-Content -LiteralPath $configFile -Raw)
        $node = $xml.SelectSingleNode("//GUIConfig[@name='cloudPath']")
        if ($node -and $node.InnerText.Trim() -and (Test-Path $node.InnerText.Trim())) {
            return $node.InnerText.Trim()
        }
    } catch {
        Write-Warn "config.xml could not be read to look for the cloud folder: $($_.Exception.Message)"
    }

    return $null
}

function Get-PackagedConfigDirs {
    # A Notepad++ installed from the Microsoft Store runs packaged (MSIX), and Windows redirects
    # what it writes to %APPDATA% into the LocalCache of its package, so its traces are the same
    # ones in a folder of their own that the usual lookup never sees
    $packages = Join-Path $env:LOCALAPPDATA "Packages"
    if (-not (Test-Path -LiteralPath $packages)) { return @() }

    $dirs = @()
    foreach ($package in @(Get-ChildItem -LiteralPath $packages -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($relative in @("LocalCache\Roaming\Notepad++", "LocalCache\Local\Notepad++", "LocalState\Notepad++")) {
            $candidate = Join-Path $package.FullName $relative
            # config.xml is what tells a real configuration folder from an empty leftover
            if (Test-Path -LiteralPath (Join-Path $candidate "config.xml")) { $dirs += $candidate }
        }
    }

    return $dirs
}

function Resolve-ConfigDir {
    if ($ConfigDir) {
        if (-not (Test-Path -LiteralPath $ConfigDir)) {
            throw "The configuration folder does not exist: $ConfigDir"
        }
        return (Resolve-Path -LiteralPath $ConfigDir).Path
    }

    # Local mode: a doLocalConf.xml next to notepad++.exe moves the whole configuration there
    $installDir = Get-InstallDir
    if ($installDir -and (Test-Path (Join-Path $installDir "doLocalConf.xml"))) {
        Write-Info "Notepad++ is in local mode: its configuration is in the installation folder"
        return $installDir
    }

    $appDataDir = Join-Path $env:APPDATA "Notepad++"
    if (-not (Test-Path $appDataDir)) {
        throw "The Notepad++ configuration folder was not found: $appDataDir"
    }

    $cloudDir = Get-CloudDir $appDataDir
    if ($cloudDir) {
        Write-Info "Notepad++ keeps its configuration in the cloud folder: $cloudDir"
        return $cloudDir
    }

    return $appDataDir
}

# ---------------------------------------------------------------------------------------------
# Wiping files
# ---------------------------------------------------------------------------------------------

function Clear-FileContent($path) {
    # Overwrites the bytes of the file with random data before it is deleted
    $length = (Get-Item -LiteralPath $path -Force).Length
    if ($length -le 0) { return }

    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
    try {
        $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $bufferSize = [Math]::Min($length, 1MB)
            $buffer = New-Object byte[] $bufferSize
            $written = [long]0
            while ($written -lt $length) {
                $chunk = [Math]::Min($bufferSize, $length - $written)
                $random.GetBytes($buffer)
                $stream.Write($buffer, 0, $chunk)
                $written += $chunk
            }
            $stream.Flush($true)
        } finally {
            $random.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Remove-TraceFile($path, $description) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }

    $item = Get-Item -LiteralPath $path -Force
    $size = $item.Length

    if (-not $PSCmdlet.ShouldProcess($path, "Wipe ($description)")) { return }

    # A read-only or hidden file is deleted as well, but its attributes get in the way first
    if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
        Set-ItemProperty -LiteralPath $path -Name Attributes -Value ([System.IO.FileAttributes]::Normal)
    }

    try {
        if ($Overwrite) { Clear-FileContent $path }
        Remove-Item -LiteralPath $path -Force
    } catch {
        Write-Warn "Could not be wiped: $path ($($_.Exception.Message))"
        return
    }

    $script:WipedFiles++
    $script:WipedBytes += $size
    Write-Host "   $path"
}

function Format-Size([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes bytes"
}

# ---------------------------------------------------------------------------------------------
# The traces themselves
# ---------------------------------------------------------------------------------------------

function Get-BackupDir($configDir) {
    # Settings > Preferences > Backup: the snapshots go to <config>\backup unless a custom
    # directory is set there
    $configFile = Join-Path $configDir "config.xml"
    if (Test-Path $configFile) {
        try {
            $xml = [xml](Get-Content -LiteralPath $configFile -Raw)
            $node = $xml.SelectSingleNode("//GUIConfig[@name='Backup']")
            if ($node -and $node.useCustumDir -eq "yes" -and $node.dir -and (Test-Path $node.dir)) {
                return $node.dir
            }
        } catch {
            Write-Warn "config.xml could not be read to look for the backup folder: $($_.Exception.Message)"
        }
    }

    return (Join-Path $configDir "backup")
}

function Clear-Snapshots($configDir) {
    $backupDir = Get-BackupDir $configDir
    if (-not (Test-Path -LiteralPath $backupDir)) {
        Write-Info "No snapshots folder: $backupDir"
        return
    }

    Write-Info "Snapshots of unsaved tabs (their content): $backupDir"
    $files = @(Get-ChildItem -LiteralPath $backupDir -File -Force -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        Write-Host "   (empty)"
        return
    }

    foreach ($file in $files) { Remove-TraceFile $file.FullName "snapshot" }
}

function Clear-SessionFiles($configDir) {
    Write-Info "Session: the tabs of the last time, with their full paths"
    $found = $false

    # Wildcards on purpose: besides session.xml and workspace.xml, Notepad++ keeps copies of them
    # next to the originals, and the naming has changed between versions (8.9 writes
    # session.xml.inCaseOfCorruption.bak). The copies hold the same paths as the originals
    foreach ($pattern in @("session*.xml*", "workspace*.xml*", "config.xml.*bak*")) {
        foreach ($file in @(Get-ChildItem -LiteralPath $configDir -Filter $pattern -File -Force -ErrorAction SilentlyContinue)) {
            $found = $true
            Remove-TraceFile $file.FullName "session"
        }
    }

    if (-not $found) { Write-Host "   (nothing)" }
}

function Clear-LogFile($configDir) {
    $path = Join-Path $configDir "nppLogNulContentCorruptionIssue.log"
    if (-not (Test-Path -LiteralPath $path)) { return }

    Write-Info "Log with the paths of the files written"
    Remove-TraceFile $path "log"
}

function Clear-ConfigHistory($configDir) {
    # config.xml holds the settings too, so only the entries that name files or hold what was
    # searched are removed, one by one
    $configFile = Join-Path $configDir "config.xml"
    if (-not (Test-Path -LiteralPath $configFile)) {
        Write-Warn "config.xml not found in $configDir"
        return
    }

    Write-Info "config.xml: recent files, searches and project panels"

    try {
        $xml = [xml](Get-Content -LiteralPath $configFile -Raw)
    } catch {
        Write-ErrorMsg "config.xml could not be read: $($_.Exception.Message)"
        return
    }

    $removed = @{}
    # <History><File .../> recent files; <FindHistory> holds what was searched, what it was
    # replaced with, and the folders and filters of "Find in Files"
    foreach ($xpath in @("//History/File", "//FindHistory/Find", "//FindHistory/Replace",
                         "//FindHistory/Path", "//FindHistory/Filter", "//ProjectPanels/ProjectPanel")) {
        foreach ($node in @($xml.SelectNodes($xpath))) {
            # LocalName, not Name: these nodes carry a "name" attribute holding what was
            # searched, and PowerShell would give that instead of the name of the node
            $name = $node.LocalName
            $removed[$name] = [int]$removed[$name] + 1
            [void]$node.ParentNode.RemoveChild($node)
        }
    }

    # The project panels keep the path of their workspace in an attribute, not in a child node
    foreach ($node in @($xml.SelectNodes("//ProjectPanels/ProjectPanel[@workSpaceFile]"))) {
        if ($node.workSpaceFile) {
            $node.SetAttribute("workSpaceFile", "")
            $removed["workSpaceFile"] = [int]$removed["workSpaceFile"] + 1
        }
    }

    # <ColumnEditor> (Notepad++ 8.9 and later) keeps the last text typed in the column editor
    foreach ($node in @($xml.SelectNodes("//ColumnEditor/text[@content]"))) {
        if ($node.GetAttribute("content")) {
            $node.SetAttribute("content", "")
            $removed["columnEditorText"] = [int]$removed["columnEditorText"] + 1
        }
    }

    $total = ($removed.Values | Measure-Object -Sum).Sum
    if (-not $total) {
        Write-Host "   (nothing to remove)"
        return
    }

    $detail = ($removed.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Value) $($_.Key)" }) -join ", "

    if (-not $PSCmdlet.ShouldProcess($configFile, "Remove $detail")) { return }

    try {
        $xml.Save($configFile)
    } catch {
        Write-ErrorMsg "config.xml could not be written: $($_.Exception.Message)"
        return
    }

    Write-Host "   $detail removed"
}

function Disable-Snapshots($configDir) {
    $configFile = Join-Path $configDir "config.xml"
    if (-not (Test-Path -LiteralPath $configFile)) { return }

    try {
        $xml = [xml](Get-Content -LiteralPath $configFile -Raw)
    } catch {
        Write-ErrorMsg "config.xml could not be read: $($_.Exception.Message)"
        return
    }

    $node = $xml.SelectSingleNode("//GUIConfig[@name='Backup']")
    if (-not $node) {
        Write-Warn "The backup settings were not found in config.xml"
        return
    }

    if ($node.isSnapshotMode -eq "no") {
        Write-Info "The session snapshots were already turned off"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($configFile, "Turn off the session snapshots")) { return }

    $node.SetAttribute("isSnapshotMode", "no")
    try {
        $xml.Save($configFile)
        Write-Success "Session snapshots turned off: Notepad++ will no longer write unsaved tabs to disk"
    } catch {
        Write-ErrorMsg "config.xml could not be written: $($_.Exception.Message)"
    }
}

function Show-SnapshotWarning($configDir) {
    $configFile = Join-Path $configDir "config.xml"
    if (-not (Test-Path -LiteralPath $configFile)) { return }

    try {
        $xml = [xml](Get-Content -LiteralPath $configFile -Raw)
        $node = $xml.SelectSingleNode("//GUIConfig[@name='Backup']")
        if ($node -and $node.isSnapshotMode -ne "no") {
            Write-Warn "The session snapshots are on: Notepad++ writes the content of unsaved tabs to disk every few seconds. Run this script with -DisableSnapshots to turn them off"
        }
    } catch { }
}

function Get-TracedPaths($configDir) {
    # The files Notepad++ names in its session and in its recent files menu. Read BEFORE wiping
    # anything, because they are what the Windows traces are matched against
    $paths = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    foreach ($name in @("session.xml", "workspace.xml", "config.xml")) {
        $path = Join-Path $configDir $name
        if (-not (Test-Path -LiteralPath $path)) { continue }

        try {
            $xml = [xml](Get-Content -LiteralPath $path -Raw)
        } catch {
            continue
        }

        foreach ($node in @($xml.SelectNodes("//*[@filename]"))) {
            $filename = $node.GetAttribute("filename")
            if ($filename) { [void]$paths.Add($filename) }
        }
    }

    return $paths
}

function Clear-WindowsRecent($tracedPaths) {
    # Windows keeps its own trace of what has been opened: a shortcut per file in the Recent
    # folder, which feeds the recent documents of the Start menu and the taskbar. Only the
    # shortcuts pointing at the files Notepad++ had opened are removed, so the recent documents
    # of every other program are left alone
    Write-Info "Windows recent documents pointing at those files"

    $recentDir = Join-Path $env:APPDATA "Microsoft\Windows\Recent"
    if (-not (Test-Path -LiteralPath $recentDir) -or $tracedPaths.Count -eq 0) {
        Write-Host "   (nothing)"
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $found = $false
    try {
        foreach ($link in @(Get-ChildItem -LiteralPath $recentDir -Filter "*.lnk" -File -Force -ErrorAction SilentlyContinue)) {
            try {
                $target = $shell.CreateShortcut($link.FullName).TargetPath
            } catch {
                continue
            }

            if (-not $target -or -not $tracedPaths.Contains($target)) { continue }

            $found = $true
            Remove-TraceFile $link.FullName "recent document"
        }
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }

    if (-not $found) { Write-Host "   (nothing)" }

    # The jump list of Notepad++ itself (right click on it in the taskbar) is not touched:
    # Windows keeps one file per program, named after a hash of the path of its executable, and
    # picking the right one cannot be done reliably. Empty it from the taskbar, by right clicking
    # each entry and choosing "Remove from this list", or turn the whole thing off in
    # Settings > Personalization > Start > "Show recently opened items"
    Write-Warn "The taskbar jump list of Notepad++ is not touched: empty it by right clicking its entries, or turn it off in Settings > Personalization > Start"
}

# ---------------------------------------------------------------------------------------------
# Notepad++ must not be running
# ---------------------------------------------------------------------------------------------

function Stop-NotepadPlusPlus {
    $processes = @(Get-Process -Name "notepad++" -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return $true }

    if (-not $Force) {
        Write-ErrorMsg "Notepad++ is running: close it and run this again"
        Write-Host "   While it is open it holds the session in memory and writes it back when it closes,"
        Write-Host "   so the traces would come back. Use -Force to have it closed from here."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess("Notepad++", "Close")) { return $false }

    Write-Info "Closing Notepad++"
    foreach ($process in $processes) { [void]$process.CloseMainWindow() }

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Name "notepad++" -ErrorAction SilentlyContinue)) {
            Write-Success "Notepad++ closed"
            # It writes session.xml and config.xml as it closes, and the wiping comes after
            Start-Sleep -Milliseconds 500
            return $true
        }
        Start-Sleep -Milliseconds 300
    }

    Write-ErrorMsg "Notepad++ did not close: it is probably asking what to do with unsaved changes"
    Write-Host "   Answer that dialog and run this again. It is not killed on purpose: that would"
    Write-Host "   leave the snapshots of the unsaved tabs behind."
    return $false
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

try {
    $configDirs = @(Resolve-ConfigDir)

    # An explicit -ConfigDir means that folder and no other
    if (-not $ConfigDir) {
        foreach ($packaged in @(Get-PackagedConfigDirs)) {
            if ($configDirs -notcontains $packaged) { $configDirs += $packaged }
        }
    }

    foreach ($dir in $configDirs) { Write-Info "Configuration folder: $dir" }

    if (-not (Stop-NotepadPlusPlus)) { exit 1 }

    # The paths are read first: the files naming them are wiped right after
    $tracedPaths = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    if ($IncludeWindowsRecent) {
        foreach ($dir in $configDirs) {
            foreach ($path in (Get-TracedPaths $dir)) { [void]$tracedPaths.Add($path) }
        }
    }

    foreach ($dir in $configDirs) {
        if ($configDirs.Count -gt 1) { Write-Host ""; Write-Info "--- $dir ---" }

        Clear-Snapshots $dir
        Clear-SessionFiles $dir
        Clear-ConfigHistory $dir
        Clear-LogFile $dir
        if ($DisableSnapshots) { Disable-Snapshots $dir }
        elseif (-not $KeepSnapshots) { Show-SnapshotWarning $dir }
    }

    if ($IncludeWindowsRecent) { Write-Host ""; Clear-WindowsRecent $tracedPaths }

    Write-Host ""
    if ($WhatIfPreference) {
        Write-Info "Nothing was touched: this was a -WhatIf run"
    } elseif ($script:WipedFiles -gt 0) {
        $how = if ($Overwrite) { "overwritten and deleted" } else { "deleted" }
        Write-Success "$($script:WipedFiles) files $how ($(Format-Size $script:WipedBytes)), plus the entries of config.xml"
    } else {
        Write-Success "No trace files were left; config.xml was cleaned anyway"
    }

    if (-not $Overwrite -and -not $WhatIfPreference) {
        Write-Info "Run it with -Overwrite to have the content overwritten before it is deleted (see Get-Help -Full)"
    }

    exit 0
} catch {
    Write-ErrorMsg $_.Exception.Message
    exit 1
}
