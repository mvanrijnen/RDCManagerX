# Building RDCManagerX

**English** | [Nederlands](BUILDING.nl.md)

This page explains how to build RDCManagerX from source: the app itself, the tests, the Tailscale bridge DLL, the
English translation and the manual. Back to the [README](README.md).

## What ends up in the exe

RDCManagerX is a Delphi VCL application for Windows x64. Everything it needs is embedded in one exe:

| Resource | Source | Built by |
|---|---|---|
| Tailscale bridge (`TSBRIDGE`) | `Bridge\bin\Win64\tsbridge.dll.gz` via `Source\TsBridge.rc` | `Tools\build-tsbridge.cmd` |
| English UI texts (`LANG_EN`) | `Source\Lang\en.po` via `Source\Lang.rc` | `Tools\i18n.py` (you translate) |
| Manual as CHM (`HELPCHM`, `HELPCHM_EN`) | `Docs\help\*.chm` via `Source\HelpChm.rc` | `Tools\build-help.ps1` |
| Manual as HTML (fallback) | `Docs\*.html` via `Source\Help.rc` | (the sources themselves) |
| Light and dark theme | `Styles\*.vsf` (`Custom_Styles` in the dproj) | (files in the repo) |
| Version info | `Source\Version.rc` | `Tools\NextVersion.ps1`, on every build |

The generated files (`tsbridge.dll.gz`, the hash include, the CHMs, `en.po`) are committed. **A fresh clone builds
with Delphi alone**; the other tools are only needed when you change the part they build.

## Requirements

| Part | Tool | Needed |
|---|---|---|
| App and tests | Delphi 12 Athens (RAD Studio 23.0), Win64 platform; DUnitX comes with it | always |
| UI texts | Python 3 | when you change user-visible texts |
| `tsbridge.dll` | Go `go1.27.4` and WinLibs GCC 16.2.0 (MinGW-w64 14.0.0 UCRT, POSIX threads, r3) | only when you change `Bridge\tsbridge` |
| Manual | HTML Help Workshop (`hhc.exe`) or Free Pascal `chmcmd`; Microsoft Edge for the PDFs | only when you change the manual |

Tested with Delphi 12 Athens. Other Delphi versions and editions have not been tried.

## App and tests

From a command prompt in the project folder:

```
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild RDCManagerX.dproj /t:Build /p:Config=Release /p:Platform=Win64 /nologo /v:minimal
msbuild Tests\RDCManagerXTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:minimal
Tests\Win64\Debug\RDCManagerXTests.exe --exitbehavior:Continue
```

Or open `RDCManagerX.dproj` (and `Tests\RDCManagerXTests.dproj`) in the IDE.

- The exe goes to `Win64\Release\RDCManagerX.exe` (or `Win64\Debug`). The build must give **no warnings and no hints**.
- The tests are DUnitX console tests and never touch Windows Credential Manager. Run one test with
  `--run:RdcmX.Tests.Storage.TStorageTests.RoundTripIsByteIdentical`. RDP behaviour itself has no automated tests;
  see `TESTPLAN.md` for the manual test plan. Start the app with `/debuglog` to write
  `%LOCALAPPDATA%\RDCManagerX\debug.log`.
- **Version number** `yyyy.mm.dd.xxx` (xxx = build of the day). `Tools\Version.targets` runs `Tools\NextVersion.ps1`
  before the resource compiler: it increments `BuildNumber.json` and writes `Source\Version.rc`. Leave "Include
  version information" off in the project options, otherwise the exe gets two version resources.
- **DCU folder:** `Tools\DcuOutput.props` puts the `.dcu` files in `$(DCUFolder)\<version>\<project>\<platform>\<config>`
  when the IDE variable `DCUFolder` is set, otherwise in `.\Win64\<config>\dcu`.
- **After the build** `Tools\afterbuild.cmd <config> <exe>` runs, if present. In the repository it is empty. Use it
  for a local copy (for example the Release exe to a share) and keep it out of git with
  `git update-index --skip-worktree Tools/afterbuild.cmd`. If the copy fails, the build does not fail.
