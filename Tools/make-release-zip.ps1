# Packs the Release build into a zip for a GitHub release: RDCManagerX-<version>-win64.zip with RDCManagerX.exe and
# LICENSE (the MIT license must travel with the binary). The exe is never published on its own.
# The version comes from the exe's version info; the zip goes to Win64\Release (git-ignored).
# Prints the SHA-256 of the zip and of the exe for the release notes.
param([string]$Root = (Join-Path $PSScriptRoot '..'))

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path
$exe = Join-Path $Root 'Win64\Release\RDCManagerX.exe'
if (-not (Test-Path $exe)) { throw "No Release build found: $exe" }

$version = (Get-Item $exe).VersionInfo.FileVersion
$zip = Join-Path $Root "Win64\Release\RDCManagerX-$version-win64.zip"
$staging = Join-Path ([IO.Path]::GetTempPath()) "rdcmx-release-$version"

Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $staging | Out-Null
Copy-Item $exe $staging
Copy-Item (Join-Path $Root 'LICENSE') $staging
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $staging -Recurse -Force

Write-Output "Zip:     $zip"
Write-Output "Version: $version"
Write-Output ("SHA-256 zip: " + (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower())
Write-Output ("SHA-256 exe: " + (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLower())
