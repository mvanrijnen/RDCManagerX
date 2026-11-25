@echo off
rem Bouwt Bridge\tsbridge -> Bridge\bin\Win64\tsbridge.dll (Go c-shared, amd64; RDCManagerX is alleen Win64).
rem Vereist Go (1.26+) en mingw-w64 (gcc). Gezocht in PATH, anders op de standaardplekken:
rem   Go:    %LOCALAPPDATA%\Programs\go\bin
rem   gcc:   winget-pakket BrechtSanders.WinLibs.POSIX.UCRT
rem Gebruik: Tools\build-tsbridge.cmd [test]   ("test" draait eerst de Go-tests)
rem Na het bouwen: controlesom naar Source\RdcmX.TsBridgeHash.inc en tsbridge.dll.gz voor de resource in de exe.
setlocal

set "ROOT=%~dp0.."
set "SRC=%ROOT%\Bridge\tsbridge"
set "OUT=%ROOT%\Bridge\bin\Win64"

where go >nul 2>nul || set "PATH=%LOCALAPPDATA%\Programs\go\bin;%PATH%"
where go >nul 2>nul || (echo FOUT: Go niet gevonden. & exit /b 1)

where gcc >nul 2>nul || for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs*") do set "PATH=%%~D\mingw64\bin;%PATH%"
where gcc >nul 2>nul || (echo FOUT: gcc ^(mingw-w64^) niet gevonden. & exit /b 1)

set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64
set CC=gcc

pushd "%SRC%" || exit /b 1
if /i "%~1"=="test" (
  go test ./... || (popd & exit /b 1)
)
if not exist "%OUT%" mkdir "%OUT%"
go build -buildmode=c-shared -trimpath -ldflags "-s -w" -o "%OUT%\tsbridge.dll" . || (popd & exit /b 1)
popd
echo tsbridge.dll gebouwd: %OUT%\tsbridge.dll

rem Controlesom vastleggen in de exe (Source\RdcmX.TsBridgeHash.inc): RDCManagerX laadt alleen deze DLL.
rem Daarna RDCManagerX opnieuw bouwen, anders weigert de exe de nieuwe DLL.
set "HASH="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -NonInteractive -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%OUT%\tsbridge.dll').Hash.ToLower()"`) do set "HASH=%%H"
if "%HASH%"=="" (echo FOUT: controlesom kon niet worden berekend. & exit /b 1)
> "%ROOT%\Source\RdcmX.TsBridgeHash.inc" (
  echo // Gegenereerd door Tools\build-tsbridge.cmd: SHA-256 van tsbridge.dll. Niet met de hand wijzigen.
  echo // RDCManagerX laadt alleen de tsbridge.dll met deze controlesom.
  echo const
  echo   cTsBridgeSha256 = '%HASH%';
)
echo Controlesom vastgelegd in Source\RdcmX.TsBridgeHash.inc ^(nu RDCManagerX opnieuw bouwen^)

rem Gecomprimeerd voor de resource in de exe (Source\TsBridge.rc): de launcher kopieert alleen de exe.
rem (Een losse DLL naast de Debug-exe is daardoor niet meer nodig; de exe pakt de ingebouwde zelf uit.)
powershell -NoProfile -NonInteractive -Command "$i=[IO.File]::OpenRead('%OUT%\tsbridge.dll'); $o=[IO.File]::Create('%OUT%\tsbridge.dll.gz'); $z=New-Object IO.Compression.GZipStream($o,[IO.Compression.CompressionLevel]::Optimal); $i.CopyTo($z); $z.Dispose(); $o.Dispose(); $i.Dispose()" || (echo FOUT: comprimeren mislukt. & exit /b 1)
echo tsbridge.dll.gz gemaakt voor de resource in RDCManagerX.exe
endlocal
