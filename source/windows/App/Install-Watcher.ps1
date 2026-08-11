# Install-Watcher.ps1 -- turns on background indexing.
#
# Called by "Install Drive Indexer.cmd". Registers a scheduled task that starts
# the watcher at sign-in (falling back to a Startup-folder shortcut if task
# registration is blocked), starts it right away, and indexes whatever is
# already plugged in.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

. (Join-Path $PSScriptRoot 'Common.ps1')

$taskName    = 'AVM Drive Indexer'
$watcherPath = Join-Path $PSScriptRoot 'Watcher.ps1'
$indexerPath = Join-Path $PSScriptRoot 'DriveIndexer.ps1'
$hostExe     = Get-HostExecutable
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'AVM Drive Indexer.lnk'

$watcherArguments = @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden', '-File', "`"$watcherPath`""
)

Write-Host ''
Write-Host 'Setting up the AVM Drive Indexer...'
Write-Host ''
Write-Host "  Private index folder : $(Get-IndexRoot)"
Write-Host '  Watching             : every drive connect / disconnect'
Write-Host ''

$indexRoot = Get-IndexRoot
if (-not (Test-Path -LiteralPath $indexRoot)) {
    New-Item -ItemType Directory -Path $indexRoot -Force | Out-Null
}

# ---------------------------------------------------------------- autostart

$method = $null

try {
    $action = New-ScheduledTaskAction -Execute $hostExe -Argument ($watcherArguments -join ' ')
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable -Hidden -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Description 'Keeps the AVM Drive Index up to date when drives are connected.' `
        -Force -ErrorAction Stop | Out-Null
    $method = 'task'
    Write-Host 'Registered the background helper as a scheduled task.'
} catch {
    Write-Host "Could not register a scheduled task ($($_.Exception.Message.Trim()))."
    Write-Host 'Falling back to a Startup shortcut instead...'
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupLink)
        $shortcut.TargetPath = $hostExe
        $shortcut.Arguments = ($watcherArguments -join ' ')
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.WindowStyle = 7          # minimized
        $shortcut.Description = 'AVM Drive Indexer background helper'
        $shortcut.Save()
        $method = 'startup'
        Write-Host 'Added the background helper to your Startup folder.'
    } catch {
        Write-Host ''
        Write-Host 'Automatic startup could not be set up:'
        Write-Host "  $($_.Exception.Message.Trim())"
        Write-Host ''
        Write-Host 'The app itself will still work, and its Rescan button will still'
        Write-Host 'index whatever is plugged in at that moment.'
    }
}

# ---------------------------------------------------------------- start now

try {
    Start-Process -FilePath $hostExe -ArgumentList $watcherArguments -WindowStyle Hidden | Out-Null
    Write-Host 'Started the background helper.'
} catch {
    Write-Host "Could not start the background helper: $($_.Exception.Message.Trim())"
}

Write-Host ''
Write-Host 'Indexing the drives that are connected right now...'
try {
    & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $indexerPath | Out-Null
} catch {
    Write-Host "  (the first scan failed: $($_.Exception.Message.Trim()))"
}

Write-Host ''
Write-Host 'Done! The AVM Drive Indexer is now running.'
Write-Host ''
if ($method) {
    Write-Host 'From now on it starts automatically when you sign in, and every'
    Write-Host 'external drive you connect is added to the index.'
}
Write-Host 'Open "AVM Drive Index.cmd" to browse the index.'
Write-Host ''
