unit RdcmX.Storage;

{
  Gemeenschappelijke opslaglaag.

  - IRdcFileStorage (Load/Save) per formaat, gekozen op extensie: .rdg (RDCMan, + sidecar) en .rdcx (JSON).
  - Externe wijziging: bij laden worden SHA-256 en tijdstempel onthouden. Bij opslaan naar hetzelfde bestand
    wordt gecontroleerd of het intussen door iets anders (bijv. RDCMan) is gewijzigd; zo ja, dan beslist de
    callback: herladen / overschrijven / annuleren. Zonder callback wordt niet overschreven.
  - Atomisch opslaan: eerst naar <bestand>.tmp, daarna vervangen met MoveFileEx (REPLACE_EXISTING |
    WRITE_THROUGH). De eerste keer dat een geladen bestand wordt overschreven, komt er een <bestand>.bak.
  - "Opslaan als" naar de andere extensie converteert: .rdg -> .rdcx neemt de sidecar-extra's mee in de JSON,
    .rdcx -> .rdg schrijft de extra's naar een nieuwe sidecar.
}

interface

uses
  System.SysUtils,
  RdcmX.Model;

type
  ERdcStorageError = class(Exception);

  TRdcExternalChangeAction = (ecaReload, ecaOverwrite, ecaCancel);
  TRdcExternalChangeEvent = reference to function(aFile: TRdcFile): TRdcExternalChangeAction;
  TRdcSaveResult = (srSaved, srCancelled, srReloadRequested);

  IRdcFileStorage = interface
    ['{7B0B8E8C-2A55-4F0E-9C51-6B6F3F1E2D11}']
    function Load(const aFileName: string): TRdcFile;
    /// <summary>Schrijft (atomisch) zonder controle op externe wijzigingen; zie TRdcStorage.Save.</summary>
    procedure Save(aFile: TRdcFile; const aFileName: string);
  end;

  TRdcStorage = class abstract
  public
    class function ForFileName(const aFileName: string): IRdcFileStorage; static;
    class function Load(const aFileName: string): TRdcFile; static;
    /// <summary>Opslaan (aFileName leeg = huidige bestandsnaam). Bij een externe wijziging wordt aOnExternalChange gevraagd.</summary>
    class function Save(aFile: TRdcFile; const aFileName: string = ''; const aOnExternalChange: TRdcExternalChangeEvent = nil): TRdcSaveResult; static;
    class function HasExternalChange(aFile: TRdcFile): Boolean; static;
    class procedure WriteFileAtomic(const aFileName: string; const aBytes: TBytes); static;
    class function FileHash(const aFileName: string): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes, System.Hash, System.IOUtils,
  RdcmX.Lang, RdcmX.Storage.Json, RdcmX.Storage.Rdg, RdcmX.Storage.Sidecar;

type
  TRdgStorage = class(TInterfacedObject, IRdcFileStorage)
  public
    function Load(const aFileName: string): TRdcFile;
    procedure Save(aFile: TRdcFile; const aFileName: string);
  end;

  TJsonStorage = class(TInterfacedObject, IRdcFileStorage)
  public
    function Load(const aFileName: string): TRdcFile;
    procedure Save(aFile: TRdcFile; const aFileName: string);
  end;

{ TRdgStorage }

function TRdgStorage.Load(const aFileName: string): TRdcFile;
var
  lSidecar: string;
begin
  Result := TRdcRdgFormat.Read(TFile.ReadAllBytes(aFileName), aFileName);
  try
    lSidecar := TRdcSidecar.FileNameFor(aFileName);
    if TFile.Exists(lSidecar) then
      TRdcSidecar.Apply(Result, TFile.ReadAllText(lSidecar, TEncoding.UTF8));
  except
    Result.Free;
    raise;
  end;
end;

procedure TRdgStorage.Save(aFile: TRdcFile; const aFileName: string);
var
  lSidecar: string;
  lSidecarText: string;
begin
  TRdcStorage.WriteFileAtomic(aFileName, TRdcRdgFormat.Write(aFile));
  lSidecar := TRdcSidecar.FileNameFor(aFileName);
  lSidecarText := TRdcSidecar.Build(aFile);
  if lSidecarText <> '' then
    TRdcStorage.WriteFileAtomic(lSidecar, TEncoding.UTF8.GetBytes(lSidecarText))
  else if TFile.Exists(lSidecar) then
    TFile.Delete(lSidecar); // niets meer te bewaren: verouderde sidecar opruimen
end;

{ TJsonStorage }

