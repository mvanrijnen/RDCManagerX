# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

RDCManagerX: a Delphi 12 (VCL, Win64) RDP connection manager modelled on Microsoft's Remote Desktop Connection Manager (working title in the assignment: RDCManX, hence the `RdcmX.*` unit prefix). Its key feature is **dynamic resolution**: the remote desktop follows the panel size via `IMsRdpClient9.UpdateSessionDisplaySettings`, without reconnecting and without smart sizing. Source control is git, published on GitHub (`https://github.com/mvanrijnen/RDCManagerX`, public; the local folder name still says SVN). The UI is bilingual (English/Dutch, see "Language, GitHub and documentation"); the Dutch texts are the source.

Status:
- Phase 1 is built: tree, session tabs and dynamic resolution.
- The storage layer is built: reading and writing `.rdg` and `.rdcx` (tested). The File menu covers it in the UI.
- Phase 2 is built:
  - the properties dialog covers every settings section except encryptionSettings;
  - credential-profile management;
  - Wake-on-LAN.

Next: phase 4 (thumbnails, undock and fullscreen).

Where data is stored:
- Connection data goes in the `.rdg` (RDCMan-compatible).
- RDCManX extras (display mode, WOL) go in the sidecar `<file>.rdg.rdcx.json`, or inside a `.rdcx`.
- App settings (window layout, recent files, files open at exit) go in `%APPDATA%\RDCManagerX\settings.json`. `TRdcAppSettings.Save` writes **only keys changed in this session** (per-key snapshot at load, merged into the file as it is now on disk; `layouts` per monitor key; nothing changed means no write). This stops a second, older instance from reverting settings such as "Wachtwoorden onthouden" (user request). At startup, if the option is off but the vault exists, it is turned back on (`DropLegacyPasswords`).
- The debug log goes in `%LOCALAPPDATA%\RDCManagerX\debug.log`, only with `/debuglog`.

## Hard rules from the user

- **Passwords are stored ONLY in Windows Credential Manager, and only when "Wachtwoorden onthouden" is enabled in Options (off by default).** This revises the earlier rule "never store passwords" (user decision, 2026-11-24).
  - The "Wachtwoord onthouden" checkbox in the password prompt is **never checked by default**, also for a group connect. A password is stored only when the user ticks it.
  - `RdcmX.Credentials` is the only unit that writes passwords. It is a **vault with a master password** (`TRdcPasswordVault`, user decision "A"):
    - PBKDF2-HMAC-SHA256 (600000 iterations, random salt) derives an AES-256 key from the master password. Each password is sealed with AES-256-GCM (`RdcmX.Crypto`, CNG/bcrypt); the AAD is the lowercased target name, so an item cannot be moved to another account.
    - The result goes into Credential Manager (`CredWrite`, generic credential, persisted `LOCAL_MACHINE`, DPAPI on top). The item `RDCManagerX:vault` holds iterations, salt and an encrypted check text; the master password itself is never stored.
    - The key lives in memory protected by `CryptProtectMemory`. The vault auto-locks after `autoLockMinutes` (Options, default 15, 0 = never) and has File menu items "Wachtwoordkluis vergrendelen" and "Hoofdwachtwoord wijzigen..." (re-encrypts everything, two-phase, under the mutex `Global\RDCManagerX.VaultChange.<user SID>` so console and RDP sessions of the same user are serialized; every vault write takes that mutex and first checks that the store still uses its key, otherwise it locks).
    - Turning the option on asks for a new master password (`RdcmX.UI.MasterPassword`, at least 10 characters); cancelling leaves the option off. A forgotten master password can only be handled by emptying the vault.
    - Stored items without a vault (from before the vault existed) are wiped at startup, and the option is turned off (`DropLegacyPasswords`).
    - The store is behind `IRdcBlobStore`; the tests (`Tests\RdcmX.Tests.Vault.pas`) use an in-memory store and never touch Credential Manager.
  - Credentials are keyed per account: `RDCManagerX:account:<domain\user>`. Local accounts are keyed per server: `RDCManagerX:server:<host>:<user>`.
  - **An account password is bound to approved hosts** (security review 2026-11-25, user decision): the encrypted payload holds the password plus host keys (`DirectHostKey`, `TailnetHostKey` = hash of the control URL + tailnet MagicDNS suffix + the device's resolved MagicDNS name (`ts3:`; a device without suffix or name gets no vault host, and `LoadApproved` never releases a password without hosts); on the Tailscale route the credentials are asked in `FinishTailnetConnect` once the tunnel is ready and the target resolved (not before; `DeferTailnetCredentials` is off during a group connect with one typed password), `ViaGatewayHostKey` = gateway + server for every gateway in the path, whatever credSharing says). `TRdcSessionManager.CredentialContextFor` lists where a connection's password goes; `TRdcPasswordVault.LoadApproved` asks once for hosts not approved yet (`ConfirmHostApproval`, default No; No = normal prompt). Saving a typed password approves that connection's hosts. Group connect shows one check list of all new hosts (`ApproveGroupHosts` → `RdcmX.UI.HostApproval`, unchecked by default, hosts from AD marked); unchecked hosts go to the normal prompt without a second question (`FBatchDeclinedKeys`). Old items (plain payload) count as approved for nothing.
  - With a vault password `AuthenticationLevelFor(level, fromVault, route)` forces 1 (required) for routes Direct and Gateway (second security review, user decision), and at least 2 (warn) for Tailscale, because the connection goes to 127.0.0.2 and the certificate name never matches. Certificate pinning for Tailscale was rejected: the control does not expose the server certificate.
  - Prompts show the real host next to the caption (the caption comes from the file).
  - Passwords never go into `.rdg`/`.rdcx`/sidecar, `settings.json` or the log. The log contains only the target name.
  - Password strings are overwritten after use (`WipeString`).
  - A stored password rejected by the server is forgotten automatically: disconnect reason 2055/2567, marked ONZEKER.
  - Turning the option off deletes all stored passwords after confirmation (`DeleteAll`).
  - The server menu has "Onthouden wachtwoord vergeten" for the selected server's account.
- What still applies from the old rule:
  - The `.rdg` reader clears every `<password>` text and adds a warning to `TRdcFile.Warnings`.
  - Writers always emit an empty `<password />`.
  - The password is asked at every connect (`RdcmX.UI.CredentialPrompt`), handed to the control and cleared. `AllowCredentialSaving` is False.
  - User name and domain may be stored. The logon prompt has "Gebruikersnaam en domein onthouden" (user request, separate from the password, unchecked by default): `TfrmMain.RememberUserName` writes them into the server's (group connect: the group's) own logon section as custom credentials.
