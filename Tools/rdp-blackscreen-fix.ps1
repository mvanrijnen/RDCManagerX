# rdp-blackscreen-fix.ps1 - run ON THE REMOTE PC (the RDP target), as administrator, from the account you log on with
# over RDP. Fixes a session that stays black after being idle (screen saver + WDDM display driver for RDP):
#   1. screen saver off for this user,
#   2. WDDM display driver for Remote Desktop connections off (policy; needs a restart),
#   3. display on AC power never turned off.
# The original values are saved next to the script (rdp-blackscreen-fix-backup.json); -Undo restores them.
# Usage:   powershell -NoProfile -ExecutionPolicy Bypass -File rdp-blackscreen-fix.ps1
# Undo:    powershell -NoProfile -ExecutionPolicy Bypass -File rdp-blackscreen-fix.ps1 -Undo
param([switch]$Undo)
$ErrorActionPreference = 'Stop'
$backup = Join-Path $PSScriptRoot 'rdp-blackscreen-fix-backup.json'
$desk = 'HKCU:\Control Panel\Desktop'
$ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run PowerShell as administrator (needed for the WDDM policy).'
}

function Get-Val($path, $name) {
    try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { $null }
}
function Set-Val($path, $name, $value, $type) {
    if ($null -eq $value) {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    } else {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
    }
}
function Get-MonitorTimeoutAc {
    # Current AC value in seconds (0 = never). The labels of powercfg are localised; the second-last hex value of the
    # output is always the current AC index.
    $hex = @((powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE) | Select-String '0x([0-9a-fA-F]+)\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if ($hex.Count -ge 2) { [Convert]::ToInt64($hex[-2], 16) } else { $null }
}

if ($Undo) {
    if (-not (Test-Path $backup)) { throw "No backup found: $backup" }
    $b = Get-Content $backup -Raw | ConvertFrom-Json
    Set-Val $desk 'ScreenSaveActive' $b.ScreenSaveActive String
    Set-Val $desk 'ScreenSaverIsSecure' $b.ScreenSaverIsSecure String
    Set-Val $ts 'fEnableWddmDriver' $b.fEnableWddmDriver DWord
    if ($null -ne $b.MonitorTimeoutAcSeconds) { powercfg /change monitor-timeout-ac ([int][math]::Ceiling($b.MonitorTimeoutAcSeconds / 60)) }
    'Previous settings restored. Restart the PC (for the WDDM setting).'
    return
}

# Backup of the current values (only the first time, so -Undo always goes back to the original).
if (-not (Test-Path $backup)) {
    [ordered]@{
        ScreenSaveActive        = Get-Val $desk 'ScreenSaveActive'
        ScreenSaverIsSecure     = Get-Val $desk 'ScreenSaverIsSecure'
        fEnableWddmDriver       = Get-Val $ts 'fEnableWddmDriver'
        MonitorTimeoutAcSeconds = Get-MonitorTimeoutAc
    } | ConvertTo-Json | Set-Content $backup -Encoding UTF8
    "Backup: $backup"
}

# 1. Screen saver off (current user). A policy can enforce it; then this user setting does not help.
Set-Val $desk 'ScreenSaveActive' '0' String
$policy = 'HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
if ($null -ne (Get-Val $policy 'ScreenSaveActive')) { "NOTE: the screen saver is set by a policy ($policy); change that policy." }

# 2. WDDM display driver for RDP off (policy; takes effect after a restart).
Set-Val $ts 'fEnableWddmDriver' 0 DWord

# 3. Display on AC power never off.
powercfg /change monitor-timeout-ac 0

''
'Done:'
'  - screen saver off for ' + $env:USERNAME
'  - WDDM display driver for RDP off (fEnableWddmDriver = 0)'
'  - display on AC power: never off'
''
'Restart the PC, then connect again.'
