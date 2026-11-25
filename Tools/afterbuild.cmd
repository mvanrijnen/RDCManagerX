@echo off
rem Wordt na elke build van RDCManagerX aangeroepen (PostBuildEvent in RDCManagerX.dproj):
rem   %1 = configuratie (Debug of Release)
rem   %2 = volledig pad van de gebouwde RDCManagerX.exe
rem
rem In de repository is dit bestand leeg en blijft het leeg. Vul het lokaal, bijvoorbeeld om de exe naar een
rem netwerkshare te kopieren. Zodat lokale aanpassingen niet worden gecommit:
rem   git update-index --skip-worktree Tools/afterbuild.cmd
rem
rem Voorbeeld:
rem   if /i "%~1"=="Release" copy /Y "%~2" "\\server\share\RDCManagerX\"
exit /b 0