- Open sessions are shown as **tabs**. Double-click or Enter connects the server, or activates its tab if it is already open.
  - Selecting a server in the tree that has an open tab shows that tab (`ShowTabOfSelectedServer`, user decision 2026-11-24, replaces "the tree does not switch the session"). Keyboard focus stays in the tree and a detached window is not brought forward (`FSelectingFromTree`).
  - A session that ends normally closes its tab: user disconnect, or the server ending it (`TRdcSessionManager.EndedNormally`, queued via `CloseTabAfterDisconnect`). After an error the tab stays open with the message. A fallback reconnect (`ReconnectPending`) does not count as an end.
  - Logging off a session ("Afmelden") was removed at the user's request (2026-11-25): it was "not the right way". Do not reintroduce it without asking.

## Build and test

Delphi 12 is at `C:\Program Files (x86)\Embarcadero\Studio\23.0`. From cmd:

```
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild RDCManagerX.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:minimal
msbuild Tests\RDCManagerXTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:minimal
Tests\Win64\Debug\RDCManagerXTests.exe --exitbehavior:Continue
```

- The build must produce no warnings or hints.
- After every build the PostBuildEvent calls `Tools\afterbuild.cmd <Config> <exe path>` (if present). In the repository that file is empty and stays empty; locally the user fills it (Release: copy the exe to the deploy share) and marks it with `git update-index --skip-worktree Tools/afterbuild.cmd`, so never commit local content. The Release copy is what the user tests and distributes, so builds meant for the user are Release builds.
  - If the share is unreachable the script prints a warning and the build does not fail.
  - Use `$(MSBuildProjectDirectory)\$(Platform)\$(Config)` in build events, not `$(OUTPUTPATH)`: that macro is still empty at evaluation time in a command-line msbuild.
- DCU output for all builds: `$(DCUFolder)\$(ProductVersion)\$(ProjectName)\$(Platform)\$(Config)`, set by `Tools\DcuOutput.props` (imported by both dprojs). From the command line it reads DCUFolder from the IDE registry and ProductVersion from `$(BDS)`; without DCUFolder it falls back to `.\$(Platform)\$(Config)\dcu`.
- Version scheme `yyyy.mm.dd.xxx` (no semantic versioning; xxx = build number of the day, zero-padded, restarting at 001 each day).
  - `Tools\Version.targets`, imported by the dproj, runs `Tools\NextVersion.ps1` before `BrccCompile`. A PreBuildEvent is too late because it runs after the resource compile.
  - The script increments `BuildNumber.json` and generates `Source\Version.rc` (VERSIONINFO), which is linked via `{$R 'Version.res' 'Source\Version.rc'}`.
  - `VerInfo_IncludeVerInfo` is false, otherwise there are two version resources. Do not turn it back on in the project options.
  - The status bar shows the version far right (`AppVersionText`/`LayoutStatusBar`).
- App icon: `RDCManagerX.ico` (`Icon_MainIcon`). It is generated with System.Drawing: 16-128 px as DIB, 256 px as PNG, and simpler shapes at 24 px and below. `RDCManagerX.res` is regenerated on every build.
- Tests are DUnitX (console). Run a single test with `--run:RdcmX.Tests.Storage.TStorageTests.RoundTripIsByteIdentical`.
- Test data: `Samples\Voorbeeld.rdg` is a real RDCMan 2.90, schema 3 file, anonymised (root group CONTOSO, generic host and user names; keep it free of real names). The tests find it by walking up from the exe.
  - Its round-trip must stay **byte-identical**.
  - Optional: `Samples\password-test.rdg`.
- RDP behaviour has no automated tests; the user tests it against real servers. Start the app with `/debuglog` to write `%LOCALAPPDATA%\RDCManagerX\debug.log`.

## Language, GitHub and documentation

- **UI language** (`RdcmX.Lang`, user request: everything bilingual): gettext style. The Dutch texts in code and DFMs are the msgids; English comes from `Source\Lang\en.po`, embedded as RCDATA `LANG_EN` (`Source\Lang.rc`).
  - Every user-visible literal in code goes through `_('Dutch text')`; format strings too (`Format(_('%s is online (%d ms)'), [...])`). Build sentences as one `Format(_())`, not by concatenating fragments. The argument must be a constant (literals, `#nn`, `+`), otherwise the extractor cannot find it. Do not wrap log lines, keys, persisted or compared values.
  - Forms translate their DFM in `DoCreate` (`TranslateComponent(Self)`, before OnCreate). Only stored properties are translated, so action-linked controls keep following their action. The main form re-links `tbMenu.Menu` afterwards so the toolbar menu buttons pick up the translated captions.
  - The language (`language` in `settings.json`: system/en/nl, Options dialog) is applied once at startup in the dpr (`ApplyStartupLanguage`), like the theme; a change applies at the next start. `system` = Dutch when the Windows display language is Dutch, otherwise English.
  - After changing UI texts: `python Tools\i18n.py update`, translate the new entries in `en.po`, and `python Tools\i18n.py check` must pass (no missing translations, no non-constant `_()` arguments). New fields and hints need an English translation too.
  - The unit has no VCL dependency, so the console test project can use units that call `_`. Without a catalogue (tests, Dutch) `_` returns the source text.