- Do not save *Project Options > Appearance* in the IDE: it rewrites the style list and drops the `Styles\` themes.
- Source files are UTF-8 with BOM and CRLF line endings (except the Go sources, see below).

## The Tailscale bridge (tsbridge.dll)

### Why a DLL in Go

The Tailscale route needs no Tailscale client on the PC: RDCManagerX runs its own Tailscale node in the process with
[tsnet](https://pkg.go.dev/tailscale.com/tsnet). That library exists only in Go, so `Bridge\tsbridge` wraps it as a
C DLL (`-buildmode=c-shared`, amd64 only) with a small C API. It forwards a local port on `127.0.0.2` to a device in
the tailnet; the RDP control connects to that port.

### How it ships and loads

1. `Tools\build-tsbridge.cmd` builds `Bridge\bin\Win64\tsbridge.dll`, writes its SHA-256 to
   `Source\RdcmX.TsBridgeHash.inc` and compresses it to `tsbridge.dll.gz`.
2. The exe embeds the gz as RCDATA `TSBRIDGE` (the test project embeds it too, via `Tests\TsBridgeTest.rc`).
3. At first use the app extracts it to `%LOCALAPPDATA%\RDCManagerX\bin\tsbridge-<hash>.dll` (temp file, then rename;
   older versions are removed), opens it without write or delete sharing, checks the SHA-256 against the value in
   the exe and only then loads it, with its imports resolved from System32 only.
4. The DLL is never unloaded (the Go runtime does not support that). Without the DLL the app works normally; only the
   Tailscale route is unavailable.

### Toolchain

The build is reproducible, so the toolchain is pinned. The script refuses other versions.

- **Go** `go1.27.4`: extract the Windows zip to `%LOCALAPPDATA%\Programs\go` (no installation needed), or have `go`
  in `PATH`.
- **WinLibs** GCC 16.2.0, MinGW-w64 14.0.0 UCRT, POSIX threads, release 3:
  `winget install BrechtSanders.WinLibs.POSIX.UCRT --version 16.2.0-14.0.0-r3`, or `gcc` in `PATH`.

`TSBRIDGE_ALLOW_OTHER_TOOLCHAIN=1` builds with another version anyway, but the DLL hash will then differ from the CI
build.

### Building

```
Tools\build-tsbridge.cmd test
```

This checks the toolchain, runs the Go tests (forwarder with a local echo server, encrypted state, secret filtering),
builds the DLL, and writes the hash include and the gz. **Then rebuild RDCManagerX and the test project**: the exe
only loads the DLL whose hash it contains. Commit the Go changes, `tsbridge.dll.gz` and `RdcmX.TsBridgeHash.inc`
together.

### Reproducible build and CI

- Flags: `-trimpath -buildvcs=false`, empty build ID, no PE timestamp. Keep the output name `tsbridge.dll`: GNU ld
  derives the image base from it.
- The Go sources are checked out with LF (`.gitattributes`): cgo hashes the file contents into its export symbols,
  so CRLF would give another DLL.
- `.github/workflows/tsbridge.yml` rebuilds the DLL with the same toolchain and fails when its SHA-256 differs from
  `cTsBridgeSha256` or from the committed `tsbridge.dll.gz`. That proves the committed binary comes from the sources.
- When you upgrade Go or WinLibs, update `PIN_GO`/`PIN_GCC`/`PIN_LD` in the script and `WINLIBS_URL`/`WINLIBS_SHA256`
  in the workflow together.

### C API

cdecl, UTF-8 input, int32 return codes; text goes into a buffer of the caller (the return value is the number of
bytes needed).

```c
int TsNetCreate(const char* configJson);          // handle > 0, or error code < 0
int TsNetUp(int h, int timeoutMs);                // blocks; TsNetClose from another thread aborts it
int TsNetGetStatus(int h, char* buf, int buflen); // JSON: state, ips, dnsName, authUrl, lastError
int TsNetAddForward(int h, const char* localAddr, const char* target); // local port
int TsNetRemoveForward(int h, int localPort);
int TsNetClose(int h);
int TsLastError(int h, char* buf, int buflen);    // h = 0: last error of TsNetCreate
int TsBridgeVersion(char* buf, int buflen);
```

## UI texts (English)

The Dutch texts in the code and the DFMs are the source; English comes from `Source\Lang\en.po`. After changing
user-visible texts:

```
python Tools\i18n.py update
rem translate the new entries (empty msgstr) in Source\Lang\en.po
python Tools\i18n.py check
```

`check` fails on missing translations and on `_()` calls with a non-constant argument. Then rebuild the exe.

## Manual

The sources are `Docs\RDCManagerX-Manual.html` (English) and `Docs\RDCManagerX-Handleiding.html` (Dutch); keep them
in sync. Build the CHMs and PDFs with:

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\build-help.ps1
```

Then rebuild the exe. `hhc.exe` comes from Microsoft's HTML Help Workshop; it can be extracted without installing to
`%LOCALAPPDATA%\Programs\HTMLHelpWorkshop`. The message "Itircl.dll not registered" only concerns the full-text index
and can be ignored. The PDFs are printed with Microsoft Edge. The online manual is published by
`.github/workflows/pages.yml` when `Docs` changes.

## Release package

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\make-release-zip.ps1
```

This packs the Release exe and `LICENSE` into `Win64\Release\RDCManagerX-<version>-win64.zip` and prints the SHA-256
of the zip and the exe for the release notes. Releases are always this zip, never the bare exe; the tag is
`v<version>`. It also writes `Win64\Release\version.json`; upload it with the zip. The update check in the app
downloads that file first, so its download count on GitHub is the number of update checks.
`.github/workflows/stats.yml` writes the counters per day to `downloads.csv` on the branch `stats`.
