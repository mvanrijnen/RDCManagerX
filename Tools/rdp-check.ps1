# rdp-check.ps1 - run ON THE REMOTE PC (the RDP target) when a session goes black after being idle.
# Only reads settings, changes nothing.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File rdp-check.ps1

function Get-PowerIndex($sub, $setting) {
    # Current value (seconds) on AC and battery (DC). The labels of powercfg are localised; the last two hex values of
    # the output are always the current AC and DC index, in every language.
    $hex = @((powercfg /query SCHEME_CURRENT $sub $setting 2>$null) | Select-String '0x([0-9a-fA-F]+)\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    $fmt = { param($h) if ($h) { $s = [Convert]::ToInt64($h, 16); if ($s -eq 0 -or $s -ge 4294967295) { 'never' } elseif ($s -lt 60) { "$s s" } else { "$([math]::Round($s / 60, 1)) min" } } else { '?' } }
    if ($hex.Count -lt 2) { return '?' }
    "AC: $(& $fmt $hex[-2])   battery: $(& $fmt $hex[-1])"
}
function Get-Reg($path, $name) {
    try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { '(not set)' }
}

"=== Power (active scheme: $((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1')) ==="
"Turn off display after : " + (Get-PowerIndex SUB_VIDEO VIDEOIDLE)
"Sleep after            : " + (Get-PowerIndex SUB_SLEEP STANDBYIDLE)
"Hibernate after        : " + (Get-PowerIndex SUB_SLEEP HIBERNATEIDLE)

"`n=== RDP / graphics ==="
$ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
"WDDM driver for RDP (fEnableWddmDriver; 0 = off, not set = on) : " + (Get-Reg $ts 'fEnableWddmDriver')
"Transport (SelectTransport; 0 = TCP+UDP, 1 = TCP only)         : " + (Get-Reg $ts 'SelectTransport')
"Max idle time of a session (MaxIdleTime, ms)                   : " + (Get-Reg $ts 'MaxIdleTime')
"RDP allowed (fDenyTSConnections; 0 = yes)                      : " + (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections')
"Graphics adapters:"; Get-CimInstance Win32_VideoController | ForEach-Object { "  $($_.Name)  driver $($_.DriverVersion)" }

"`n=== Screen saver / lock (current user) ==="
$desk = 'HKCU:\Control Panel\Desktop'
"Screen saver active     : " + (Get-Reg $desk 'ScreenSaveActive')
"After (seconds)         : " + (Get-Reg $desk 'ScreenSaveTimeOut')
"Password on resume      : " + (Get-Reg $desk 'ScreenSaverIsSecure')
"Lock after inactivity (InactivityTimeoutSecs) : " + (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'InactivityTimeoutSecs')

"`n=== System ==="
$os = Get-CimInstance Win32_OperatingSystem
"$($os.Caption) $($os.Version), last boot $($os.LastBootUpTime)"

"`n=== Last RDP session events ==="
try {
    Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' -MaxEvents 15 -ErrorAction Stop |
        ForEach-Object { "  $($_.TimeCreated.ToString('dd-MM HH:mm:ss'))  [$($_.Id)] $(($_.Message -split "`n")[0])" }
} catch { "  (not readable: $($_.Exception.Message))" }
