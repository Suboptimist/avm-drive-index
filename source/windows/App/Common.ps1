# Common.ps1 -- shared helpers for AVM Drive Index (Windows).
#
# Dot-sourced by DriveIndexer.ps1, Watcher.ps1 and DriveIndexApp.ps1.
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 assumes the legacy
# ANSI code page for .ps1 files without a byte-order mark, which would mangle
# any non-ASCII literal. Characters such as the em dash are built from their
# code point instead (see $script:Dash).

$script:AppName      = 'AVM Drive Index'
$script:InfoName     = '_DRIVE INFO.txt'
$script:FileListName = '_FILE LIST.txt'
$script:OrgFileName  = '.drive-organization.json'
$script:OverviewName = 'Drives Overview.txt'
$script:StateDirName = '.mounted'
$script:Dash         = [string][char]0x2014   # em dash, matching the Mac version

# ---------------------------------------------------------------- paths

function Get-IndexRoot {
    if ($env:DRIVE_INDEX_DIR) { return $env:DRIVE_INDEX_DIR }
    return (Join-Path $env:LOCALAPPDATA $script:AppName)
}

function Get-DrivesDir {
    return (Join-Path (Get-IndexRoot) 'Drives')
}

function Get-HostExecutable {
    # The PowerShell that is running this code, so child scans use the same one.
    foreach ($candidate in @('powershell.exe', 'pwsh.exe')) {
        $path = Join-Path $PSHOME $candidate
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return 'powershell.exe'
}

# ---------------------------------------------------------------- collections

function Remove-FromList($List, [string]$Value) {
    # Mutates $List in place. Rebuilding it instead would silently turn the
    # List into a plain array as PowerShell unrolls collections.
    for ($i = $List.Count - 1; $i -ge 0; $i--) {
        if ([string]$List[$i] -eq $Value) { $List.RemoveAt($i) }
    }
}

function ConvertTo-Array($Value) {
    # Copies any collection into a plain array. Deliberately avoids @($list):
    # on a generic List that has been seen to throw "Argument types do not
    # match" on some PowerShell builds.
    $items = New-Object System.Collections.ArrayList
    if ($null -ne $Value) {
        foreach ($item in $Value) { [void]$items.Add($item) }
    }
    return , $items.ToArray()
}

# ---------------------------------------------------------------- text files

function Read-TextFileUtf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    } catch {
        return $null
    }
}