- **Code comments and commit messages:** new ones in English (user decision 2026-11-25). Existing Dutch comments stay; translate them only in code you are changing anyway.
- **README:** `README.md` (English, what GitHub shows) and `README.nl.md` (Dutch), with a language switch at the top. Keep both in sync.
- **GitHub Pages:** `.github/workflows/pages.yml` publishes the manual (en/nl, HTML and PDF, landing page `Docs\site\index.html` with download button, features and the screenshots from `Docs\images`) to `https://mvanrijnen.github.io/RDCManagerX/` on changes in `Docs`. `Tools\site-layout.py` lays the manual pages out like a CHM viewer (contents tree from the h2/h3 headings, top bar with language switch and PDF); the app's own copy is unchanged. Help > Online manual opens the site in the UI language.
- **Security scans:** `.github/workflows/codacy.yml` (SARIF split per tool: code scanning accepts one run per category) and `devskim.yml`. Actions are pinned to commit SHAs with the version in a comment; `actions/checkout` always with `persist-credentials: false`.
- **Reproducible tsbridge build:** `.github/workflows/tsbridge.yml` rebuilds the DLL with the pinned toolchain and fails when its SHA-256 differs from `cTsBridgeSha256` or from the committed `tsbridge.dll.gz` (attests provenance on main).
- **GitHub releases** (user decision): never the bare exe, always a zip made with `Tools\make-release-zip.ps1` (`RDCManagerX-<version>-win64.zip` with the exe and LICENSE, in `Win64\Release`); tag `v<version>`; normal releases marked latest (no pre-release unless asked); publish with the `github` skill (command GITHUB); SHA-256 of zip and exe in the notes.
- **Public repo:** keep real names, hosts and company references out of everything committed (docs, samples, PDFs; `Samples/` is git-ignored). Test data with fake secrets must not look like real keys (build them from pieces), or GitHub secret scanning flags them.

## Architecture

### RDP

- **`Source\Imports\MSTSCLib_TLB.pas`**: generated with `tlibimp -P -Hr- C:\Windows\System32\mstscax.dll`.
  - Hand patch after regenerating: `property ConnectWithEndpoint: POleVariant1` must become `OleVariant` (a tlibimp bug).
  - `TRdpSession.CreateControl` probes each CLSID with `CoCreateInstance` (12 → 9) before it constructs the `TOleControl`. The typelib lists classes that the DLL may not be able to create.
- **`RdcmX.Rdp.Host`**: `TRdpHost` is the fixed window that holds one session's control and paints the status text.
- **`RdcmX.Rdp.Session`**: `TRdpSession` owns the control.
  - State machine and the resize debounce, starting only after `OnLoginComplete`.
  - DPI scale factors, verification through `OnRemoteDesktopSizeChange`, and the reconnect fallback.
  - The unit header lists the known uncertainties about ActiveX behaviour.
  - It hooks `WindowProc` so that `CN_KEY*` messages only reach the control's `TranslateAccelerator`. Otherwise VCL shortcuts, dialog keys and Alt would steal keys from the remote session. For the same reason the main form actions have no `ShortCut`; keys are handled in `tvServersKeyDown`.
- **`RdcmX.Sessions`**: `TRdcSessionManager` maps server to session.
  - All hosts live permanently in `pnlSession`; only `Visible` is toggled.
  - It frees sessions with a delay through a posted message, never inside their own events.
  - `BuildSettings` maps the effective model settings to `TRdpConnectionSettings`.

### Tailscale and gateway routes

User docs: `README.md`. Manual test plan: `TESTPLAN.md`.

- **Connecting** (`TRdcSessionManager.BuildSettings`/`Connect`):
  - Route `Gateway`: `ApplyGatewayRoute` maps the `TRdcGatewayDef` (password from the vault for "own credentials"). `TRdpSession.ApplyGatewaySettings` raises when `GatewayIsSupported = 0`, so it never silently connects directly.
  - Route `Tailscale`: `ConnectViaTailnet` calls `TRdpSession.BeginPrepare` (state connecting, status text), `TRdcTailnetManager.Acquire`, then `TunnelReady` (forward on `127.0.0.2:0`, `SetEndpoint`, `Connect`), or `PrepareFailed` (error stays in the tab).
  - One `TRdcTunnel` per session: it lives until the session is released (tab closed), so reconnects reuse the forward. `ReleaseTunnel` removes the forward and releases the network.
  - `TunnelTimerFired` opens the Tailscale login URL in the browser for an interactive login while the network starts.
  - `DisplayName` keeps status texts on the real server name.
- **Certificates and NLA via 127.0.0.2**: there is no ActiveX property for the expected server name (`AuthenticationServiceClass` is only the SPN class). Expect a certificate-name warning; Kerberos falls back to NTLM. This is documented in the README.
- **Management screens**: `RdcmX.UI.Tailnets` (with "Test verbinding" through the same manager) and `RdcmX.UI.Gateways` (File menu, per selected file). They reach the vault through `IRdcSecretAccess`, which `TfrmMain` implements. Route tab: `TfrmProperties.BuildRoutePage`.