function TJsonStorage.Load(const aFileName: string): TRdcFile;
begin
  Result := TRdcJsonFormat.Read(TFile.ReadAllBytes(aFileName), aFileName);
end;

procedure TJsonStorage.Save(aFile: TRdcFile; const aFileName: string);
begin
  TRdcStorage.WriteFileAtomic(aFileName, TRdcJsonFormat.Write(aFile));
end;

{ TRdcStorage }

class function TRdcStorage.ForFileName(const aFileName: string): IRdcFileStorage;
var
  lExtension: string;
begin
  lExtension := LowerCase(ExtractFileExt(aFileName));
  if lExtension = '.rdg' then
    Result := TRdgStorage.Create
  else if lExtension = '.rdcx' then
    Result := TJsonStorage.Create
  else
    raise ERdcStorageError.CreateFmt(_('Onbekend bestandstype "%s" (verwacht .rdg of .rdcx).'), [lExtension]);
end;

class function TRdcStorage.FileHash(const aFileName: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(aFileName, THashSHA2.TSHA2Version.SHA256);
end;

class function TRdcStorage.Load(const aFileName: string): TRdcFile;
begin
  Result := ForFileName(aFileName).Load(aFileName);
  try
    Result.FileName := aFileName;
    if SameText(ExtractFileExt(aFileName), '.rdcx') then
      Result.Format := ffRdcx
    else
      Result.Format := ffRdg;
    Result.LoadedHash := FileHash(aFileName);
    Result.LoadedTimestamp := TFile.GetLastWriteTimeUtc(aFileName);
    Result.BackupMade := False;
    Result.Modified := False;
  except
    Result.Free;
    raise;
  end;
end;

class function TRdcStorage.HasExternalChange(aFile: TRdcFile): Boolean;
begin
  Result := False;
  if (aFile.FileName = '') or (aFile.LoadedHash = '') then
    Exit;
  if not TFile.Exists(aFile.FileName) then
    Exit(True);
  // Tijdstempel als snelle check; de hash beslist (een touch zonder inhoudswijziging telt niet).
  if TFile.GetLastWriteTimeUtc(aFile.FileName) = aFile.LoadedTimestamp then
    Exit;
  Result := FileHash(aFile.FileName) <> aFile.LoadedHash;
end;

class procedure TRdcStorage.WriteFileAtomic(const aFileName: string; const aBytes: TBytes);
var
  lTempName: string;
begin
  lTempName := aFileName + '.tmp';
  TFile.WriteAllBytes(lTempName, aBytes);
  if not MoveFileEx(PChar(lTempName), PChar(aFileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
  begin
    try
      RaiseLastOSError;
    finally
      if TFile.Exists(lTempName) then
        TFile.Delete(lTempName);
    end;
  end;
end;

class function TRdcStorage.Save(aFile: TRdcFile; const aFileName: string; const aOnExternalChange: TRdcExternalChangeEvent): TRdcSaveResult;
var
  lAction: TRdcExternalChangeAction;
  lSameFile: Boolean;
  lTarget: string;
begin
  lTarget := aFileName;
  if lTarget = '' then
    lTarget := aFile.FileName;
  if lTarget = '' then
    raise ERdcStorageError.Create(_('Geen bestandsnaam om naar op te slaan.'));
  lSameFile := SameFileName(ExpandFileName(lTarget), ExpandFileName(aFile.FileName));

  if lSameFile and HasExternalChange(aFile) then
  begin
    if Assigned(aOnExternalChange) then
      lAction := aOnExternalChange(aFile)
    else
      lAction := ecaCancel;
    case lAction of
      ecaReload:
        Exit(srReloadRequested);
      ecaCancel:
        Exit(srCancelled);
    end;
  end;

  // Eenmalig een .bak van het origineel voordat een geladen bestand voor het eerst wordt overschreven.
  if lSameFile and not aFile.BackupMade and TFile.Exists(lTarget) then
  begin
    TFile.Copy(lTarget, lTarget + '.bak', True);
    aFile.BackupMade := True;
  end;

  ForFileName(lTarget).Save(aFile, lTarget);

  if not lSameFile then
    aFile.BackupMade := False;
  aFile.FileName := lTarget;
  if SameText(ExtractFileExt(lTarget), '.rdcx') then
    aFile.Format := ffRdcx
  else
    aFile.Format := ffRdg;
  aFile.LoadedHash := FileHash(lTarget);
  aFile.LoadedTimestamp := TFile.GetLastWriteTimeUtc(lTarget);
  aFile.Modified := False;
  Result := srSaved;
end;

end.
