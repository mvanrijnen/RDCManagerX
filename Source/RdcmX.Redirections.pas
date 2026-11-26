unit RdcmX.Redirections;

{
  Warning for files that hand local resources to the server (security review 2026-11-25, point 10): drive or port
  redirection, a start program, or the keyboard hook always on the remote side. A file from someone else
  can switch these on silently; RDCManagerX applies them at connect. Smart card redirection is left out: it is on by
  default in RDCMan and mstsc, so it would flag every ordinary file.

  RdcRiskyRedirections lists them per server (effective settings, so inherited ones count). The fingerprint covers
  the file name and the findings (server paths, kinds, start program), not the whole file: the warning is shown once
  per fingerprint (settings.json "acceptedRedirections") and comes back only when the risky settings change. Saving
  a file accepts its current fingerprint: the user's own changes do not trigger the warning.
  No VCL dependency (tested in the console test project).
}

interface

uses
  System.Generics.Collections, System.SysUtils,
  RdcmX.Model;

type
  TRdcRedirectionKind = (rrkDrives, rrkPorts, rrkStartProgram, rrkKeyboardHook);

  TRdcRedirectionFinding = record
    Server: TRdcServer;
    Kind: TRdcRedirectionKind;
    /// <summary>Start program text for rrkStartProgram, else empty.</summary>
    Detail: string;
  end;

/// <summary>Risky redirections of all servers in the file, in tree order.</summary>
function RdcRiskyRedirections(aFile: TRdcFile): TArray<TRdcRedirectionFinding>;
/// <summary>SHA-256 over file name and findings; '' when there are no findings.</summary>
function RdcRedirectionFingerprint(aFile: TRdcFile; const aFindings: TArray<TRdcRedirectionFinding>): string;
/// <summary>The warning text (Dutch source, translated via _), with at most a few servers per kind.</summary>
function RdcRedirectionWarning(aFile: TRdcFile; const aFindings: TArray<TRdcRedirectionFinding>): string;

implementation

uses
  System.Classes, System.Hash,
  RdcmX.Lang;

function RdcRiskyRedirections(aFile: TRdcFile): TArray<TRdcRedirectionFinding>;
var
  lFindings: TList<TRdcRedirectionFinding>;
  lLocal: TRdcLocalResources;
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
  lServer: TRdcServer;

  procedure Add(aKind: TRdcRedirectionKind; const aDetail: string = '');
  var
    lFinding: TRdcRedirectionFinding;
  begin
    lFinding.Server := lServer;
    lFinding.Kind := aKind;
    lFinding.Detail := aDetail;
    lFindings.Add(lFinding);
  end;

begin
  lFindings := TList<TRdcRedirectionFinding>.Create;
  lNodes := TList<TRdcNode>.Create;
  try
    aFile.CollectServers(lNodes);
    for lNode in lNodes do
    begin
      lServer := TRdcServer(lNode);
      lLocal := lServer.EffectiveLocalResources;
      if lLocal.RedirectDrives then
        Add(rrkDrives);
      if lLocal.RedirectPorts then
        Add(rrkPorts);
      if Trim(lServer.EffectiveConnection.StartProgram) <> '' then
        Add(rrkStartProgram, Trim(lServer.EffectiveConnection.StartProgram));
      if lLocal.KeyboardHook = khRemote then
        Add(rrkKeyboardHook);
    end;
    Result := lFindings.ToArray;
  finally
    lNodes.Free;
    lFindings.Free;
  end;
end;

function RdcRedirectionFingerprint(aFile: TRdcFile; const aFindings: TArray<TRdcRedirectionFinding>): string;
var
  lFinding: TRdcRedirectionFinding;
  lText: TStringBuilder;
begin
  if Length(aFindings) = 0 then
    Exit('');
  lText := TStringBuilder.Create;
  try
    lText.Append(LowerCase(aFile.FileName)).Append(#10);
    for lFinding in aFindings do
      lText.Append(lFinding.Server.Path(True)).Append(#9).Append(Ord(lFinding.Kind)).Append(#9).Append(lFinding.Detail).Append(#10);
    Result := THashSHA2.GetHashString(lText.ToString, THashSHA2.TSHA2Version.SHA256);
  finally
    lText.Free;
  end;
end;

function RdcRedirectionWarning(aFile: TRdcFile; const aFindings: TArray<TRdcRedirectionFinding>): string;
const
  cMaxServers = 5;
var
  lCount: Integer;
  lFinding: TRdcRedirectionFinding;
  lKind: TRdcRedirectionKind;
  lLines: TStringList;
  lNames: string;
  lWhat: string;
begin
  lLines := TStringList.Create;
  try
    for lKind := Low(TRdcRedirectionKind) to High(TRdcRedirectionKind) do
    begin
      lNames := '';
      lCount := 0;
      for lFinding in aFindings do
        if lFinding.Kind = lKind then
        begin
          Inc(lCount);
          if lCount <= cMaxServers then
          begin
            if lNames <> '' then
              lNames := lNames + ', ';
            if lKind = rrkStartProgram then
              lNames := lNames + Format('%s (%s)', [lFinding.Server.Caption, lFinding.Detail])
            else
              lNames := lNames + lFinding.Server.Caption;
          end;
        end;
      if lCount = 0 then
        Continue;
      if lCount > cMaxServers then
        lNames := lNames + Format(_(' en nog %d'), [lCount - cMaxServers]);
      case lKind of
        rrkDrives:
          lWhat := _('Lokale schijven delen met de server');
        rrkPorts:
          lWhat := _('Lokale poorten (COM/LPT) delen met de server');
        rrkStartProgram:
          lWhat := _('Programma starten na aanmelden');
      else
        lWhat := _('Windows-toetscombinaties altijd naar de server');
      end;
      lLines.Add(Format('- %s: %s', [lWhat, lNames]));
    end;
    Result := Format(_('"%s" zet bij het verbinden het volgende aan:'#13#10#13#10'%s'#13#10#13#10'Een server kan zo bij uw lokale bestanden of apparaten, of een programma laten starten. Vertrouwt u de maker van dit bestand niet, zet het dan uit in Eigenschappen (tabbladen Lokale bronnen en Verbinding). Deze melding komt pas terug als deze instellingen veranderen.'),
      [ExtractFileName(aFile.FileName), lLines.Text.TrimRight]);
  finally
    lLines.Free;
  end;
end;

end.