- **Route per server/group**: section `rdcmxRoute` (`TRdcxRouteSettings`, inheritable, never in the `.rdg`): `Direct` (default; existing `gatewaySettings` from the `.rdg` keep applying), `Tailscale` (tailnetId, optional tailnetHost; empty = server host name) or `Gateway` (gatewayId).
- **Definitions per file** (user decision: bound to the file, secrets are not): `TRdcFile.Tailnets` (`TRdcTailnetDef`) and `TRdcFile.Gateways` (`TRdcGatewayDef`), stored as `tailnets`/`gateways` at the top level of the `.rdcx` or the sidecar. A gateway's `TailnetId` is reserved for "gateway via tailnet" (not built).
- **Secrets only in the vault**, keyed by id: `TailnetAuthKeyTarget`, `TailnetStateKeyTarget` (random 32 bytes, base64), `GatewayTarget`. Emptying the vault or turning the option off therefore also drops them.
- **`Bridge\tsbridge`** (Go, `tailscale.com/tsnet`, c-shared, amd64 only): build with `Tools\build-tsbridge.cmd [test]` → `Bridge\bin\Win64\tsbridge.dll`. The script also writes `tsbridge.dll.gz`, which is embedded in the exe as RCDATA `TSBRIDGE` (`Source\TsBridge.rc`; the test project embeds it too via `Tests\TsBridgeTest.rc`). The user's launcher copies only the exe. At first use `TRdcTsBridge` extracts it to `%LOCALAPPDATA%\RDCManagerX\bin\tsbridge-<hash16>.dll` (temp file + `MoveFileEx`; re-extracted when the hash differs; old versions cleaned up), then verifies the hash under lock and loads it. Without the resource it falls back to next to the exe. Loading from memory was rejected: an unreliable manual loader for a Go DLL, and it looks like malware to EDR. Separate DLL copies (post-build, Win64\Debug) are gone. Needs Go (`%LOCALAPPDATA%\Programs\go`) and mingw-w64 (winget WinLibs), in exactly the versions pinned in the script (`PIN_GO`/`PIN_GCC`/`PIN_LD`; it refuses others unless `TSBRIDGE_ALLOW_OTHER_TOOLCHAIN=1`). The build is reproducible (`-trimpath -buildvcs=false`, empty build ID, no PE timestamp; GNU ld derives the image base from the output name, so keep `tsbridge.dll`). When bumping Go or WinLibs, update the script's pins and the workflow's WinLibs URL/SHA-256 together. C API: `TsNetCreate/Up/GetStatus/AddForward/RemoveForward/Close`, `TsLastError`, `TsBridgeVersion`; text goes into caller buffers (return = bytes needed). Non-ephemeral state is AES-256-GCM with the state key from the vault plus DPAPI on top; a non-ephemeral network without a state key is refused. `TS_NO_LOGS_NO_SUPPORT` is set (no log upload); debug logging only to a file and always redacted.
- **Security rules (user request: "100% veilig")**:
  - Forwards bind loopback only, with `SO_EXCLUSIVEADDRUSE`, and accept only connections whose client side belongs to our own PID (`GetExtendedTcpTable`; mstscax runs in-process).
  - Targets are resolved only against tailnet peers (`resolveInTailnet`: MagicDNS name (FQDN or first label)/Tailscale IP/approved subnet route, never exit-node 0/0, never system DNS). The self-chosen `HostName` only matches with the opt-in `matchHostName`, and shared-in peers (other MagicDNS domain or `AltSharerUserID`) are skipped unless `allowShared`. Both opt-ins live in `settings.json` (`tailnetHostNameMatch`/`tailnetAllowShared`, keyed by `TailnetBindingKey`), never in the file: a file must not loosen this. `TsNetResolvedTarget` gives what the last check resolved to; the session status shows it. tsnet's `Dial` would otherwise `SystemDial` non-tailnet addresses.
  - Control URL must be https (http only to localhost), checked in Go and Delphi. Login URLs open only when they are https (`RdcOpenAuthUrl`).
  - Secrets are bound to their server: the vault target contains a hash of the normalized control URL or the gateway `host:port`.
  - Values from files (localAddress, nodeHostName, controlUrl) are re-validated at use.
  - `tsbridge.dll` is pinned by SHA-256: `Tools\build-tsbridge.cmd` writes `Source\RdcmX.TsBridgeHash.inc`, so **rebuild the exe after rebuilding the DLL**. The file is hashed and loaded while held open without write/delete sharing, with `LOAD_LIBRARY_SEARCH_SYSTEM32`, so its imports come only from System32 (not from the user-writable extraction folder).
- **`RdcmX.Tailscale`**: `TRdcTsBridge` loads the DLL lazily from the exe folder only and never calls `FreeLibrary`. `TRdcTailnetManager` refcounts nodes per id, runs `Up` in a background thread, and a `Release` during startup aborts it (orphan flag; the Up thread finishes the cleanup).

### Reachability (ping)

