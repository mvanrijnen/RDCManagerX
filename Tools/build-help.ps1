# Builds the Windows help (CHM) and the PDF of the manual, in Dutch and English, and prepares the CHMs as
# resources for the exe.
#
# Per language (nl: Docs\RDCManagerX-Handleiding.html, en: Docs\RDCManagerX-Manual.html):
#  - Docs\help\<base>.html : the manual with fixed (light) colours; the CHM viewer uses the Internet Explorer engine
#                            and knows no CSS variables or dark mode.
#  - Docs\help\<base>.hhp/.hhc : project and table of contents (one entry per chapter).
#  - Docs\help\<base>.chm : built with chmcmd (Free Pascal) or hhc (HTML Help Workshop), if either is available.
#  - Docs\<manual>.pdf : printed with Microsoft Edge (headless, no header/footer), if Edge is installed.
# Source\HelpChm.rc references the CHMs that were built (HELPCHM = nl, HELPCHM_EN = en); without a compiler it is
# empty and the app falls back to the embedded HTML (Source\Help.rc).
#
# Rebuild RDCManagerX afterwards.
# Compiler: hhc.exe + hha.dll (+ itcc.dll) from Microsoft's HTML Help Workshop, extracted (not installed) to
# %LOCALAPPDATA%\Programs\HTMLHelpWorkshop; or chmcmd from Free Pascal.
param(
  [string]$Root = (Join-Path $PSScriptRoot '..'),
  [switch]$NoPdf
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path
$docs = Join-Path $Root 'Docs'
$helpDir = Join-Path $docs 'help'
New-Item -ItemType Directory -Force $helpDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$languages = @(
  @{ Code = 'nl'; Source = 'RDCManagerX-Handleiding.html'; Base = 'RDCManagerX';    Resource = 'HELPCHM';    Title = 'RDCManagerX - Handleiding'; Lcid = '0x413 Nederlands (standaard)' },
  @{ Code = 'en'; Source = 'RDCManagerX-Manual.html';      Base = 'RDCManagerX-en'; Resource = 'HELPCHM_EN'; Title = 'RDCManagerX - Manual';      Lcid = '0x409 English (United States)' }
)

# --- Compiler: chmcmd (Free Pascal) or hhc (HTML Help Workshop) ---
$compiler = $null
foreach ($name in 'chmcmd.exe', 'hhc.exe') {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { $compiler = $cmd.Source; break }
}
if (-not $compiler) {
  $candidates = @()
  foreach ($base in "$env:LOCALAPPDATA\Programs\HTMLHelpWorkshop", "${env:ProgramFiles(x86)}\HTML Help Workshop", 'C:\FPC', 'C:\lazarus', "$env:LOCALAPPDATA\Programs") {
    if (Test-Path $base) { $candidates += Get-ChildItem $base -Recurse -Include chmcmd.exe, hhc.exe -ErrorAction SilentlyContinue }
  }
  if ($candidates) { $compiler = $candidates[0].FullName }
}

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1

$rcLines = New-Object System.Collections.Generic.List[string]
foreach ($lang in $languages) {
  $sourceFile = Join-Path $docs $lang.Source
  $base = $lang.Base

  # --- HTML for the CHM: replace CSS variables with fixed light colours, drop dark mode and print rules ---
  $html = [IO.File]::ReadAllText($sourceFile, [Text.Encoding]::UTF8)
  $vars = @{}
  $rootBlock = [regex]::Match($html, ':root\s*\{([^}]*)\}').Groups[1].Value
  foreach ($m in [regex]::Matches($rootBlock, '--([\w-]+)\s*:\s*([^;]+);')) { $vars[$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
  $html = [regex]::Replace($html, '@media \(prefers-color-scheme: dark\)\s*\{[^{}]*\{[^{}]*\}\s*\}', '')
  $html = [regex]::Replace($html, '@media print\s*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}', '')
  $html = [regex]::Replace($html, 'var\(--([\w-]+)\)', { param($m) $vars[$m.Groups[1].Value] })
  $html = [regex]::Replace($html, ':root\s*\{[^}]*\}', '')
  $html = $html.Replace('<meta charset="utf-8">', '<meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge">')
  [IO.File]::WriteAllText((Join-Path $helpDir "$base.html"), $html, $utf8)

  # --- Table of contents from the chapters (h2 with id) ---
  $toc = New-Object Text.StringBuilder
  [void]$toc.AppendLine('<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><BODY><UL>')
  [void]$toc.AppendLine(('<LI><OBJECT type="text/sitemap"><param name="Name" value="RDCManagerX"><param name="Local" value="{0}.html"></OBJECT>' -f $base))
  [void]$toc.AppendLine('<UL>')
  foreach ($m in [regex]::Matches($html, '<h2 id="([^"]+)"[^>]*>([^<]+)</h2>')) {
    $title = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
    [void]$toc.AppendLine(('<LI><OBJECT type="text/sitemap"><param name="Name" value="{0}"><param name="Local" value="{1}.html#{2}"></OBJECT>' -f $title, $base, $m.Groups[1].Value))
  }
  [void]$toc.AppendLine('</UL></UL></BODY></HTML>')
  [IO.File]::WriteAllText((Join-Path $helpDir "$base.hhc"), $toc.ToString(), [Text.Encoding]::GetEncoding(1252))

  $hhp = @"
[OPTIONS]
Compatibility=1.1 or later
Compiled file=$base.chm
Contents file=$base.hhc
Default topic=$base.html
Default Window=main
Display compile progress=No
Language=$($lang.Lcid)
Title=$($lang.Title)

[WINDOWS]
main="$($lang.Title)","$base.hhc",,"$base.html","$base.html",,,,,0x63520,260,0x104e,[80,60,1080,810],,,,,,,0

[FILES]
$base.html
"@
  [IO.File]::WriteAllText((Join-Path $helpDir "$base.hhp"), $hhp, [Text.Encoding]::GetEncoding(1252))

  # --- Compile ---
  $chm = Join-Path $helpDir "$base.chm"
  if (Test-Path $chm) { Remove-Item $chm -Force }
  if ($compiler) {
    # hhc sometimes reports "Itircl.dll has not been registered": that concerns the full-text index (not used).
    Push-Location $helpDir
    try { & $compiler "$base.hhp" | Out-Host } finally { Pop-Location }
  }
  if ($compiler -and (Test-Path $chm)) {
    $rcLines.Add(('{0} RCDATA "Docs\\help\\{1}.chm"' -f $lang.Resource, $base))
    Write-Host "CHM ($($lang.Code)) built with $compiler -> $chm"
  }

  # --- PDF via Edge (no header/footer, so no local path ends up in the PDF) ---
  if (-not $NoPdf -and $edge) {
    $pdf = [IO.Path]::ChangeExtension($sourceFile, '.pdf')
    $profileDir = Join-Path ([IO.Path]::GetTempPath()) 'rdcmx-edge-pdf'
    $url = 'file:///' + $sourceFile.Replace('\', '/')
    # Start-Process: Edge writes harmless messages to stderr, which Windows PowerShell 5.1 would turn into errors.
    $edgeArgs = @('--headless', '--disable-gpu', '--no-pdf-header-footer', "`"--user-data-dir=$profileDir`"", "`"--print-to-pdf=$pdf`"", "`"$url`"")
    Start-Process -FilePath $edge -ArgumentList $edgeArgs -Wait -WindowStyle Hidden
    Write-Host "PDF ($($lang.Code)) -> $pdf"
  }
}

$rc = Join-Path $Root 'Source\HelpChm.rc'
if ($rcLines.Count -gt 0) {
  $text = "// Windows help (CHM), generated by Tools\build-help.ps1. The app extracts it and opens it via Help.`r`n" + ($rcLines -join "`r`n") + "`r`n"
  [IO.File]::WriteAllText($rc, $text, [Text.Encoding]::ASCII)
  Write-Host 'Now rebuild RDCManagerX.'
} else {
  [IO.File]::WriteAllText($rc, "// No CHM built (no chmcmd/hhc found): the app uses the embedded HTML manual.`r`n// To build: winget install FreePascal.FreePascalCompiler, then Tools\build-help.ps1.`r`n", [Text.Encoding]::ASCII)
  Write-Warning 'No CHM compiler found (chmcmd or hhc); HelpChm.rc is empty. Install: winget install FreePascal.FreePascalCompiler'
}
