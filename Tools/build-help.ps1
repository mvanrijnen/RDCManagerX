# Bouwt de Windows-help (CHM) uit Docs\RDCManagerX-Handleiding.html en zet hem klaar als resource voor de exe.
#
#  - Docs\help\RDCManagerX.html : de handleiding met vaste (lichte) kleuren; de CHM-viewer gebruikt de Internet
#                                  Explorer-engine en kent geen CSS-variabelen of donkere modus.
#  - Docs\help\RDCManagerX.hhp/.hhc : project en inhoudsopgave (per hoofdstuk).
#  - Docs\help\RDCManagerX.chm : met chmcmd (Free Pascal) of hhc (HTML Help Workshop), als een van beide er is.
#  - Source\HelpChm.rc : verwijst naar de CHM als die gebouwd is; anders leeg (de app gebruikt dan de ingebouwde HTML).
#
# Daarna RDCManagerX opnieuw bouwen.
# Compiler: hhc.exe + hha.dll (+ itcc.dll) uit Microsofts HTML Help Workshop, uitgepakt (niet geinstalleerd) naar
# %LOCALAPPDATA%\Programs\HTMLHelpWorkshop; of chmcmd van Free Pascal.
param([string]$Root = (Join-Path $PSScriptRoot '..'))

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path
$docs = Join-Path $Root 'Docs'
$helpDir = Join-Path $docs 'help'
New-Item -ItemType Directory -Force $helpDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# --- HTML voor de CHM: CSS-variabelen vervangen door vaste lichte kleuren, donkere modus eruit ---
$html = [IO.File]::ReadAllText((Join-Path $docs 'RDCManagerX-Handleiding.html'), [Text.Encoding]::UTF8)
$vars = @{}
$rootBlock = [regex]::Match($html, ':root\s*\{([^}]*)\}').Groups[1].Value
foreach ($m in [regex]::Matches($rootBlock, '--([\w-]+)\s*:\s*([^;]+);')) { $vars[$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
$html = [regex]::Replace($html, '@media \(prefers-color-scheme: dark\)\s*\{[^{}]*\{[^{}]*\}\s*\}', '')
$html = [regex]::Replace($html, '@media print\s*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}', '')
$html = [regex]::Replace($html, 'var\(--([\w-]+)\)', { param($m) $vars[$m.Groups[1].Value] })
$html = [regex]::Replace($html, ':root\s*\{[^}]*\}', '')
$html = $html.Replace('<meta charset="utf-8">', '<meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge">')
[IO.File]::WriteAllText((Join-Path $helpDir 'RDCManagerX.html'), $html, $utf8)

# --- Inhoudsopgave uit de hoofdstukken (h2 met id) ---
$toc = New-Object Text.StringBuilder
[void]$toc.AppendLine('<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML><BODY><UL>')
[void]$toc.AppendLine('<LI><OBJECT type="text/sitemap"><param name="Name" value="RDCManagerX"><param name="Local" value="RDCManagerX.html"></OBJECT>')
[void]$toc.AppendLine('<UL>')
foreach ($m in [regex]::Matches($html, '<h2 id="([^"]+)"[^>]*>([^<]+)</h2>')) {
  $title = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
  [void]$toc.AppendLine(('<LI><OBJECT type="text/sitemap"><param name="Name" value="{0}"><param name="Local" value="RDCManagerX.html#{1}"></OBJECT>' -f $title, $m.Groups[1].Value))
}
[void]$toc.AppendLine('</UL></UL></BODY></HTML>')
[IO.File]::WriteAllText((Join-Path $helpDir 'RDCManagerX.hhc'), $toc.ToString(), [Text.Encoding]::GetEncoding(1252))

$hhp = @"
[OPTIONS]
Compatibility=1.1 or later
Compiled file=RDCManagerX.chm
Contents file=RDCManagerX.hhc
Default topic=RDCManagerX.html
Default Window=main
Display compile progress=No
Language=0x413 Nederlands (standaard)
Title=RDCManagerX - Handleiding

[WINDOWS]
main="RDCManagerX - Handleiding","RDCManagerX.hhc",,"RDCManagerX.html","RDCManagerX.html",,,,,0x63520,260,0x104e,[80,60,1080,810],,,,,,,0

[FILES]
RDCManagerX.html
"@
[IO.File]::WriteAllText((Join-Path $helpDir 'RDCManagerX.hhp'), $hhp, [Text.Encoding]::GetEncoding(1252))

# --- Compileren: chmcmd (Free Pascal) of hhc (HTML Help Workshop) ---
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

$chm = Join-Path $helpDir 'RDCManagerX.chm'
$rc = Join-Path $Root 'Source\HelpChm.rc'
if (Test-Path $chm) { Remove-Item $chm -Force }
if ($compiler) {
  # hhc meldt soms "Itircl.dll has not been registered": dat gaat over de volledige-tekstindex (niet gebruikt).
  Push-Location $helpDir
  try { & $compiler 'RDCManagerX.hhp' | Out-Host } finally { Pop-Location }
}
if ($compiler -and (Test-Path $chm)) {
  [IO.File]::WriteAllText($rc, "// Windows-help (CHM), gemaakt door Tools\build-help.ps1. De app pakt hem uit en opent hem via Help.`r`nHELPCHM RCDATA `"Docs\\help\\RDCManagerX.chm`"`r`n", [Text.Encoding]::ASCII)
  Write-Host "CHM gebouwd met $compiler -> $chm (nu RDCManagerX opnieuw bouwen)"
} else {
  [IO.File]::WriteAllText($rc, "// Geen CHM gebouwd (geen chmcmd/hhc gevonden): de app gebruikt de ingebouwde HTML-handleiding.`r`n// Bouwen: winget install FreePascal.FreePascalCompiler, dan Tools\build-help.ps1.`r`n", [Text.Encoding]::ASCII)
  Write-Warning 'Geen CHM-compiler gevonden (chmcmd of hhc); HelpChm.rc is leeg. Installeer: winget install FreePascal.FreePascalCompiler'
}