- **Setting:** `rdcmxRoute.ping` (route tab, inherits from file/group; default off). It applies only to route Direct, because Tailscale and gateway targets are not directly reachable from this PC.
- **`RdcmX.Ping`:** `RdcCheckHost` tries ICMP echo (`IcmpSendEcho`, no admin needed) and, if that fails, a TCP connect to the RDP port, because Windows often blocks ICMP. It is IPv4 only.
- **`TRdcPinger`:** a thread that runs a round every 30 s with `TParallel.For` and delivers results via `TThread.Queue(Self, ...)`. `Destroy` calls `RemoveQueuedEvents`.
- **Main form:**
  - `UpdatePingTargets` runs on open/close/`MarkModified`, and only pushes when the target set changed.
  - `PingResultsArrived` updates the icons.
  - A server not in a session has a tinted server icon (`TintedPixels`; user request): blue `ciServer` means no ping or no result yet, green `ciServerOnline` means reachable, red `ciServerOffline` means not reachable. Orange `ciServerWrongHost` means reachable by name, but the NetBIOS node status (UDP 137, `RdcNetBiosName`, like `nbtstat -A`) on that address returns a different computer name. That points to a stale DNS A record (typical when DHCP hands the address to another device and DNS scavenging is off). With no NetBIOS answer the identity is not checked, and servers entered by IP are skipped. Sessions keep the untinted icon with a coloured dot.
  - The status bar shows "online (n ms)" or "niet bereikbaar (sinds hh:nn)" for the selected server.


### Help and hints

- **Help > Manual (F1):** `ShowManual` extracts the embedded CHM in the UI language (`HELPCHM` = Dutch, `HELPCHM_EN` = English, `Source\HelpChm.rc`) to `%LOCALAPPDATA%\RDCManagerX\help` and opens it. A CHM opened from a network share is blocked by Windows, but locally it works. Without a CHM it falls back to the embedded HTML (`HELPHTML`/`HELPHTML_EN`, `Source\Help.rc`) in the browser.
- **Building the manual:**
  - The sources are `Docs\RDCManagerX-Handleiding.html` (Dutch) and `Docs\RDCManagerX-Manual.html` (English). **Keep both in sync**: every change goes into both.
  - `Tools\build-help.ps1` builds both languages: `Docs\help` (IE-compatible HTML without CSS variables, `.hhp`, `.hhc` table of contents from the h2 ids, CHM via `hhc.exe`), the PDFs via Edge (`--print-to-pdf`, no header/footer so no local path ends up in them), and rewrites `HelpChm.rc` (empty when no compiler is found).
  - `hhc.exe` comes from Microsoft's HTML Help Workshop (`htmlhelp.exe`, Microsoft-signed, link from the user). It is extracted without installing, from the installer's `CABINET` resource, to `%LOCALAPPDATA%\Programs\HTMLHelpWorkshop`. The "Itircl.dll not registered" message only concerns the full-text index and can be ignored.
  - After changing the manual: run `build-help.ps1`, then rebuild the exe.
- **Hints (user request: clear explanations everywhere):**
  - DFM controls and their labels have `Hint`, and each form has `ShowHint = True`.
  - Generic section pages get their hints via `TRdcSectionPage.SetHint` (`TfrmProperties.ApplyFieldHints`, keyed by element name); the inherit checkbox also has one.
  - Tree tooltips (`UpdateTreeHint`/`ServerHint`):
    - for a server: session state, reachability, last seen, last check and the comment;
    - for groups: the number of servers reachable.
  - New fields need a hint too.

### Model and storage

- **`RdcmX.XmlTree`**: a lightweight element tree plus a writer that copies RDCMan's .NET XmlWriter output:
  - UTF-8 BOM, CRLF, 2-space indent;
  - `<x />` for empty elements;
  - no trailing newline;
  - escaping of `& < >`.
- **`RdcmX.Model`**: `TRdcFile` > `TRdcGroup` > `TRdcServer`.
  - **Server fields**: `Name` = host name, `DisplayName` is optional, and `Caption` is the display name with fallback to `Name`.
  - **Properties and settings sections are stored as XML elements with typed accessors.** This keeps unknown elements, unknown enum values and partial sections intact on round-trip.
  - **Sections**, in rdg order: logonCredentials, connectionSettings, gatewaySettings, remoteDesktop, localResources, securitySettings, displaySettings, encryptionSettings, plus `rdcmx` (RDCManX extras, never written to `.rdg`).
  - **Inheritance:**
    - A missing section means inherit.
    - A missing child element inside an own section means the RDCMan default; it does not inherit.
    - `Effective*` falls back to `AppDefaults`.
  - **`ResolveLogon`/`SplitLogon`** handle `DOMAIN\user`, `.\user`, UPNs and `scope="File"` profile references.
  - **Paths** use the `<favorites>` format (`root name\group\...\caption`). `Path(True)` adds `#n` for duplicate captions. `FindByPath` resolves both forms.
  - Defaults and enum values marked `ONZEKER` are not confirmed; verify them against a reference file from RDCMan.
- **Storage units:**
  - `RdcmX.Storage.Rdg`: bytes ↔ model, read through MSXML (`Xml.XMLDoc`) and written through `TRdcXmlWriter`. Unknown elements are kept with an anchor (the preceding known element).
  - `RdcmX.Storage.Sidecar`: `<file>.rdg.rdcx.json` with the RDCManX extras.
  - `RdcmX.Storage.Json`: `.rdcx` with `formatVersion` 1.
  - `RdcmX.Storage`: `IRdcFileStorage`/`TRdcStorage` handles the choice by extension, atomic save (`.tmp` + `MoveFileEx`), a one-time `.bak`, and detection of external changes by timestamp plus SHA-256, with a callback.

### UI

