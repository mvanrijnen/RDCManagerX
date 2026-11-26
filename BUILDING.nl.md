# RDCManagerX bouwen

[English](BUILDING.md) | **Nederlands**

Deze pagina legt uit hoe je RDCManagerX vanaf de broncode bouwt: de app zelf, de tests, de Tailscale-bridge-DLL, de
Engelse vertaling en de handleiding. Terug naar de [README](README.nl.md).

## Wat er in de exe terechtkomt

RDCManagerX is een Delphi VCL-applicatie voor Windows x64. Alles wat hij nodig heeft, zit in één exe:

| Resource | Bron | Gebouwd door |
|---|---|---|
| Tailscale-bridge (`TSBRIDGE`) | `Bridge\bin\Win64\tsbridge.dll.gz` via `Source\TsBridge.rc` | `Tools\build-tsbridge.cmd` |
| Engelse teksten (`LANG_EN`) | `Source\Lang\en.po` via `Source\Lang.rc` | `Tools\i18n.py` (vertalen doe je zelf) |
| Handleiding als CHM (`HELPCHM`, `HELPCHM_EN`) | `Docs\help\*.chm` via `Source\HelpChm.rc` | `Tools\build-help.ps1` |
| Handleiding als HTML (terugval) | `Docs\*.html` via `Source\Help.rc` | (de bronbestanden zelf) |
| Licht en donker thema | `Styles\*.vsf` (`Custom_Styles` in de dproj) | (bestanden in de repo) |
| Versie-informatie | `Source\Version.rc` | `Tools\NextVersion.ps1`, bij elke build |

