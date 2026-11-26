---
name: github
description: Publish a GitHub release of RDCManagerX (Release build, tests, zip, release notes, gh release create). Use when the user types the command GITHUB (or /github), or asks to make or publish a GitHub release.
---

# GITHUB: publish a GitHub release

The user starts a release with the command **GITHUB**. Follow these steps in order. Stop and report when a step
fails; never publish a release from a broken or dirty state.

## 1. Preconditions

- `git status --short` is empty and `main` equals `origin/main` after `git fetch` (everything committed and pushed).
  If not: say what is pending and ask whether to commit/push first.
- The GitHub CLI is available and logged in: `gh auth status`. If `gh` is missing, ask the user to run
  `winget install GitHub.cli` and then `! gh auth login`; do not work around it.
- Find the previous release tag: `git describe --tags --abbrev=0 --match "v*"` (none = first release).

## 2. Build and test (no warnings, no hints)

From cmd, as in CLAUDE.md:

```
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild RDCManagerX.dproj /t:Build /p:Config=Release /p:Platform=Win64 /nologo /v:minimal
msbuild Tests\RDCManagerXTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:minimal
Tests\Win64\Debug\RDCManagerXTests.exe --exitbehavior:Continue
```

- Look at the full msbuild output (do not filter it away): any error, warning or hint stops the release.
- All tests must pass (check the test exe timestamp: it must be freshly built).
- Also run `python Tools\i18n.py check` (all UI texts translated).
- The Release build also runs `Tools\afterbuild.cmd` (local deploy copy); that is expected.

## 3. Zip (never the bare exe)

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\make-release-zip.ps1
```

It prints the zip path (`Win64\Release\RDCManagerX-<version>-win64.zip`, exe + LICENSE), the version and the
SHA-256 of zip and exe. The version (`yyyy.mm.dd.xxx`) comes from the exe; the tag is `v<version>`.
It also writes `Win64\Release\version.json`: the asset the update check downloads first (its download count
is the number of update checks, `.github/workflows/stats.yml` records it per day). Always upload it with the zip.

## 4. Privacy check of the binary

The repo is public. Scan the exe (ANSI and UTF-16) for the user's name, company, local paths and e-mail address
(e.g. the words in CLAUDE.md "Public repo", `D:\Data`, `C:\Users\`); also the embedded `tsbridge.dll`
(`Bridge\bin\Win64\tsbridge.dll.gz`, decompressed). Report hits with context; real hits stop the release
(substrings of unrelated words are false positives).

## 5. Release notes

Write them to the scratchpad (not the repo), in English with a short Dutch paragraph at the end:

- Title: `RDCManagerX <version>` (first release: add "first public release").
- Download line: the zip name, "unzip and run RDCManagerX.exe, no installation (Windows 10/11, 64-bit)".
- Manual: https://mvanrijnen.github.io/RDCManagerX/ (English / Dutch).
- Changes since the previous tag, grouped (new, improved, fixed), written for users from
  `git log <previous tag>..HEAD`; skip pure tooling/docs-internal commits. First release: highlights instead.
- Notes that still apply (check README/CLAUDE.md): RD Gateway route not tested yet (until the user says it is),
  Tailscale needs an ACL, exe not code-signed (SmartScreen).
- SHA-256 of the zip and of the exe.

## 6. Confirm, then publish

Publishing is outward-facing: show the user the version, tag and the notes, and wait for an
explicit go. Then:

```
gh release create v<version> "Win64\Release\RDCManagerX-<version>-win64.zip" "Win64\Release\version.json" --target main --title "RDCManagerX <version>" --notes-file <notes file> --latest
```

- Normal releases marked latest (user decision 2026-11-25, after the first release); `--prerelease` only when the
  user asks for it.
- `gh` may not be on the PATH of this session: use `C:\Program Files\GitHub CLI\gh.exe`.
- Afterwards `gh release view v<version>` and report the URL. `git fetch --tags` so the local tag exists.

Versioning stays date based (`yyyy.mm.dd.xxx`, user decision: it is an app, not an API or library).