- **`RdcmX.UI.Main`**:
  - Left side: `pnlLeft` with the search box (`sbSearch`, Ctrl+F) and the tree. Right side: `pnlSession`, the session area, managed by `RdcmX.UI.SessionPanes`.
  - The search box filters the tree on caption or host name, keeping the groups above each match.
  - While a filter is active, every group is expanded but the expand state is not written to the model (`FFilter`).
  - The tree has no lines and uses hover highlighting and full-row selection. Its item height (26 px at 96 DPI) is set in `RebuildImages`, because a handle recreate resets it.
  - The File menu covers new, open (also from the command line), recent files, save, save as (converts between `.rdg` and `.rdcx`), save all and close.
  - Each open file is a root node; `*` marks unsaved changes. Every model change in the UI must call `MarkModified`.
  - Files that were open at exit are reopened at startup. Recent and open files are kept in `%APPDATA%\RDCManagerX\settings.json` (`RdcmX.AppSettings`).
  - Window layout is stored per monitor configuration (`MonitorConfigKey`) and restored with `SetWindowPlacement`, called twice to handle DPI changes. It covers position, size, maximized and the tree width in 96-DPI units.
  - The tree is sorted alphabetically with groups first (`CompareTreeNodes`). This is display only; the model and file order stay unchanged.
- **Local resources**: `RdcmX.Sessions.BuildSettings` maps the effective `localResources` to `TRdpConnectionSettings`, and `TRdpSession.ApplyConnectSettings` sets them on the control. This covers clipboard, drives, printers, ports, smart cards, PnP devices, audio and the keyboard hook. The enum order matches the control values.
- **`RdcmX.UI.Properties`**: the properties dialog.
  - The DFM holds the General tab (with Wake-on-LAN for servers) and the Logon tab (custom credentials or a file profile).
  - Every other section is a generic tab built in `BuildSectionPages` with **`RdcmX.UI.SectionPage`**. Each field maps to one XML element (text, number, bool or choice).
  - One tab can cover several sections (`AddSection`/`UseSection`), all under a single inherit checkbox.
    - **Weergave** = `rdcmx` (mode, scale, wait time, fallback) + `remoteDesktop` (fixed size, colour depth) + `displaySettings` (smart sizing).
    - Thumbnail settings are not shown, but they are kept for RDCMan.
    - `sameSizeAsClientArea`/`fullScreen` are derived from the display mode on save, but only when the mode changed.
  - A section that inherited when the dialog opened and was not touched keeps inheriting.
  - Saving writes only fields whose value actually changed. Unknown enum values and missing elements therefore survive an unchanged OK.
  - Unchecking "inherit" on an empty section copies the inherited values as the starting point.
  - Choosing a display mode on the "Dynamische resolutie" tab also sets `sameSizeAsClientArea`/`fullScreen` on the Remote desktop tab, if that tab has own settings.
- **`RdcmX.UI.Profiles`**: manages the `<credentialsProfiles>` of a file (File > Credential-profielen).
  - Renaming a profile updates every reference (`TRdcFile.RenameProfileReferences`, scope="File" in logon and gateway sections).
  - A profile that is still referenced cannot be deleted.
- **`RdcmX.WakeOnLan`**: sends the magic packet as a UDP broadcast.
  - The MAC address, broadcast address and port live in the `rdcmxHost` section (`TRdcxHostSettings`, never in the `.rdg`). This section does **not** inherit: read it from the server's own `Settings.Host`, never through `Effective`.
- **`RdcmX.UI.CredentialPrompt`**, **`RdcmX.UI.Icons`**.
- **Connect settings**: `BuildSettings` also maps:
  - connection: console/admin session, start program, load-balance info;
  - gateway: host, bypass local, cred sharing, creds source, user/domain. For route Direct (the `.rdg` gatewaySettings) it never passes a gateway password, so Windows prompts for it when needed. Only route Gateway with "own credentials" passes a password, and that one comes from the vault.
  - `TRdpSession.ApplyConnectionOptions`/`ApplyGatewaySettings` set these on the control.

### Critical pitfalls

- **Never change the VCL `Parent`** of the RDP `TOleControl` or its `TRdpHost`, and never recreate a window handle that contains them. Doing so recreates the window handle and kills the session.
  - The tab strips (`RdcmX.UI.TabStrip`) deliberately do not contain the hosts.
  - Undock and fullscreen (phase 4) must move the host with `Winapi.Windows.SetParent`.
- **Never call Connect/Disconnect/Reconnect, or free a session, synchronously inside RDP event handlers.** Use the posted messages instead.
- **Source files must be UTF-8 with BOM.** Without a BOM the compiler reads them as ANSI and non-ASCII literals (`·`, `ë`) show up garbled (`Â·`).
- **Split session area** (`RdcmX.UI.SessionPanes`, View menu):
  - Modes: one pane; two side by side or stacked, with a draggable splitter; or a grid of 4 (2x2) or 8 (4x2) equal panes.
  - Each pane has its own tab strip: **`RdcmX.UI.TabStrip`**, a custom-painted flat tab bar with close buttons that replaces TTabControl.
    - It takes its colours from `TStyleManager.ActiveStyle`, not from `StyleServices(Self)`. The control has `StyleElements = []` and would otherwise get system colours.
    - The accent line under the selected tab marks the active pane.
  - Every control lives in `pnlSession`: the tab strips, the splitter, the placeholders and all RDP hosts. Hosts use `Align = alNone`. `TRdcSessionManager.ShowServers(servers, rects)` positions them; their VCL Parent never changes.
  - `OnPlaceHost` sets the host's position before Connect, because the initial resolution follows the host size.
  - A click inside a session activates its pane: `TRdpHost.OnActivated` via `WM_PARENTNOTIFY`.
  - Clicking an empty pane makes it active.
  - A tab moves by dragging it to another tab strip or empty pane, or through the tab menu ("volgend vak").
  - Dragging within its own strip reorders it live (`ReorderDraggedTab`; it moves only once the cursor would be on the dragged tab after the move, so tabs of different widths do not flip back and forth). Tab widths fit the caption (`TRdcTabStrip.TabWidths`), and the caption is the host without domain unless a display name is set (`TabCaptionOf`).
  - The session area colours follow the theme: `TRdcSessionPanes.ApplyColors(RdcActiveStyleIsDark)`.
  - `settings.json` stores `splitMode` and `splitRatio`.
