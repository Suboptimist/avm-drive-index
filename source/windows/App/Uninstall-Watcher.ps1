# Uninstall-Watcher.ps1 -- turns off background indexing.
#
# Called by "Uninstall Drive Indexer.cmd". Removes the autostart entry and stops
# the running watcher. The index itself is deliberately left untouched.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

. (Join-Path $PSScriptRoot 'Common.ps1')

$taskName    = 'AVM Drive Indexer'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'AVM Drive Indexer.lnk'

try {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host 'Removed the scheduled task.'
} catch {
    # Nothing registered -- that is fine.
}

if (Test-Path -LiteralPath $startupLink) {
    Remove-Item -LiteralPath $startupLink -Force -ErrorAction SilentlyContinue
    Write-Host 'Removed the Startup shortcut.'
}

# Stop any watcher that is still running, without touching other PowerShell
# windows: match on the Watcher.ps1 path in the command line.
try {
    $running = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" `
                    -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -and $_.CommandLine -like '*Watcher.ps1*' })
    foreach ($process in $running) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($running.Count -gt 0) { Write-Host "Stopped $($running.Count) running helper(s)." }
} catch { }

Write-Host ''
Write-Host 'The AVM Drive Indexer has been turned off.'
Write-Host 'Your index and its contents were left untouched:'
Write-Host "  $(Get-IndexRoot)"
Write-Host ''
Write-Host 'To turn it back on later, run "Install Drive Indexer.cmd".'
Write-Host ''