function Write-TextFileUtf8([string]$Path, [string]$Text) {
    # UTF-8 *with* BOM so Notepad and PowerShell 5.1 both read it correctly.
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

# ---------------------------------------------------------------- formatting

function Format-DriveSize([long]$Bytes) {
    # Decimal units, matching how Windows and macOS both advertise drive sizes.
    if ($Bytes -le 0) { return 'unknown' }
    $units = @('bytes', 'KB', 'MB', 'GB', 'TB', 'PB')
    $value = [double]$Bytes
    $i = 0
    while ($value -ge 1000 -and $i -lt ($units.Count - 1)) {
        $value = $value / 1000
        $i++
    }
    if ($i -eq 0) { return "$([long]$value) bytes" }
    # One decimal, matching how the Mac version reads (e.g. "255.8 GB"), but
    # without a pointless ".0" on round numbers.
    $rounded = [math]::Round($value, 1)
    if ($rounded -eq [math]::Floor($rounded)) {
        return ('{0:N0} {1}' -f $rounded, $units[$i])
    }
    return ('{0:N1} {1}' -f $rounded, $units[$i])
}

function Format-FreeSpace([long]$FreeBytes, [long]$TotalBytes) {
    # e.g. "812.4 GB (20% free)". The percentage is of the whole drive.
    if ($FreeBytes -le 0 -or $TotalBytes -le 0) { return 'unknown' }
    $percent = [math]::Round(($FreeBytes * 100.0) / $TotalBytes)
    return ('{0} ({1}% free)' -f (Format-DriveSize $FreeBytes), $percent)
}

function Get-UsedPercent([long]$FreeBytes, [long]$TotalBytes) {
    # Whole-number percent of the drive that is occupied. Empty when unknown,
    # so the app can leave the usage bar out entirely.
    if ($FreeBytes -lt 0 -or $TotalBytes -le 0) { return '' }
    $used = [math]::Round((($TotalBytes - $FreeBytes) * 100.0) / $TotalBytes)
    if ($used -lt 0) { $used = 0 }
    if ($used -gt 100) { $used = 100 }
    return [string][int]$used
}

function Get-RelativeTimeText([datetime]$When) {
    $span = (Get-Date) - $When
    $seconds = $span.TotalSeconds
    if ($seconds -lt 0) { return 'just now' }
    if ($seconds -lt 90) { return 'just now' }
    if ($span.TotalMinutes -lt 60) {
        $n = [int][math]::Round($span.TotalMinutes)
        if ($n -eq 1) { return '1 minute ago' }
        return "$n minutes ago"
    }
    if ($span.TotalHours -lt 24) {
        $n = [int][math]::Round($span.TotalHours)
        if ($n -eq 1) { return '1 hour ago' }
        return "$n hours ago"
    }
    if ($span.TotalDays -lt 30) {
        $n = [int][math]::Floor($span.TotalDays)
        if ($n -le 1) { return 'yesterday' }
        return "$n days ago"
    }
    if ($span.TotalDays -lt 365) {
        $n = [int][math]::Floor($span.TotalDays / 30)
        if ($n -le 1) { return 'last month' }
        return "$n months ago"
    }
    $n = [int][math]::Floor($span.TotalDays / 365)
    if ($n -le 1) { return 'last year' }
    return "$n years ago"
}

function ConvertTo-IndexDate([string]$Text) {
    # Returns $null when the stamp is missing or unparseable.
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $parsed = New-Object datetime
    $ok = [datetime]::TryParseExact(
        $Text.Trim(), 'yyyy-MM-dd HH:mm',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
    if ($ok) { return $parsed }
    return $null
}

function Format-IndexDate([datetime]$When) {
    return $When.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-InfoLine([string]$Label, [string]$Value) {
    return ($Label + ':').PadRight(17) + $Value
}

# ---------------------------------------------------------------- info files

function Get-InfoField([string[]]$Lines, [string]$Label) {
    $prefix = $Label + ':'
    foreach ($line in $Lines) {
        if ($line.StartsWith($prefix)) {
            return $line.Substring($prefix.Length).Trim()
        }
    }
    return ''
}

function Split-HistoryLine([string]$Line) {
    # "2026-08-03 14:22 <em dash> andreas" -> @{ DateString; User }
    # Tolerates a plain hyphen separator as well.
    $idx = $Line.IndexOf($script:Dash)
    $sepLength = 1
    if ($idx -lt 0) {
        $idx = $Line.IndexOf(' - ')
        $sepLength = 3
    }
    if ($idx -lt 0) { return $null }
    $stamp = $Line.Substring(0, $idx).Trim()
    $user = $Line.Substring($idx + $sepLength).Trim()
    if ([string]::IsNullOrWhiteSpace($stamp)) { return $null }
    return [pscustomobject]@{ DateString = $stamp; User = $user }
}

function Read-DriveRecord([string]$FolderPath) {
    $infoPath = Join-Path $FolderPath $script:InfoName
    $text = Read-TextFileUtf8 $infoPath
    if (-not $text) { return $null }

    $lines = $text -split "`r?`n"
    $name = Get-InfoField $lines 'DRIVE'
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }

    $history = New-Object System.Collections.Generic.List[object]
    $inHistory = $false
    foreach ($line in $lines) {
        if ($line.StartsWith('CONNECTION HISTORY')) { $inHistory = $true; continue }
        if (-not $inHistory) { continue }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $entry = Split-HistoryLine $line
        if (-not $entry) { continue }
        $history.Add([pscustomobject]@{
            DateString = $entry.DateString
            Date       = ConvertTo-IndexDate $entry.DateString
            User       = $entry.User
        }) | Out-Null
    }

    $notes = @(Get-InfoField $lines 'FOLDERS'; Get-InfoField $lines 'FILES') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $lastConnectedString = Get-InfoField $lines 'LAST CONNECTED'

    return [pscustomobject]@{
        IndexFolderName     = Split-Path $FolderPath -Leaf
        Name                = $name
        Letter              = Get-InfoField $lines 'DRIVE LETTER'
        Size                = Get-InfoField $lines 'SIZE'
        FreeSpace           = Get-InfoField $lines 'FREE SPACE'
        UsedPercent         = Get-InfoField $lines 'USED PERCENT'
        Format              = Get-InfoField $lines 'FORMAT'
        Serial              = Get-InfoField $lines 'VOLUME SERIAL'
        LastConnectedString = $lastConnectedString
        LastConnected       = ConvertTo-IndexDate $lastConnectedString
        LastUser            = Get-InfoField $lines 'LAST USED BY'
        ContentsNote        = ($notes -join ('  ' + $script:Dash + '  '))
        History             = $history.ToArray()
        FolderPath          = $FolderPath
        IsConnected         = $false     # filled in by the caller
        VolumePath          = $null      # filled in by the caller
    }
}

function Get-AllDriveRecords {
    $drivesDir = Get-DrivesDir
    $records = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $drivesDir)) { return $records.ToArray() }

    foreach ($dir in (Get-ChildItem -LiteralPath $drivesDir -Directory -ErrorAction SilentlyContinue)) {
        $record = Read-DriveRecord $dir.FullName
        if ($record) { $records.Add($record) | Out-Null }
    }
    return $records.ToArray()
}

