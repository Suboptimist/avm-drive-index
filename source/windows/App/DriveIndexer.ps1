# DriveIndexer.ps1 -- the scanner behind AVM Drive Index (Windows).
#
# Keeps the private index up to date with every external storage drive
# connected to this PC. SD cards and mounted disk images (ISO/VHD) are
# intentionally ignored, matching the Mac version. For each drive it writes:
#
#   %LOCALAPPDATA%\AVM Drive Index\Drives\<Drive Name>\
#       _DRIVE INFO.txt      size, format, last connected, last used by,
#                            and a connection history
#       _FILE LIST.txt       every file with its size (used by the app for
#                            browsing and search)
#       <mirrored folders>   the drive's folder structure as real folders you
#                            can browse in File Explorer
#
# ...plus "Drives Overview.txt" as a one-glance summary.
#
# Normally run automatically by the scheduled task that
# "Install Drive Indexer.cmd" sets up, but safe to run by hand at any time.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

. (Join-Path $PSScriptRoot 'Common.ps1')

$MaxFolderDepth = 3       # how many folder levels deep to mirror
$MaxFolders     = 1000    # safety cap so a huge drive can't create endless folders
$MaxFileDepth   = 6       # how deep to record file names
$MaxFiles       = 20000   # safety cap on file names recorded per drive
$MaxHistory     = 50      # connection-history lines to keep per drive

$ErrorActionPreference = 'Continue'

# Only one scan at a time -- the watcher and the app's Rescan button can both
# land here at once.
$mutex = New-Object System.Threading.Mutex($false, 'Local\AVMDriveIndexerScan')
if (-not $mutex.WaitOne(90000)) { exit 0 }