- **Theme** (`RdcmX.UI.Theme`, View > Thema): System/Light/Dark, stored as `theme` in `settings.json`.
  - Styles are `.vsf` files in the project folder `Styles\`, embedded via `Custom_Styles` in the dproj.
    - Light is "Windows11 Modern Light" (taken from the Delphi Skia4Delphi sample).
    - Dark is "Windows11 Modern Dark" (from GetIt, `Styles\Windows11ModernDark.vsf`). "Windows10 Dark" is only the fallback. `RdcmX.UI.Theme` picks the first available style.
    - Light and Dark are the same Embarcadero pair (version 2.0), so they differ only in colour.
    - `Vcl.Styles` must be in a uses clause, otherwise the embedded styles are not registered.
    - **Do not save Project Options > Appearance.** The IDE rewrites `Custom_Styles` to its own list, which drops the Styles\ entries.
  - **`TStyleManager.SetStyle` recreates every window handle** (tested), which would kill RDP sessions. The theme is therefore set in the dpr before `CreateForm` (`ApplyStartupTheme`).
  - At runtime the theme only switches when no tabs are open; otherwise it applies at the next start. The same applies to System when Windows switches (`WM_SETTINGCHANGE` "ImmersiveColorSet").
  - The RDP host, `pnlSession` and the placeholder have `StyleElements = []`.
- **UI tests via scripts**:
  - The main menu is not the form's menu (`Form.Menu` is empty). It is a toolbar menu (`tbMenu.Menu = mmMain`) above the tree, so the session area starts directly under the title bar. Script tests therefore click the `TToolBar` buttons.
  - With a VCL style active the menu bar is drawn by the style, so `GetMenu` finds nothing. VCL also adds `&` accelerators automatically (e.g. `B&eeld`).
  - Menu commands work via `WM_COMMAND` with the item IDs. Those IDs are the same for every run of the same build.
  - Keystrokes via SendKeys often do not arrive, because a background process does not get the focus.
- **Connected** (user request): a third shortcut section at the very top with every server whose session is connecting or connected (`TRdcSessionManager.ConnectedServers`); `UpdateConnectedSection` (queued from `SessionsStateChanged`) rebuilds the sections only when that set changes. Delete is disabled there (the entry is the server itself).
- **Favorites and Recent** (`RdcmX.Shortcuts`; settings `favorites`, `recentServers`, `recentServerCount`) are client settings and are never written to the file.
  - Favorites are stored per file; Recent holds the last N connected servers (N is set in Options; a group connect does not add to it).
  - Entries are stored as file plus `Path(True)`. While a file is open, an entry points to the server object itself, so renaming or moving a server does not break it; paths are refreshed when saving or closing.
  - In the tree they appear as extra root nodes with `TRdcTreeShortcut` as `Data` instead of a `TRdcNode`. Always go through `NodeOfTreeNode`/`SelectedNode`, which map a shortcut to the real server.
  - Shortcut nodes cannot be renamed or dragged. Delete only removes the entry from its list.
- **Connect a group**: the credentials are asked once and reused for every server in the group, including subgroups (`FBatch*`). The password is kept only during the loop. The sessions are spread over the panes.
- **Detach / fullscreen** (`RdcmX.UI.SessionWindow`, tab menu):
  - `TRdcSessionManager.Detach` moves the host with `Winapi.Windows.SetParent` into a separate window. The VCL Parent stays `pnlSession`, and `ShowServers` skips detached hosts.
  - Switching between window and fullscreen moves the host to a **new** window. Never change the border style of an existing window: that recreates its handle and would destroy the host along with it.
  - Closing a session window re-docks the session; it does not disconnect.
  - **Flicker:**
    - The buttons are TSpeedButtons, because a TButton cancels its click when the RDP control takes the focus back.
    - The host area (`TRdcHostArea`) uses `WS_CLIPCHILDREN` and fills only the area the session does not cover.
    - While the window border is dragged (`WM_ENTERSIZEMOVE`..`WM_EXITSIZEMOVE`) the session keeps its size and gets one new size on release.
    - On detach the host is placed in the window before it is shown.
  - Before a session is freed, and in `FinalizeForm`, every host is re-attached first (`Reattach`/`DockAllServers`).
- **Desktop scale**: `rdcmx` element `desktopScale`, where 0 means automatic (it follows the monitor DPI).
  - It can be set per server or group under Properties > Dynamische resolutie.
  - For one open session it can also be changed through the tab menu "Schaal" (`TRdpSession.SetDesktopScale`).
  - In dynamic mode the change is applied immediately via `UpdateSessionDisplaySettings`; in the other modes it takes effect at the next connect.
  - `EffectiveDesktopScale` replaces `DesktopScaleFromDpi` wherever a scale is sent.
- **Experience tab** (`rdcmxExperience`, `TRdcxExperienceSettings`, inherits, never in the `.rdg`; user request): connection speed (`NetworkConnectionType`, Auto = 7 with `BandwidthDetection`), the six mstsc "allow" options (`PerformanceFlags`, computed in the model; `PresetFor` sets the check boxes per speed like mstsc), persistent bitmap caching, `EnableAutoReconnect`, and *Keep session active*: `TRdcSessionManager.PulseIdleSessions` (every 2 min) calls `TRdpSession.KeepAlivePulse` (a 1-pixel mouse move posted to the control's `IHWindowClass` input window, ONZEKER) for logged-in sessions without the keyboard focus, or all when this PC has been idle for a minute; `keepAliveInterval` (60 s) is set for every session, so a connection that died on the way is detected and auto-reconnect starts. Pulses are logged (debug log). A session that stays black after idle while connected was traced to the target PC (screen saver + WDDM display driver for RDP); `Toolsdp-check.ps1` (read only) and `Toolsdp-blackscreen-fix.ps1` (backup, `-Undo`) are run on the target and documented under Troubleshooting. Whether the posted mouse pulse counts as input on the server is not confirmed yet.
- **Active Directory link** (user request): section `rdcmxAd` (`TRdcxAdSettings`) on a group, does **not** inherit (no inherit box: `TRdcSectionPage.HideInherit`; empty OU = no own section, like Wake-on-LAN; read `Settings.Ad.IsLinked`, never Effective). `RdcmX.AdLdap` queries OUs and computers via ADSI/ADO (`ADsDSOObject`, late bound, current Windows account, secure + signing + sealing) in a background thread (`TfrmMain.RefreshAdGroup`, result via `TThread.Queue` behind `FAdGuard`, group found back by path). `RdcmX.AdSync` turns the result into normal groups/servers marked with their DN (`rdcmxAdItem`), matched on DN at the next refresh; gone = removed unless busy (open session) or a group that still holds other nodes; manual nodes are never touched; a nested linked group is skipped; only OUs holding an included computer (after the disabled/name filters, at any depth) become groups. `dNSHostName` is validated (`RdcAdCheckHostName`: host name characters, no port, dotted names must end with the OU's DC= domain or a configured `dnsSuffixes` entry); invalid ones are skipped. The result lists added/renamed/removed/skipped names; a manual refresh shows them (`ShowAdSyncSummary`). Name filter validated (`RdcAdIsValidNameFilter`), at most 5000 entries, 60 s timeouts; the query question shows the real target (`RdcAdTargetOf`: an empty server means the domain of the OU's DC= parts) and warns for IP addresses or servers outside this PC's domain. The first query per server + OU asks once per PC (`adApprovals` in `settings.json`); refresh on open only for approved ones.
- **Redirection warning** (`RdcmX.Redirections`, security review point 10): opening a file whose effective settings share drives, ports, printers, PnP devices or the microphone, set a start program, the keyboard hook "Remote" or keep session active shows one warning per fingerprint (file name + findings; `acceptedRedirections` in `settings.json`, newest 200). Saving a file accepts its fingerprint. Smart cards are left out (on by default in RDCMan).
- **Options dialog** (`RdcmX.UI.Options`, File > Opties...): app settings such as the number of recent servers, the theme and automatic saving.
- **Automatic saving** (setting `autoSave`, off by default):
  - `MarkModified` → `ScheduleAutoSave`. The modified files that have a file name are saved after 2 seconds of quiet.
  - A new file without a name is still asked about when closing.
  - Saving is postponed while the tree is in rename mode.
  - With the setting off, unsaved changes are asked about when closing, as before.
- **Do not use `RightClickSelect` on the tree.** The VCL only marks the node temporarily, and the popup action then runs on the previous selection. `tvServersContextPopup` → `SelectNodeForContextMenu` really selects the clicked node.
- **Line endings must be CRLF.** RAD Studio warns about LF-only files. When patching files with scripts, write `\r\n`.
- **In `.pas` patches written from Python, escape backslashes in Delphi strings (or use raw strings).** `\100` or `\b` otherwise silently becomes another character.
- **Units: `initialization` comes after all method implementations.** Methods added after it produce misleading parse errors.
- **The UI cannot be driven fully through UI Automation.** VCL TTreeView items and TPageControl tabs are not exposed. Use focus plus type-ahead, Alt+Enter and Ctrl+Tab, and take screenshots with PrintWindow.
- **DLL planting:** `RdcmX.DllSearch` must stay the first unit in the dpr uses clause (its initialization restricts DLL loading by name to System32). Declare new imports of non-KnownDLLs `delayed` (with `{$WARN SYMBOL_PLATFORM OFF}`); `version.dll`, `winspool.drv` and `wtsapi32.dll` are static RTL/VCL imports that cannot be delayed; therefore the app warns at startup when it runs from the Downloads folder (`WarnIfStartedFromDownloads`), and README/manual say to use a folder of its own.
- **Delphi `{ }` comments end at the first `}`.** Unit headers that contain JSON examples must use `(* *)`.

## Coding style (mandatory)

- Uses clauses grouped in this order: `Winapi.*`, `System.*`, `Xml.*` (right after System), `Data.*`, `FireDAC.*`, `Vcl.*`, `FMX.*`, third-party, own shared libraries, project units. Sort each group alphabetically (case-insensitive).
- Always use full namespaced unit names.
- Do not wrap lines at 80 chars; long lines are fine.
- Prefix locals with `l`, fields with `F` and parameters with `a`.
- Keep event handlers thin: click events, `OnExecute` of actions, form events and other handlers contain hardly any code. They only call a named procedure or function (for example `actDeleteExecute` → `DeleteSelectedNode`).
- Access ActiveX interfaces only through `Supports(...)`.
- No modal dialogs from RDP events.
- Never log passwords or other secrets.