# ---------------------------------------------------------------- content tree

function New-ContentNode([string]$Name, [string]$RelPath, [bool]$IsFile, [string]$SizeLabel) {
    return [pscustomobject]@{
        Name      = $Name
        RelPath   = $RelPath
        IsFile    = $IsFile
        SizeLabel = $SizeLabel
        Children  = (New-Object System.Collections.Generic.List[object])
    }
}

function Get-DriveContentTree([string]$FolderPath) {
    # Folders come from the mirrored (empty) folder structure, files from
    # "_FILE LIST.txt" -- one "size_in_bytes|relative/path" per line.
    $root = New-ContentNode '' '' $false $null
    $dirIndex = @{ '' = $root }

    function Get-Node([string]$RelPath) {
        if ($dirIndex.ContainsKey($RelPath)) { return $dirIndex[$RelPath] }
        $parentRel = ''
        $name = $RelPath
        $slash = $RelPath.LastIndexOf('\')
        if ($slash -ge 0) {
            $parentRel = $RelPath.Substring(0, $slash)
            $name = $RelPath.Substring($slash + 1)
        }
        $parent = Get-Node $parentRel
        $node = New-ContentNode $name $RelPath $false $null
        $parent.Children.Add($node) | Out-Null
        $dirIndex[$RelPath] = $node
        return $node
    }

    if (Test-Path -LiteralPath $FolderPath) {
        $prefixLength = $FolderPath.TrimEnd('\', '/').Length + 1
        foreach ($dir in (Get-ChildItem -LiteralPath $FolderPath -Directory -Recurse -ErrorAction SilentlyContinue)) {
            $rel = $dir.FullName.Substring($prefixLength).Replace('/', '\')
            Get-Node $rel | Out-Null
        }
    }

    $listPath = Join-Path $FolderPath $script:FileListName
    $text = Read-TextFileUtf8 $listPath
    if ($text) {
        foreach ($line in ($text -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $bar = $line.IndexOf('|')
            if ($bar -lt 1) { continue }
            $bytes = 0L
            [void][long]::TryParse($line.Substring(0, $bar), [ref]$bytes)
            $rel = $line.Substring($bar + 1).Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $parentRel = ''
            $name = $rel
            $slash = $rel.LastIndexOf('\')
            if ($slash -ge 0) {
                $parentRel = $rel.Substring(0, $slash)
                $name = $rel.Substring($slash + 1)
            }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $parent = Get-Node $parentRel
            $parent.Children.Add((New-ContentNode $name $rel $true (Format-DriveSize $bytes))) | Out-Null
        }
    }

    Sort-ContentNode $root
    return $root
}

function Sort-ContentNode($Node) {
    # Folders first, then files, each alphabetical -- matching the Mac app.
    if ($Node.Children.Count -eq 0) { return }
    $sorted = @($Node.Children | Sort-Object @{ Expression = { $_.IsFile } }, @{ Expression = { $_.Name } })
    $Node.Children.Clear()
    foreach ($child in $sorted) {
        $Node.Children.Add($child) | Out-Null
        Sort-ContentNode $child
    }
}

# ---------------------------------------------------------------- drive discovery

function Get-SafeFolderName([string]$Name) {
    $clean = $Name
    # Spell the Windows-invalid set out rather than relying on
    # GetInvalidFileNameChars(), so the result is the same wherever this runs.
    foreach ($ch in @('<', '>', ':', '"', '/', '\', '|', '?', '*')) {
        $clean = $clean.Replace($ch, '')
    }
    foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) {
        $clean = $clean.Replace([string]$ch, '')
    }
    $clean = $clean.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'Removable Disk' }
    return $clean
}

function Get-ExternalVolume {
    # Emits one object per external storage volume that currently has a drive
    # letter. Deliberately excludes internal disks, optical drives, network
    # drives, mounted ISO/VHD images, and SD/memory cards -- matching the
    # behaviour of the Mac version.
    #
    # Both the scanner and the app call this, so "connected right now" is always
    # answered by the system itself rather than by any cached state.
    $diskByNumber = @{}
    try {
        foreach ($disk in (Get-Disk -ErrorAction Stop)) {
            $diskByNumber[[int]$disk.Number] = $disk
        }
    } catch {
        # Storage module unavailable -- fall back to Win32_DiskDrive only.
    }

    foreach ($logical in (Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
        # DriveType 2 = removable media, 3 = local disk (most external HDDs and
        # SSDs report as 3). 4 = network, 5 = optical: both skipped.
        if ($logical.DriveType -ne 2 -and $logical.DriveType -ne 3) { continue }
        if ($logical.DeviceID -eq $env:SystemDrive) { continue }
        if (-not $logical.FileSystem) { continue }   # no media inserted

        # Walk logical disk -> partition -> physical disk.
        $diskDrive = $null
        try {
            foreach ($partition in @(Get-CimAssociatedInstance -InputObject $logical `
                        -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue)) {
                $found = @(Get-CimAssociatedInstance -InputObject $partition `
                            -ResultClassName Win32_DiskDrive -ErrorAction SilentlyContinue)
                if ($found.Count -gt 0) { $diskDrive = $found[0]; break }
            }
        } catch { }

        $disk = $null
        if ($diskDrive -and $diskByNumber.ContainsKey([int]$diskDrive.Index)) {
            $disk = $diskByNumber[[int]$diskDrive.Index]
        }

        # Never index the disk Windows booted from.
        if ($disk -and ($disk.IsBoot -or $disk.IsSystem)) { continue }

        $busType = ''
        if ($disk) { $busType = [string]$disk.BusType }
        $interfaceType = ''
        if ($diskDrive) { $interfaceType = [string]$diskDrive.InterfaceType }

        # Mounted ISO or VHD images look like ordinary drives otherwise.
        if ($busType -eq 'File Backed Virtual') { continue }

        $isExternal = $false
        if ($busType -eq 'USB' -or $busType -eq '1394' -or $busType -eq 'SD' -or $busType -eq 'MMC') {
            $isExternal = $true
        } elseif ($interfaceType -eq 'USB' -or $interfaceType -eq '1394') {
            $isExternal = $true
        } elseif (-not $diskDrive -and $logical.DriveType -eq 2) {
            # Couldn't identify the hardware; removable media is external.
            $isExternal = $true
        }
        if (-not $isExternal) { continue }

        # Skip SD cards and other memory cards, including ones behind a USB card
        # reader (which report themselves as plain USB storage).
        if ($busType -eq 'SD' -or $busType -eq 'MMC') { continue }
        $modelText = ''
        if ($diskDrive) { $modelText = "$($diskDrive.Model) $($diskDrive.Caption) $($diskDrive.PNPDeviceID)" }
        if ($disk) { $modelText = "$modelText $($disk.FriendlyName)" }
        if ($modelText -match '(?i)(\bSD\b|SDHC|SDXC|\bMMC\b|Multi[-_ ]?Card|Card[-_ ]?Reader|CFast|CompactFlash|xD[-_ ]Picture|Memory[-_ ]?Card)') {
            continue
        }

        $label = [string]$logical.VolumeName
        if ([string]::IsNullOrWhiteSpace($label)) {
            if ($disk -and $disk.FriendlyName) { $label = [string]$disk.FriendlyName }
            elseif ($diskDrive -and $diskDrive.Model) { $label = [string]$diskDrive.Model }
        }
        $label = $label.Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { $label = 'Removable Disk' }

        [pscustomobject]@{
            Letter     = [string]$logical.DeviceID          # e.g. "E:"
            RootPath   = ([string]$logical.DeviceID) + '\'
            Name       = $label
            Serial     = [string]$logical.VolumeSerialNumber
            FileSystem = [string]$logical.FileSystem
            SizeBytes  = [long]$logical.Size
            FreeBytes  = [long]$logical.FreeSpace
        }
    }
}

function Get-VolumeFingerprint {
    # Cheap "what is mounted" signature, used to notice drives coming and going
    # without running a full WMI query on a timer.
    $parts = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            if (-not $drive.IsReady) { continue }
            # Only disk-like volumes. Inserting a CD or a network share
            # reconnecting must not look like a drive being plugged in.
            $type = [string]$drive.DriveType
            if ($type -ne 'Removable' -and $type -ne 'Fixed') { continue }
            $parts.Add($drive.Name) | Out-Null
        }
    } catch { }
    return ($parts.ToArray() -join '|')
}

# ---------------------------------------------------------------- search

$script:FileListCache = @{}

function Get-CachedFileList([string]$FolderPath) {
    $listPath = Join-Path $FolderPath $script:FileListName
    $item = Get-Item -LiteralPath $listPath -ErrorAction SilentlyContinue
    if (-not $item) { return @() }
    $stamp = $item.LastWriteTimeUtc.Ticks
    if ($script:FileListCache.ContainsKey($FolderPath)) {
        $cached = $script:FileListCache[$FolderPath]
        if ($cached.Stamp -eq $stamp) { return $cached.Lines }
    }
    $text = Read-TextFileUtf8 $listPath
    $lines = @()
    if ($text) { $lines = @($text -split "`r?`n" | Where-Object { $_ }) }
    $script:FileListCache[$FolderPath] = [pscustomobject]@{ Stamp = $stamp; Lines = $lines }
    return $lines
}

function Clear-FileListCache([string]$FolderPath) {
    if ($FolderPath) { $script:FileListCache.Remove($FolderPath) | Out-Null }
    else { $script:FileListCache.Clear() }
}

function Find-IndexMatch($Records, [string]$Query, [int]$Limit = 400) {
    # Searches drive names, folder names and file names across every indexed
    # drive. Folder names come from the mirrored folders, file names from each
    # drive's recorded file list.
    $needle = $Query.Trim().ToLowerInvariant()
    $hits = New-Object System.Collections.Generic.List[object]
    if (-not $needle) { return $hits.ToArray() }

    foreach ($record in $Records) {
        if ($hits.Count -ge $Limit) { break }

        if ($record.IndexFolderName.ToLowerInvariant().Contains($needle)) {
            $hits.Add([pscustomobject]@{
                DriveName = $record.IndexFolderName
                Name      = $record.IndexFolderName
                Path      = ''
                Kind      = 'drive'
                SizeLabel = $record.Size
            }) | Out-Null
        }

        $prefixLength = $record.FolderPath.TrimEnd('\', '/').Length + 1
        foreach ($dir in (Get-ChildItem -LiteralPath $record.FolderPath -Directory -Recurse -ErrorAction SilentlyContinue)) {
            if ($hits.Count -ge $Limit) { break }
            if (-not $dir.Name.ToLowerInvariant().Contains($needle)) { continue }
            $hits.Add([pscustomobject]@{
                DriveName = $record.IndexFolderName
                Name      = $dir.Name
                Path      = $dir.FullName.Substring($prefixLength).Replace('/', '\')
                Kind      = 'folder'
                SizeLabel = $null
            }) | Out-Null
        }

        foreach ($line in (Get-CachedFileList $record.FolderPath)) {
            if ($hits.Count -ge $Limit) { break }
            $bar = $line.IndexOf('|')
            if ($bar -lt 1) { continue }
            $rel = $line.Substring($bar + 1)
            $slash = $rel.LastIndexOf('\')
            $fileName = $rel
            if ($slash -ge 0) { $fileName = $rel.Substring($slash + 1) }
            if (-not $fileName.ToLowerInvariant().Contains($needle)) { continue }
            $bytes = 0L
            [void][long]::TryParse($line.Substring(0, $bar), [ref]$bytes)
            $hits.Add([pscustomobject]@{
                DriveName = $record.IndexFolderName
                Name      = $fileName
                Path      = $rel
                Kind      = 'file'
                SizeLabel = (Format-DriveSize $bytes)
            }) | Out-Null
        }
    }
    return $hits.ToArray()
}

# ---------------------------------------------------------------- organization

function Get-Organization {
    $path = Join-Path (Get-IndexRoot) $script:OrgFileName
    $ungrouped = New-Object System.Collections.Generic.List[object]
    $groups = New-Object System.Collections.Generic.List[object]

    $text = Read-TextFileUtf8 $path
    if ($text) {
        try {
            $parsed = $text | ConvertFrom-Json
            foreach ($name in @($parsed.ungrouped)) {
                if ($name) { $ungrouped.Add([string]$name) | Out-Null }
            }
            foreach ($group in @($parsed.groups)) {
                if (-not $group) { continue }
                $names = New-Object System.Collections.Generic.List[object]
                foreach ($name in @($group.driveNames)) {
                    if ($name) { $names.Add([string]$name) | Out-Null }
                }
                $id = [string]$group.id
                if ([string]::IsNullOrWhiteSpace($id)) { $id = [guid]::NewGuid().ToString() }
                $groups.Add([pscustomobject]@{
                    id         = $id
                    name       = [string]$group.name
                    driveNames = $names
                }) | Out-Null
            }
        } catch {
            # A corrupt file should not stop the app -- start from a clean slate.
        }
    }

    return [pscustomobject]@{ ungrouped = $ungrouped; groups = $groups }
}

function Save-Organization($Organization) {
    $root = Get-IndexRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    $groupPayload = New-Object System.Collections.ArrayList
    foreach ($group in $Organization.groups) {
        [void]$groupPayload.Add([pscustomobject]@{
            id         = $group.id
            name       = $group.name
            driveNames = (ConvertTo-Array $group.driveNames)
        })
    }
    $payload = [pscustomobject]@{
        ungrouped = (ConvertTo-Array $Organization.ungrouped)
        groups    = $groupPayload.ToArray()
    }
    $json = $payload | ConvertTo-Json -Depth 6
    Write-TextFileUtf8 (Join-Path $root $script:OrgFileName) $json
}

function Sync-Organization($Organization, $Records) {
    # Drops drives that are no longer indexed and files new arrivals at the
    # top of the main list. Returns $true when something changed.
    #
    # "Still indexed" means the drive's folder exists OR it parsed into a
    # record. The folder check matters: the scanner rewrites _DRIVE INFO.txt in
    # place, so a read landing mid-write yields no record for a drive that is
    # perfectly fine. Pruning on that alone would throw the drive out of the
    # folder the user filed it in, and save that loss to disk.
    $known = @{}
    foreach ($dir in (Get-ChildItem -LiteralPath (Get-DrivesDir) -Directory -ErrorAction SilentlyContinue)) {
        $known[$dir.Name] = $true
    }
    foreach ($record in $Records) { $known[$record.IndexFolderName] = $true }
    $changed = $false

    $keep = New-Object System.Collections.Generic.List[object]
    foreach ($name in $Organization.ungrouped) {
        if ($known.ContainsKey($name)) { $keep.Add($name) | Out-Null } else { $changed = $true }
    }
    $Organization.ungrouped = $keep

    foreach ($group in $Organization.groups) {
        $keepGroup = New-Object System.Collections.Generic.List[object]
        foreach ($name in $group.driveNames) {
            if ($known.ContainsKey($name)) { $keepGroup.Add($name) | Out-Null } else { $changed = $true }
        }
        $group.driveNames = $keepGroup
    }

    $placed = @{}
    foreach ($name in $Organization.ungrouped) { $placed[$name] = $true }
    foreach ($group in $Organization.groups) {
        foreach ($name in $group.driveNames) { $placed[$name] = $true }
    }

    # $Records arrives newest-first; inserting in reverse keeps that order.
    $ordered = ConvertTo-Array $Records
    for ($i = $ordered.Count - 1; $i -ge 0; $i--) {
        $name = $ordered[$i].IndexFolderName
        if (-not $placed.ContainsKey($name)) {
            $Organization.ungrouped.Insert(0, $name)
            $placed[$name] = $true
            $changed = $true
        }
    }

    return $changed
}
