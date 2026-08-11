# Watcher.ps1 -- the background helper behind AVM Drive Index (Windows).
#
# Started at sign-in by the scheduled task that "Install Drive Indexer.cmd"
# registers, and runs quietly in the background. It listens for drives being
# plugged in or unplugged and runs DriveIndexer.ps1 each time, so the index
# stays current even when the app is closed.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

. (Join-Path $PSScriptRoot 'Common.ps1')

$ErrorActionPreference = 'Continue'
$indexerPath = Join-Path $PSScriptRoot 'DriveIndexer.ps1'
$sourceId    = 'AVMDriveIndexVolumeChange'
$idleRescanSeconds = 900     # safety net in case a plug/unplug event is missed

# Only one watcher per signed-in user.
$mutex = New-Object System.Threading.Mutex($false, 'Local\AVMDriveIndexWatcher')
if (-not $mutex.WaitOne(0)) { exit 0 }

$logDir = Join-Path (Get-IndexRoot) 'Logs'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logPath = Join-Path $logDir 'watcher.log'

function Write-Log([string]$Message) {
    try {
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -LiteralPath $logPath -Value "$stamp  $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
        # Keep the log small.
        $item = Get-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt 200000) {
            $tail = @(Get-Content -LiteralPath $logPath -Tail 200 -ErrorAction SilentlyContinue)
            Set-Content -LiteralPath $logPath -Value $tail -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch { }
}

$hostExe = Get-HostExecutable

function Invoke-Indexer([string]$Reason) {
    Write-Log "scanning ($Reason)"
    try {
        $arguments = @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden', '-File', "`"$indexerPath`""
        )
        $process = Start-Process -FilePath $hostExe -ArgumentList $arguments `
                        -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
        if ($process -and $process.ExitCode -ne 0) {
            Write-Log "indexer exited with code $($process.ExitCode)"
        }
    } catch {
        Write-Log "indexer failed: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------ event plumbing

function Register-VolumeEvents {
    $query = 'SELECT * FROM Win32_VolumeChangeEvent WHERE EventType = 2 OR EventType = 3'
    try {
        Register-CimIndicationEvent -Query $query -SourceIdentifier $sourceId -ErrorAction Stop
        return $true
    } catch {
        Write-Log "CIM subscription failed, trying WMI: $($_.Exception.Message)"
    }
    try {
        Register-WmiEvent -Query $query -SourceIdentifier $sourceId -ErrorAction Stop
        return $true
    } catch {
        Write-Log "WMI subscription failed: $($_.Exception.Message)"
    }
    return $false
}

try {
    Write-Log 'watcher started'
    $subscribed = Register-VolumeEvents
    if (-not $subscribed) {
        Write-Log "no volume events available -- falling back to polling every $idleRescanSeconds seconds"
    }

    # Index whatever is already plugged in.
    Invoke-Indexer 'startup'

    while ($true) {
        $triggered = $false
        if ($subscribed) {
            $event = Wait-Event -SourceIdentifier $sourceId -Timeout $idleRescanSeconds
            if ($event) {
                $triggered = $true
                Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
                # Plugging in one drive fires several events; let them settle so
                # the drive is mounted and readable before scanning.
                Start-Sleep -Seconds 3
                foreach ($extra in @(Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue)) {
                    Remove-Event -EventIdentifier $extra.EventIdentifier -ErrorAction SilentlyContinue
                }
            }
        } else {
            Start-Sleep -Seconds $idleRescanSeconds
        }

        if ($triggered) {
            Invoke-Indexer 'drive connected or removed'
        } else {
            Invoke-Indexer 'periodic check'
        }
    }
} finally {
    Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
    Write-Log 'watcher stopped'
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