try {

$indexRoot = Get-IndexRoot
$drivesDir = Get-DrivesDir
$stateDir  = Join-Path $indexRoot $script:StateDirName
foreach ($dir in @($indexRoot, $drivesDir, $stateDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$now      = Format-IndexDate (Get-Date)
$userName = $env:USERNAME
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'unknown' }

# ------------------------------------------------------------ scan

$connectedFolderNames = @{}
$seenStateIds = @{}

foreach ($volume in (Get-ExternalVolume)) {
    $folderName = Get-SafeFolderName $volume.Name

    # Plenty of Windows drives carry no volume label. The DRIVE field must never
    # be blank -- a record without it cannot be read back, so the drive would
    # quietly disappear from the app.
    $displayName = $volume.Name
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $folderName }

    # Pick this drive's index folder. A *different* drive that happens to share
    # a name gets "Name (2)", "Name (3)", ... -- told apart by volume serial.
    $target = Join-Path $drivesDir $folderName
    $suffix = 1
    while (Test-Path -LiteralPath (Join-Path $target $script:InfoName)) {
        $existing = Read-DriveRecord $target
        if (-not $existing -or [string]::IsNullOrWhiteSpace($existing.Serial) -or
            $existing.Serial -eq 'none' -or [string]::IsNullOrWhiteSpace($volume.Serial) -or
            $existing.Serial -eq $volume.Serial) {
            break
        }
        $suffix++
        $target = Join-Path $drivesDir ("$folderName ($suffix)")
    }
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }
    $connectedFolderNames[(Split-Path $target -Leaf)] = $true

    # New connection, or just a re-scan while it stayed plugged in?
    $stateId = $volume.Serial
    if ([string]::IsNullOrWhiteSpace($stateId)) { $stateId = $folderName }
    $stateId = Get-SafeFolderName $stateId
    $seenStateIds[$stateId] = $true
    $stateFile = Join-Path $stateDir $stateId
    $isNewConnection = -not (Test-Path -LiteralPath $stateFile)
    Set-Content -LiteralPath $stateFile -Value $now -Encoding ASCII -ErrorAction SilentlyContinue

    # Carry the connection history forward from the previous info file.
    $history = New-Object System.Collections.Generic.List[string]
    $previous = Read-DriveRecord $target
    if ($previous) {
        foreach ($entry in $previous.History) {
            $history.Add("$($entry.DateString) $($script:Dash) $($entry.User)") | Out-Null
        }
    }
    if ($isNewConnection) {
        $history.Insert(0, "$now $($script:Dash) $userName")
    }
    while ($history.Count -gt $MaxHistory) { $history.RemoveAt($history.Count - 1) }
    if ($history.Count -eq 0) { $history.Add("$now $($script:Dash) $userName") | Out-Null }

    $lastEntry = Split-HistoryLine $history[0]
    $lastConnected = $now
    $lastUser = $userName
    if ($lastEntry) {
        $lastConnected = $lastEntry.DateString
        $lastUser = $lastEntry.User
    }

    # Rebuild the mirrored folder structure: clear the old folders (files such
    # as the info file and file list are kept), then recreate what is there now.
    foreach ($old in (Get-ChildItem -LiteralPath $target -Directory -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    $unreadable = -not (Test-Path -LiteralPath $volume.RootPath)
    $folderCount = 0
    $foldersTruncated = $false
    $skipPattern = '\\(System Volume Information|\$RECYCLE\.BIN|\$Recycle\.Bin|found\.[0-9]{3})(\\|$)'

    $directories = @()
    if (-not $unreadable) {
        $directories = @(Get-ChildItem -LiteralPath $volume.RootPath -Directory -Recurse `
                            -Depth ($MaxFolderDepth - 1) -ErrorAction SilentlyContinue |
                         Where-Object { $_.FullName -notmatch $skipPattern } |
                         Sort-Object FullName)
    }

    if (-not $unreadable) {
        $prefixLength = $volume.RootPath.Length
        foreach ($dir in $directories) {
            if ($folderCount -ge $MaxFolders) { $foldersTruncated = $true; break }
            $rel = $dir.FullName.Substring($prefixLength)
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $mirror = Join-Path $target $rel
            if (-not (Test-Path -LiteralPath $mirror)) {
                New-Item -ItemType Directory -Path $mirror -Force -ErrorAction SilentlyContinue | Out-Null
            }
            $folderCount++
        }
    }

    $foldersNote = "$folderCount folders (shown down to $MaxFolderDepth levels deep, files not included)"
    if ($foldersTruncated) {
        $foldersNote = "$foldersNote $($script:Dash) drive has more; only the first $MaxFolders are shown"
    }
    if ($unreadable) {
        $foldersNote = 'could not read this drive (it may have been removed mid-scan)'
    }

    # Record every file with its size, for the app's browser and search.
    $listPath = Join-Path $target $script:FileListName
    $filesNote = ''
    if ($unreadable) {
        $filesNote = 'could not read this drive'
    } else {
        $found = @(Get-ChildItem -LiteralPath $volume.RootPath -File -Recurse `
                        -Depth ($MaxFileDepth - 1) -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch $skipPattern } |
                   Select-Object -First ($MaxFiles + 1))
        $filesTruncated = $found.Count -gt $MaxFiles
        if ($filesTruncated) { $found = $found[0..($MaxFiles - 1)] }

        $prefixLength = $volume.RootPath.Length
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($file in $found) {
            $rel = $file.FullName.Substring($prefixLength)
            $lines.Add("$($file.Length)|$rel") | Out-Null
        }
        Write-TextFileUtf8 $listPath ($lines.ToArray() -join "`r`n")

        $filesNote = "$($lines.Count) files listed (down to $MaxFileDepth levels deep)"
        if ($filesTruncated) {
            $filesNote = "$filesNote $($script:Dash) drive has more; only the first $MaxFiles are listed"
        }
    }

    $serialText = $volume.Serial
    if ([string]::IsNullOrWhiteSpace($serialText)) { $serialText = 'none' }

    $info = New-Object System.Collections.Generic.List[string]
    $info.Add((Format-InfoLine 'DRIVE' $displayName)) | Out-Null
    $info.Add((Format-InfoLine 'DRIVE LETTER' $volume.Letter)) | Out-Null
    $info.Add((Format-InfoLine 'SIZE' (Format-DriveSize $volume.SizeBytes))) | Out-Null
    $info.Add((Format-InfoLine 'FREE SPACE' (Format-FreeSpace $volume.FreeBytes $volume.SizeBytes))) | Out-Null
    $info.Add((Format-InfoLine 'FORMAT' $volume.FileSystem)) | Out-Null
    $info.Add((Format-InfoLine 'VOLUME SERIAL' $serialText)) | Out-Null
    $info.Add('') | Out-Null
    $info.Add((Format-InfoLine 'LAST CONNECTED' $lastConnected)) | Out-Null
    $info.Add((Format-InfoLine 'LAST USED BY' $lastUser)) | Out-Null
    $info.Add('') | Out-Null
    $info.Add((Format-InfoLine 'FOLDERS' $foldersNote)) | Out-Null
    $info.Add((Format-InfoLine 'FILES' $filesNote)) | Out-Null
    $info.Add('') | Out-Null
    $info.Add('The folders next to this file mirror what is on the drive.') | Out-Null
    $info.Add('They are recreated automatically each time the drive is') | Out-Null
    $info.Add("connected, so don't store anything of your own in them.") | Out-Null
    $info.Add('') | Out-Null
    $info.Add('CONNECTION HISTORY (newest first, on this PC):') | Out-Null
    foreach ($line in $history) { $info.Add($line) | Out-Null }

    Write-TextFileUtf8 (Join-Path $target $script:InfoName) (($info.ToArray() -join "`r`n") + "`r`n")
}

# Forget drives that have been unplugged, so the next connection is recorded as
# a fresh entry in the history.
foreach ($file in (Get-ChildItem -LiteralPath $stateDir -File -Force -ErrorAction SilentlyContinue)) {
    if (-not $seenStateIds.ContainsKey($file.Name)) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------ overview

$rows = New-Object System.Collections.Generic.List[object]
foreach ($record in (Get-AllDriveRecords)) {
    $mark = ''
    if ($connectedFolderNames.ContainsKey($record.IndexFolderName)) {
        $mark = "  $($script:Dash) connected right now"
    }
    $rows.Add([pscustomobject]@{
        Sort = $record.LastConnectedString
        Line = ('{0,-30} {1,-18} {2,-22} {3}{4}' -f $record.IndexFolderName,
                    $record.LastConnectedString, $record.FreeSpace, $record.LastUser, $mark)
    }) | Out-Null
}

$overview = New-Object System.Collections.Generic.List[string]
$overview.Add('EXTERNAL DRIVES -- updated automatically whenever a drive is connected') | Out-Null
$overview.Add("Last updated: $now") | Out-Null
$overview.Add('') | Out-Null
$overview.Add(('{0,-30} {1,-18} {2,-22} {3}' -f 'DRIVE', 'LAST CONNECTED', 'FREE SPACE', 'LAST USED BY')) | Out-Null
$overview.Add(('{0,-30} {1,-18} {2,-22} {3}' -f '-----', '--------------', '----------', '------------')) | Out-Null
foreach ($row in ($rows | Sort-Object -Property Sort -Descending)) {
    $overview.Add($row.Line) | Out-Null
}
$overview.Add('') | Out-Null
$overview.Add('Open the "Drives" folder to browse each drive''s folder structure,') | Out-Null
$overview.Add('or use the AVM Drive Index app for the full picture.') | Out-Null

Write-TextFileUtf8 (Join-Path $indexRoot $script:OverviewName) (($overview.ToArray() -join "`r`n") + "`r`n")

} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

exit 0