De gegenereerde bestanden (`tsbridge.dll.gz`, de hash-include, de CHM's, `en.po`) staan in git. **Een verse clone
bouwt met alleen Delphi**; de andere tools heb je pas nodig als je het onderdeel wijzigt dat ze bouwen.

## Benodigdheden

| Onderdeel | Tool | Nodig |
|---|---|---|
| App en tests | Delphi 12 Athens (RAD Studio 23.0), platform Win64; DUnitX zit erbij | altijd |
| Teksten in de UI | Python 3 | als je zichtbare teksten wijzigt |
| `tsbridge.dll` | Go `go1.27.4` en WinLibs GCC 16.2.0 (MinGW-w64 14.0.0 UCRT, POSIX threads, r3) | alleen als je `Bridge\tsbridge` wijzigt |
| Handleiding | HTML Help Workshop (`hhc.exe`) of Free Pascal `chmcmd`; Microsoft Edge voor de PDF's | alleen als je de handleiding wijzigt |

Getest met Delphi 12 Athens. Andere Delphi-versies en -edities zijn niet geprobeerd.

## App en tests

Vanaf een opdrachtprompt in de projectmap:

```
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild RDCManagerX.dproj /t:Build /p:Config=Release /p:Platform=Win64 /nologo /v:minimal
msbuild Tests\RDCManagerXTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:minimal
Tests\Win64\Debug\RDCManagerXTests.exe --exitbehavior:Continue
```

Of open `RDCManagerX.dproj` (en `Tests\RDCManagerXTests.dproj`) in de IDE.

- De exe komt in `Win64\Release\RDCManagerX.exe` (of `Win64\Debug`). De build moet **zonder warnings en hints**.
- De tests zijn DUnitX-consoletests en komen nooit aan Windows Referentiebeheer. Eén test draaien:
  `--run:RdcmX.Tests.Storage.TStorageTests.RoundTripIsByteIdentical`. Het RDP-gedrag zelf heeft geen automatische
  tests; zie `TESTPLAN.md` voor het handmatige testplan. Start de app met `/debuglog` voor
  `%LOCALAPPDATA%\RDCManagerX\debug.log`.
- **Versienummer** `jjjj.mm.dd.xxx` (xxx = build van de dag). `Tools\Version.targets` draait `Tools\NextVersion.ps1`
  vóór de resource-compiler: die verhoogt `BuildNumber.json` en schrijft `Source\Version.rc`. Laat "Include version
  information" uit in de projectopties, anders krijgt de exe twee versie-resources.
- **DCU-map:** `Tools\DcuOutput.props` zet de `.dcu`-bestanden in `$(DCUFolder)\<versie>\<project>\<platform>\<config>`
  als de IDE-variabele `DCUFolder` bestaat, anders in `.\Win64\<config>\dcu`.
- **Na de build** draait `Tools\afterbuild.cmd <config> <exe>`, als dat bestaat. In de repository is het leeg.
  Gebruik het voor een lokale kopie (bijvoorbeeld de Release-exe naar een share) en houd het buiten git met
  `git update-index --skip-worktree Tools/afterbuild.cmd`. Mislukt de kopie, dan faalt de build niet.
- Sla *Project Options > Appearance* in de IDE niet op: dat herschrijft de lijst met stijlen en laat de thema's uit
  `Styles\` vallen.
- Bronbestanden zijn UTF-8 met BOM en CRLF-regeleinden (behalve de Go-bronnen, zie hieronder).

## De Tailscale-bridge (tsbridge.dll)

### Waarom een DLL in Go

Voor de Tailscale-route is geen Tailscale-client op de pc nodig: RDCManagerX draait zelf een Tailscale-node in het
proces met [tsnet](https://pkg.go.dev/tailscale.com/tsnet). Die bibliotheek bestaat alleen in Go, dus
`Bridge\tsbridge` verpakt hem als C-DLL (`-buildmode=c-shared`, alleen amd64) met een kleine C-API. Hij stuurt een
lokale poort op `127.0.0.2` door naar een apparaat in het tailnet; de RDP-control verbindt met die poort.

### Hoe hij meegaat en geladen wordt

1. `Tools\build-tsbridge.cmd` bouwt `Bridge\bin\Win64\tsbridge.dll`, schrijft de SHA-256 naar
   `Source\RdcmX.TsBridgeHash.inc` en comprimeert hem tot `tsbridge.dll.gz`.
2. De exe bevat de gz als RCDATA `TSBRIDGE` (het testproject ook, via `Tests\TsBridgeTest.rc`).
3. Bij het eerste gebruik pakt de app hem uit naar `%LOCALAPPDATA%\RDCManagerX\bin\tsbridge-<hash>.dll` (tijdelijk
   bestand, dan hernoemen; oudere versies worden opgeruimd), opent hem zonder schrijf- of verwijderdeling,
   controleert de SHA-256 tegen de waarde in de exe en laadt hem pas daarna, met zijn imports alleen uit System32.
4. De DLL wordt nooit ontladen (de Go-runtime ondersteunt dat niet). Zonder DLL werkt de app gewoon; alleen de
   Tailscale-route is dan niet beschikbaar.

### Toolchain

De build is reproduceerbaar, dus de toolchain ligt vast. Het script weigert andere versies.

- **Go** `go1.27.4`: pak de Windows-zip uit naar `%LOCALAPPDATA%\Programs\go` (geen installatie nodig), of zorg dat
  `go` in `PATH` staat.
- **WinLibs** GCC 16.2.0, MinGW-w64 14.0.0 UCRT, POSIX threads, release 3:
  `winget install BrechtSanders.WinLibs.POSIX.UCRT --version 16.2.0-14.0.0-r3`, of `gcc` in `PATH`.

Met `TSBRIDGE_ALLOW_OTHER_TOOLCHAIN=1` bouwt hij toch met een andere versie, maar dan wijkt de hash van de DLL af van
de CI-build.

### Bouwen

```
Tools\build-tsbridge.cmd test
```

Dit controleert de toolchain, draait de Go-tests (forwarder met een lokale echo-server, versleutelde state, filteren
van secrets), bouwt de DLL en schrijft de hash-include en de gz. **Bouw daarna RDCManagerX en het testproject
opnieuw**: de exe laadt alleen de DLL waarvan hij de hash bevat. Commit de Go-wijzigingen, `tsbridge.dll.gz` en
`RdcmX.TsBridgeHash.inc` samen.

### Reproduceerbare build en CI

- Vlaggen: `-trimpath -buildvcs=false`, lege build-ID, geen PE-tijdstempel. Houd de uitvoernaam `tsbridge.dll`:
  GNU ld leidt de image base daarvan af.
- De Go-bronnen worden met LF uitgecheckt (`.gitattributes`): cgo verwerkt een hash van de bestandsinhoud in zijn
  exportsymbolen, dus CRLF zou een andere DLL geven.
- `.github/workflows/tsbridge.yml` bouwt de DLL opnieuw met dezelfde toolchain en faalt als de SHA-256 afwijkt van
  `cTsBridgeSha256` of van de gecommitte `tsbridge.dll.gz`. Zo is aangetoond dat de binary uit de broncode komt.
- Werk je Go of WinLibs bij, pas dan `PIN_GO`/`PIN_GCC`/`PIN_LD` in het script en `WINLIBS_URL`/`WINLIBS_SHA256` in
  de workflow samen aan.

### C-API

cdecl, UTF-8 invoer, int32-returncodes; tekst gaat naar een buffer van de aanroeper (de returnwaarde is het aantal
benodigde bytes).

```c
int TsNetCreate(const char* configJson);          // handle > 0, of foutcode < 0
int TsNetUp(int h, int timeoutMs);                // blokkeert; TsNetClose vanuit een andere thread breekt af
int TsNetGetStatus(int h, char* buf, int buflen); // JSON: state, ips, dnsName, authUrl, lastError
int TsNetAddForward(int h, const char* localAddr, const char* target); // lokale poort
int TsNetRemoveForward(int h, int localPort);
int TsNetClose(int h);
int TsLastError(int h, char* buf, int buflen);    // h = 0: laatste fout van TsNetCreate
int TsBridgeVersion(char* buf, int buflen);
```

## Teksten in de UI (Engels)

De Nederlandse teksten in de code en de DFM's zijn de bron; het Engels komt uit `Source\Lang\en.po`. Na het wijzigen
van zichtbare teksten:

```
python Tools\i18n.py update
rem vertaal de nieuwe regels (lege msgstr) in Source\Lang\en.po
python Tools\i18n.py check
```

`check` faalt bij ontbrekende vertalingen en bij `_()`-aanroepen met een niet-constant argument. Bouw daarna de exe
opnieuw.

## Handleiding

De bronnen zijn `Docs\RDCManagerX-Handleiding.html` (Nederlands) en `Docs\RDCManagerX-Manual.html` (Engels); houd ze
gelijk. Bouw de CHM's en PDF's met:

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\build-help.ps1
```

Bouw daarna de exe opnieuw. `hhc.exe` komt uit Microsofts HTML Help Workshop; die is zonder installatie uit te pakken
naar `%LOCALAPPDATA%\Programs\HTMLHelpWorkshop`. De melding "Itircl.dll not registered" gaat alleen over de
zoekindex en kan genegeerd worden. De PDF's worden met Microsoft Edge afgedrukt. De online handleiding wordt door
`.github/workflows/pages.yml` gepubliceerd als `Docs` verandert.

## Releasepakket

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\make-release-zip.ps1
```

Dit pakt de Release-exe en `LICENSE` in `Win64\Release\RDCManagerX-<versie>-win64.zip` en toont de SHA-256 van de zip
en de exe voor de release notes. Een release is altijd deze zip, nooit de losse exe; de tag is `v<versie>`.
