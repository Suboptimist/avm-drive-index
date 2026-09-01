# Update.ps1 -- checks GitHub Releases for a newer AVM Drive Index and
# installs it over the current copy.
#
# Quiet by design: the automatic check never interrupts unless an update
# actually exists, and every failure path degrades to "no update offered"
# rather than an error the user has to dismiss.
#
# A running .ps1 cannot reliably replace the folder it is executing from, so
# the install writes a small swap script to the temp folder, launches it, and
# quits. The swap script waits for this process to end, copies the new files
# over the installed copy, and starts the app again.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

function Test-VersionNewer([string]$Candidate, [string]$Current) {
    # Dotted version numbers compared the way people expect: 1.10 is newer than
    # 1.9, and "1.6" and "1.6.0" are the same version. Anything unparseable
    # counts as 0, so a malformed tag can never offer a bogus update.
    function Split-Version([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return @(0) }
        $trimmed = $Text.Trim()
        if ($trimmed.StartsWith('v') -or $trimmed.StartsWith('V')) {
            $trimmed = $trimmed.Substring(1)
        }
        $out = New-Object System.Collections.ArrayList
        foreach ($piece in $trimmed.Split('.')) {
            $digits = ''
            foreach ($ch in $piece.ToCharArray()) {
                if ([char]::IsDigit($ch)) { $digits += $ch } else { break }
            }
            $value = 0
            if ($digits -ne '') { [void][int]::TryParse($digits, [ref]$value) }
            [void]$out.Add($value)
        }
        if ($out.Count -eq 0) { return @(0) }
        return $out.ToArray()
    }

    $a = Split-Version $Candidate
    $b = Split-Version $Current
    $count = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $x = 0; if ($i -lt $a.Count) { $x = $a[$i] }
        $y = 0; if ($i -lt $b.Count) { $y = $b[$i] }
        if ($x -ne $y) { return ($x -gt $y) }
    }
    return $false
}

function Get-AvailableUpdate([int]$TimeoutSec = 20) {
    # Returns a hashtable with Version and Url when something newer exists,
    # otherwise $null. Never throws.
    try {
        # Windows PowerShell 5.1 can default to TLS 1.0, which github.com
        # refuses outright.
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.SecurityProtocolType]::Tls12
        $headers = @{
            'User-Agent' = 'AVM-Drive-Index'
            'Accept'     = 'application/vnd.github+json'
        }
        $release = Invoke-RestMethod -Uri (Get-UpdateApiUrl) -Headers $headers -TimeoutSec $TimeoutSec
    } catch {
        return $null
    }
    if (-not $release -or -not $release.tag_name) { return $null }
    $latest = [string]$release.tag_name
    if (-not (Test-VersionNewer $latest $script:AppVersion)) { return $null }

    $asset = $release.assets | Where-Object { $_.name -eq $script:UpdateAsset } | Select-Object -First 1
    if (-not $asset -or -not $asset.browser_download_url) { return $null }

    $clean = $latest
    if ($clean.StartsWith('v') -or $clean.StartsWith('V')) { $clean = $clean.Substring(1) }
    return @{ Version = $clean; Url = [string]$asset.browser_download_url }
}

function Get-UpdateCheckDue {
    # At most one automatic check a day.
    $stamp = Join-Path (Get-IndexRoot) '.last-update-check'
    try {
        if (Test-Path -LiteralPath $stamp) {
            $last = [datetime](Get-Content -LiteralPath $stamp -Raw).Trim()
            if (((Get-Date) - $last).TotalHours -lt 20) { return $false }
        }
    } catch { }
    try {
        Set-Content -LiteralPath $stamp -Value (Get-Date).ToString('o') -Encoding ASCII
    } catch { }
    return $true
}

function Install-AppUpdate($Update, [string]$InstallRoot) {
    # Downloads the release zip and hands the swap over to a helper script.
    # Returns $null on success (the caller should quit), or a message to show.
    if (-not $Update -or -not $Update.Url) { return 'There was nothing to download.' }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("avm-drive-index-update-" + [guid]::NewGuid().ToString('N'))
    $zip = Join-Path $work 'update.zip'
    $unpacked = Join-Path $work 'unpacked'
    try {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.SecurityProtocolType]::Tls12
        # Invoke-WebRequest is far faster with the progress bar switched off.
        $previous = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $Update.Url -OutFile $zip -UseBasicParsing -TimeoutSec 300 `
                -Headers @{ 'User-Agent' = 'AVM-Drive-Index' }
        } finally {
            $ProgressPreference = $previous
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $unpacked -Force
    } catch {
        return "The update could not be downloaded.`r`n`r`n$($_.Exception.Message)"
    }

    # The zip holds one top-level folder; fall back to the unpacked root if a
    # future release is packaged flat.
    $source = Join-Path $unpacked $script:UpdateRoot
    if (-not (Test-Path -LiteralPath $source)) {
        $only = @(Get-ChildItem -LiteralPath $unpacked -Directory)
        if ($only.Count -eq 1) { $source = $only[0].FullName } else { $source = $unpacked }
    }
    $marker = Join-Path (Join-Path $source 'App') 'DriveIndexApp.ps1'
    if (-not (Test-Path -LiteralPath $marker)) {
        return 'The downloaded update looks incomplete, so nothing was changed.'
    }

    $launcher = Join-Path $InstallRoot 'AVM Drive Index.cmd'
    $swap = Join-Path $work 'swap.ps1'
    $swapText = @'
param([int]$WaitFor, [string]$Source, [string]$Target, [string]$Launcher, [string]$Work)
# Wait for the app to close so nothing is holding its files open.
for ($i = 0; $i -lt 60; $i++) {
    if (-not (Get-Process -Id $WaitFor -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
# Copy over the installed copy rather than deleting it first: a half-finished
# delete would leave the user with no app at all.
try {
    Copy-Item -Path (Join-Path $Source '*') -Destination $Target -Recurse -Force -ErrorAction Stop
} catch {
    # Leave the old copy working and show the downloaded one instead.
    Start-Process explorer.exe $Source
    exit 1
}
if (Test-Path -LiteralPath $Launcher) { Start-Process -FilePath $Launcher }
Start-Sleep -Seconds 2
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
'@
    try {
        Set-Content -LiteralPath $swap -Value $swapText -Encoding ASCII
        Start-Process -FilePath (Get-HostExecutable) -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden', '-File', "`"$swap`"",
            '-WaitFor', $PID, '-Source', "`"$source`"", '-Target', "`"$InstallRoot`"",
            '-Launcher', "`"$launcher`"", '-Work', "`"$work`""
        ) -WindowStyle Hidden | Out-Null
    } catch {
        return "The update could not be started.`r`n`r`n$($_.Exception.Message)"
    }
    return $null
}
