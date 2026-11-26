@echo off
rem Bouwt Bridge\tsbridge -> Bridge\bin\Win64\tsbridge.dll (Go c-shared, amd64; RDCManagerX is alleen Win64).
rem Gezocht in PATH, anders op de standaardplekken:
rem   Go:    %LOCALAPPDATA%\Programs\go\bin
rem   gcc:   winget-pakket BrechtSanders.WinLibs.POSIX.UCRT
rem Gebruik: Tools\build-tsbridge.cmd [test]   ("test" draait eerst de Go-tests)
rem Na het bouwen: controlesom naar Source\RdcmX.TsBridgeHash.inc en tsbridge.dll.gz voor de resource in de exe.
rem
rem Reproducible build: the same sources and the same toolchain give a byte-identical DLL, wherever the source
rem tree lives (-trimpath, no VCS stamp, empty build ID, no PE timestamp; GNU ld derives the DLL image base from
rem the output file name, so that name must stay tsbridge.dll). The toolchain is pinned below and checked;
rem .github\workflows\tsbridge.yml rebuilds the DLL with it and fails when the SHA-256 differs from
rem cTsBridgeSha256. After changing a pinned version, update the workflow too (WinLibs URL and SHA-256).
rem Set TSBRIDGE_ALLOW_OTHER_TOOLCHAIN=1 to build with another version anyway (the hash will not match CI).
setlocal

rem Pinned toolchain.
set "PIN_GO=go1.27.4"
set "PIN_GCC=(MinGW-W64 x86_64-ucrt-posix-seh, built by Brecht Sanders, r3) 16.2.0"
set "PIN_LD=GNU ld (Binutils for MinGW-W64 x86_64, built by Brecht Sanders, r3) 2.47.20260726"

set "ROOT=%~dp0.."
set "SRC=%ROOT%\Bridge\tsbridge"
set "OUT=%ROOT%\Bridge\bin\Win64"

where go >nul 2>nul || set "PATH=%LOCALAPPDATA%\Programs\go\bin;%PATH%"
where go >nul 2>nul || (echo FOUT: Go niet gevonden. & exit /b 1)

where gcc >nul 2>nul || for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs*") do set "PATH=%%~D\mingw64\bin;%PATH%"
where gcc >nul 2>nul || (echo FOUT: gcc ^(mingw-w64^) niet gevonden. & exit /b 1)

rem Only the settings below may influence the build (no GOFLAGS, CGO_* or toolchain download from the environment).
set GOTOOLCHAIN=local
set GOFLAGS=
set GOEXPERIMENT=
set GOAMD64=v1
set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64
set CC=gcc
set "CGO_CFLAGS=-O2 -g"
set CGO_CPPFLAGS=
set CGO_LDFLAGS=

set "VER_GO="
set "VER_GCC="
set "VER_LD="
for /f "usebackq delims=" %%V in (`go env GOVERSION`) do set "VER_GO=%%V"
rem First line of gcc --version without the program name (gcc or gcc.exe, depending on how it was started).
for /f "usebackq tokens=1,*" %%A in (`gcc --version`) do if not defined VER_GCC set "VER_GCC=%%B"
for /f "usebackq delims=" %%V in (`ld --version`) do if not defined VER_LD set "VER_LD=%%V"
set "TOOLCHAIN_OK=1"
if not "%VER_GO%"=="%PIN_GO%" set "TOOLCHAIN_OK="
if not "%VER_GCC%"=="%PIN_GCC%" set "TOOLCHAIN_OK="
if not "%VER_LD%"=="%PIN_LD%" set "TOOLCHAIN_OK="
if not defined TOOLCHAIN_OK (
  echo Toolchain differs from the pinned versions:
  echo   go:  "%VER_GO%"  expected "%PIN_GO%"
  echo   gcc: "%VER_GCC%"
  echo        expected "%PIN_GCC%"
  echo   ld:  "%VER_LD%"
  echo        expected "%PIN_LD%"
  if not "%TSBRIDGE_ALLOW_OTHER_TOOLCHAIN%"=="1" (
    echo FOUT: install the pinned versions, or set TSBRIDGE_ALLOW_OTHER_TOOLCHAIN=1 ^(the DLL hash will then not match the CI build^).
    exit /b 1
  )
  echo WARNING: building anyway ^(TSBRIDGE_ALLOW_OTHER_TOOLCHAIN=1^).
)

pushd "%SRC%" || exit /b 1
if /i "%~1"=="test" (
  go test ./... || (popd & exit /b 1)
)
if not exist "%OUT%" mkdir "%OUT%"
go build -buildmode=c-shared -trimpath -buildvcs=false -ldflags "-s -w -buildid= -extldflags=-Wl,--no-insert-timestamp" -o "%OUT%\tsbridge.dll" . || (popd & exit /b 1)
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
echo Controlesom vastgelegd in Source\RdcmX.TsBridgeHash.inc ^(nu RDCManagerX opnieuw bouwen^): %HASH%

rem Gecomprimeerd voor de resource in de exe (Source\TsBridge.rc): de launcher kopieert alleen de exe.
rem (Een losse DLL naast de Debug-exe is daardoor niet meer nodig; de exe pakt de ingebouwde zelf uit.)
powershell -NoProfile -NonInteractive -Command "$i=[IO.File]::OpenRead('%OUT%\tsbridge.dll'); $o=[IO.File]::Create('%OUT%\tsbridge.dll.gz'); $z=New-Object IO.Compression.GZipStream($o,[IO.Compression.CompressionLevel]::Optimal); $i.CopyTo($z); $z.Dispose(); $o.Dispose(); $i.Dispose()" || (echo FOUT: comprimeren mislukt. & exit /b 1)
echo tsbridge.dll.gz gemaakt voor de resource in RDCManagerX.exe
endlocal
