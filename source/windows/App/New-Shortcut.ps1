# New-Shortcut.ps1 -- puts an "AVM Drive Index" shortcut on the Desktop, with
# the app icon, so it opens like any other program.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

. (Join-Path $PSScriptRoot 'Common.ps1')

$appScript = Join-Path $PSScriptRoot 'DriveIndexApp.ps1'
$iconPath  = Join-Path $PSScriptRoot 'AppIcon.ico'
$linkPath  = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AVM Drive Index.lnk'

try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($linkPath)
    $shortcut.TargetPath = Get-HostExecutable
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appScript`""
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.WindowStyle = 7            # start minimised so no console flashes
    $shortcut.Description = 'Browse the index of external drives connected to this PC'
    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = "$iconPath,0"
    }
    $shortcut.Save()
    Write-Host ''
    Write-Host 'Done! There is now an "AVM Drive Index" icon on your Desktop.'
    Write-Host ''
} catch {
    Write-Host ''
    Write-Host "The shortcut could not be created: $($_.Exception.Message.Trim())"
    Write-Host 'You can still open the app with "AVM Drive Index.cmd".'
    Write-Host ''
}
