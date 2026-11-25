# Bepaalt het volgende versienummer yyyy.mm.dd.xxx en schrijft Source\Version.rc (VERSIONINFO).
# Draait vóór de resource-compilatie van RDCManagerX.dproj (via Tools\Version.targets; IDE en msbuild).
#
# - xxx = oplopend buildnummer per dag, begint elke dag bij 001 (teller in BuildNumber.json in de projectmap).
# - Windows-versievelden zijn 16 bits: 2026,11,24,7 past ruim; de weergave is 2026.11.24.007.
# - Version.rc wordt alleen herschreven als het nummer verandert (dus altijd: elke build telt op).

param([string]$ProjectDir = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$counterFile = Join-Path $ProjectDir 'BuildNumber.json'
$rcFile = Join-Path $ProjectDir 'Source\Version.rc'

$today = Get-Date
$todayKey = $today.ToString('yyyy-MM-dd')
$build = 1
if (Test-Path $counterFile) {
  $state = Get-Content $counterFile -Raw | ConvertFrom-Json
  if ($state.date -eq $todayKey) { $build = [int]$state.build + 1 }
}
if ($build -gt 999) { throw "Meer dan 999 builds op $todayKey; het buildnummer past niet meer in xxx." }
@{ date = $todayKey; build = $build } | ConvertTo-Json | Set-Content -Path $counterFile -Encoding ASCII

$version = '{0:yyyy}.{0:MM}.{0:dd}.{1:D3}' -f $today, $build
$numeric = '{0},{1},{2},{3}' -f $today.Year, $today.Month, $today.Day, $build

$rc = @"
// Gegenereerd door Tools\NextVersion.ps1 bij elke build; niet handmatig wijzigen.
1 VERSIONINFO
FILEVERSION $numeric
PRODUCTVERSION $numeric
FILEFLAGSMASK 0x3F
FILEFLAGS 0x0
FILEOS 0x4
FILETYPE 0x1
FILESUBTYPE 0x0
{
  BLOCK "StringFileInfo"
  {
    BLOCK "041304E4"
    {
      VALUE "FileDescription", "RDCManagerX\0"
      VALUE "FileVersion", "$version\0"
      VALUE "InternalName", "RDCManagerX\0"
      VALUE "OriginalFilename", "RDCManagerX.exe\0"
      VALUE "ProductName", "RDCManagerX\0"
      VALUE "ProductVersion", "$version\0"
    }
  }
  BLOCK "VarFileInfo"
  {
    VALUE "Translation", 0x0413, 1252
  }
}
"@
Set-Content -Path $rcFile -Value $rc -Encoding ASCII
"RDCManagerX versie $version"
