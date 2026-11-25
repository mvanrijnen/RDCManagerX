unit RdcmX.AppSettings;

(*
  App-instellingen per gebruiker: %APPDATA%\RDCManagerX\settings.json.
  - Recente bestanden en de bij afsluiten geopende bestanden (worden bij start hersteld).
  - Vensterpositie/-grootte, gemaximaliseerd en splitter per monitorconfiguratie (sleutel: aantal monitoren
    + hun posities/afmetingen/DPI). Is er voor de huidige configuratie niets bewaard, dan geldt de laatst
    gebruikte layout (de aanroeper controleert of die zichtbaar is).
  - Favorieten (per bestand) en recent verbonden servers: client-instellingen, niet in het bestand. Bewaard als
    bestandsnaam + pad (formaat van <favorites>, met #n bij dubbele namen).
  - Weergave: raster van het sessiegebied (gridColumns/gridRows, columnRatios/rowRatios) en het thema (theme).
    Oude instellingen splitMode/splitRatio (vóór het vrije raster) worden bij het laden omgezet.

  Opslaan schrijft ALLEEN wat in deze sessie veranderd is (gebruikerswens): bij Load wordt per sleutel de waarde
  onthouden; Save leest het bestand opnieuw in en vervangt alleen de sleutels die sindsdien in deze sessie zijn
  gewijzigd (layouts per monitorconfiguratie). Zo overschrijft een tweede, oudere sessie bij afsluiten niet wat een
  andere sessie intussen heeft ingesteld (bijv. "Wachtwoorden onthouden"). Niets veranderd = niets schrijven.
  Onbekende sleutels in het bestand blijven staan.
*)

interface

uses
  Winapi.Windows,
  System.Classes, System.Generics.Collections, System.JSON, System.SysUtils;

type
  TRdcWindowLayout = record
    Valid: Boolean;
    /// <summary>Normale (niet-gemaximaliseerde) positie in fysieke pixels (werkgebied-coördinaten, zoals WINDOWPLACEMENT).</summary>
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Height: Integer;
    Maximized: Boolean;
    /// <summary>Breedte van de boom in 96-DPI-eenheden.</summary>
    TreeWidth: Integer;
  end;

  /// <summary>Verwijzing naar een server: bestand + pad zoals in &lt;favorites&gt; (TRdcNode.Path(True)).</summary>
  TRdcStoredShortcut = record
    FileName: string;
    Path: string;
  end;

  TRdcAppSettings = class
  private
    FFavorites: TArray<TRdcStoredShortcut>;
    FRecentServers: TArray<TRdcStoredShortcut>;
    FRecentServerCount: Integer;
    FAutoSave: Boolean;
    FRememberPasswords: Boolean;
    FAutoLockMinutes: Integer;
    FPingIntervalSec: Integer;
    FFileName: string;
    FOpenFiles: TStringList;
    FRecentFiles: TStringList;
    FLayouts: TDictionary<string, TRdcWindowLayout>;
    FLastLayoutKey: string;
    FGridColumns: Integer;
    FGridRows: Integer;
    FColumnRatios: TArray<Double>;
    FRowRatios: TArray<Double>;
    FTheme: string;
    FLanguage: string;
    FSnapshot: TDictionary<string, string>; // sleutel -> JSON zoals bij laden/laatste opslaan
    procedure MigrateSplitMode(const aSplitMode: string; aSplitRatio: Double);
    function BuildJson: TJSONObject;
    procedure TakeSnapshot;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Load;
    /// <summary>Schrijft alleen de instellingen die sinds Load (of de vorige Save) in deze sessie veranderd zijn,
    /// in het bestand zoals het nu op schijf staat. Niets veranderd: niets schrijven.</summary>
    procedure Save;
    procedure AddRecent(const aFileName: string);
    /// <summary>Layout voor deze monitorconfiguratie, anders de laatst gebruikte (Valid = False als er niets is).</summary>
    function GetLayout(const aMonitorKey: string): TRdcWindowLayout;
    procedure SetLayout(const aMonitorKey: string; const aLayout: TRdcWindowLayout);
    /// <summary>Pad van settings.json (instelbaar voor tests).</summary>
    property FileName: string read FFileName write FFileName;
    property OpenFiles: TStringList read FOpenFiles;
    property RecentFiles: TStringList read FRecentFiles;
    /// <summary>Raster van sessievakken: kolommen x rijen.</summary>
    property GridColumns: Integer read FGridColumns write FGridColumns;
    property GridRows: Integer read FGridRows write FGridRows;
    /// <summary>Breedte-aandeel per kolom / hoogte-aandeel per rij (leeg = gelijk verdeeld).</summary>
    property ColumnRatios: TArray<Double> read FColumnRatios write FColumnRatios;
    property RowRatios: TArray<Double> read FRowRatios write FRowRatios;
    /// <summary>'system', 'light' of 'dark'.</summary>
    property Theme: string read FTheme write FTheme;
    /// <summary>UI language: 'system' (follows the Windows display language), 'en' or 'nl'. Applied at startup.</summary>
    property Language: string read FLanguage write FLanguage;
    /// <summary>Favoriete servers (van alle bestanden; per bestand te herkennen aan FileName).</summary>
    property Favorites: TArray<TRdcStoredShortcut> read FFavorites write FFavorites;
    /// <summary>Laatst verbonden servers, nieuwste eerst.</summary>
    property RecentServers: TArray<TRdcStoredShortcut> read FRecentServers write FRecentServers;
    /// <summary>Hoeveel recent verbonden servers bovenaan de boom staan (Opties).</summary>
    property RecentServerCount: Integer read FRecentServerCount write FRecentServerCount;
    /// <summary>Wijzigingen in bestanden automatisch opslaan (Opties); anders vragen bij sluiten.</summary>
    property AutoSave: Boolean read FAutoSave write FAutoSave;
    /// <summary>Wachtwoorden onthouden in Windows Referentiebeheer (Opties; standaard uit). De wachtwoorden zelf staan
    /// nooit in dit bestand.</summary>
    property RememberPasswords: Boolean read FRememberPasswords write FRememberPasswords;
    /// <summary>Wachtwoordkluis vergrendelen na zoveel minuten zonder gebruik; 0 = nooit.</summary>
    property AutoLockMinutes: Integer read FAutoLockMinutes write FAutoLockMinutes;
    /// <summary>Bereikbaarheid (ping) controleren elke zoveel seconden (Opties; 5..3600, standaard 30).</summary>
    property PingIntervalSec: Integer read FPingIntervalSec write FPingIntervalSec;
  end;

const
  cMaxRecentFiles = 10;
  cAppFolder = 'RDCManagerX';

implementation

uses
  System.IOUtils, System.Math;

const
  cLayoutsKey = 'layouts';

constructor TRdcAppSettings.Create;
begin
  inherited Create;
  FOpenFiles := TStringList.Create;
  FRecentFiles := TStringList.Create;
  FLayouts := TDictionary<string, TRdcWindowLayout>.Create;
  FSnapshot := TDictionary<string, string>.Create;
  FGridColumns := 1;
  FGridRows := 1;
  FTheme := 'system';
  FLanguage := 'system';
  FRecentServerCount := 5;
  FAutoLockMinutes := 15;
  FPingIntervalSec := 30;
  FFileName := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), cAppFolder), 'settings.json');
end;

destructor TRdcAppSettings.Destroy;
begin
  FSnapshot.Free;
  FLayouts.Free;
  FRecentFiles.Free;
  FOpenFiles.Free;
  inherited Destroy;
end;

procedure ReadList(aRoot: TJSONObject; const aKey: string; aList: TStringList);
var
  lItem: TJSONValue;
  lValue: TJSONValue;
begin
  aList.Clear;
  lValue := aRoot.GetValue(aKey);
  if lValue is TJSONArray then
    for lItem in TJSONArray(lValue) do
      aList.Add(lItem.Value);
end;

function ReadRatios(aRoot: TJSONObject; const aKey: string): TArray<Double>;
var
  lItem: TJSONValue;
  lValue: TJSONValue;
begin
  Result := [];
  lValue := aRoot.GetValue(aKey);
  if lValue is TJSONArray then
    for lItem in TJSONArray(lValue) do
      if lItem is TJSONNumber then
        Result := Result + [TJSONNumber(lItem).AsDouble];
end;

function WriteRatios(const aRatios: TArray<Double>): TJSONArray;
var
  lRatio: Double;
begin
  Result := TJSONArray.Create;
  for lRatio in aRatios do
    Result.AddElement(TJSONNumber.Create(lRatio));
end;

function ReadShortcuts(aRoot: TJSONObject; const aKey: string): TArray<TRdcStoredShortcut>;
var
  lItem: TJSONValue;
  lShortcut: TRdcStoredShortcut;
  lValue: TJSONValue;
begin
  Result := [];
  lValue := aRoot.GetValue(aKey);
  if lValue is TJSONArray then
    for lItem in TJSONArray(lValue) do
      if lItem is TJSONObject then
      begin
        lShortcut.FileName := TJSONObject(lItem).GetValue<string>('file', '');
        lShortcut.Path := TJSONObject(lItem).GetValue<string>('path', '');
        if lShortcut.Path <> '' then
          Result := Result + [lShortcut];
      end;
end;

function WriteShortcuts(const aShortcuts: TArray<TRdcStoredShortcut>): TJSONArray;
var
  lItem: TJSONObject;
  lShortcut: TRdcStoredShortcut;
begin
  Result := TJSONArray.Create;
  for lShortcut in aShortcuts do
  begin
    lItem := TJSONObject.Create;
    lItem.AddPair('file', lShortcut.FileName);
    lItem.AddPair('path', lShortcut.Path);
    Result.AddElement(lItem);
  end;
end;

function WriteList(aList: TStringList): TJSONArray;
var
  lItem: string;
begin
  Result := TJSONArray.Create;
  for lItem in aList do
    Result.Add(lItem);
end;

procedure TRdcAppSettings.Load;
var
  lFileName: string;
  lLayout: TRdcWindowLayout;
  lLayoutObject: TJSONObject;
  lPair: TJSONPair;
  lRoot: TJSONValue;
  lValue: TJSONValue;
begin
  lFileName := FFileName;
  if not TFile.Exists(lFileName) then
  begin
    TakeSnapshot;
    Exit;
  end;
  try
    lRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(lFileName, TEncoding.UTF8));
    try
      if lRoot is TJSONObject then
      begin
        ReadList(TJSONObject(lRoot), 'recentFiles', FRecentFiles);
        ReadList(TJSONObject(lRoot), 'openFiles', FOpenFiles);
        FLastLayoutKey := TJSONObject(lRoot).GetValue<string>('lastLayout', '');
        if TJSONObject(lRoot).GetValue('gridColumns') <> nil then
        begin
          FGridColumns := TJSONObject(lRoot).GetValue<Integer>('gridColumns', 1);
          FGridRows := TJSONObject(lRoot).GetValue<Integer>('gridRows', 1);
          FColumnRatios := ReadRatios(TJSONObject(lRoot), 'columnRatios');
          FRowRatios := ReadRatios(TJSONObject(lRoot), 'rowRatios');
        end
        else
          MigrateSplitMode(TJSONObject(lRoot).GetValue<string>('splitMode', 'none'), TJSONObject(lRoot).GetValue<Double>('splitRatio', 0.5));
        FTheme := TJSONObject(lRoot).GetValue<string>('theme', FTheme);
        FLanguage := TJSONObject(lRoot).GetValue<string>('language', FLanguage);
        FFavorites := ReadShortcuts(TJSONObject(lRoot), 'favorites');
        FRecentServers := ReadShortcuts(TJSONObject(lRoot), 'recentServers');
        FRecentServerCount := TJSONObject(lRoot).GetValue<Integer>('recentServerCount', FRecentServerCount);
        FAutoSave := TJSONObject(lRoot).GetValue<Boolean>('autoSave', FAutoSave);
        FRememberPasswords := TJSONObject(lRoot).GetValue<Boolean>('rememberPasswords', FRememberPasswords);
        FAutoLockMinutes := EnsureRange(TJSONObject(lRoot).GetValue<Integer>('autoLockMinutes', FAutoLockMinutes), 0, 1440);
        FPingIntervalSec := EnsureRange(TJSONObject(lRoot).GetValue<Integer>('pingIntervalSec', FPingIntervalSec), 5, 3600);
        lValue := TJSONObject(lRoot).GetValue('layouts');
        if lValue is TJSONObject then
          for lPair in TJSONObject(lValue) do
            if lPair.JsonValue is TJSONObject then
            begin
              lLayoutObject := TJSONObject(lPair.JsonValue);
              lLayout.Valid := True;
              lLayout.Left := lLayoutObject.GetValue<Integer>('left', 0);
              lLayout.Top := lLayoutObject.GetValue<Integer>('top', 0);
              lLayout.Width := lLayoutObject.GetValue<Integer>('width', 0);
              lLayout.Height := lLayoutObject.GetValue<Integer>('height', 0);
              lLayout.Maximized := lLayoutObject.GetValue<Boolean>('maximized', False);
              lLayout.TreeWidth := lLayoutObject.GetValue<Integer>('treeWidth', 0);
              FLayouts.AddOrSetValue(lPair.JsonString.Value, lLayout);
            end;
      end;
    finally
      lRoot.Free;
    end;
  except
    // Kapotte instellingen: met lege instellingen verder.
  end;
  TakeSnapshot;
end;

procedure TRdcAppSettings.TakeSnapshot;
var
  lCurrent: TJSONObject;
  lPair: TJSONPair;
  lSub: TJSONPair;
begin
  FSnapshot.Clear;
  lCurrent := BuildJson;
  try
    for lPair in lCurrent do
      if (lPair.JsonString.Value = cLayoutsKey) and (lPair.JsonValue is TJSONObject) then
      begin
        for lSub in TJSONObject(lPair.JsonValue) do
          FSnapshot.AddOrSetValue(cLayoutsKey + '/' + lSub.JsonString.Value, lSub.JsonValue.ToJSON);
      end
      else
        FSnapshot.AddOrSetValue(lPair.JsonString.Value, lPair.JsonValue.ToJSON);
  finally
    lCurrent.Free;
  end;
end;

procedure TRdcAppSettings.Save;

  function Changed(const aKey: string; aValue: TJSONValue): Boolean;
  var
    lOld: string;
  begin
    Result := not FSnapshot.TryGetValue(aKey, lOld) or (lOld <> aValue.ToJSON);
  end;

var
  lAnyChange: Boolean;
  lCurrent: TJSONObject;
  lDisk: TJSONObject;
  lDiskLayouts: TJSONObject;
  lDiskValue: TJSONValue;
  lPair: TJSONPair;
  lSub: TJSONPair;
  lTemp: string;
begin
  lCurrent := BuildJson;
  lDisk := nil;
  try
    // Wat staat er nu op schijf (een andere sessie kan intussen hebben opgeslagen)?
    try
      if TFile.Exists(FFileName) then
      begin
        lDiskValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(FFileName, TEncoding.UTF8));
        if lDiskValue is TJSONObject then
          lDisk := TJSONObject(lDiskValue)
        else
          lDiskValue.Free;
      end;
    except
      lDisk := nil;
    end;
    if lDisk = nil then
      lDisk := TJSONObject.Create;

    // Alleen gewijzigde sleutels overnemen in de versie van schijf.
    lAnyChange := False;
    for lPair in lCurrent do
    begin
      if (lPair.JsonString.Value = cLayoutsKey) and (lPair.JsonValue is TJSONObject) then
      begin
        lDiskValue := lDisk.GetValue(cLayoutsKey);
        if not (lDiskValue is TJSONObject) then
        begin
          lDisk.RemovePair(cLayoutsKey).Free;
          lDiskLayouts := TJSONObject.Create;
          lDisk.AddPair(cLayoutsKey, lDiskLayouts);
        end
        else
          lDiskLayouts := TJSONObject(lDiskValue);
        for lSub in TJSONObject(lPair.JsonValue) do
          if Changed(cLayoutsKey + '/' + lSub.JsonString.Value, lSub.JsonValue) then
          begin
            lDiskLayouts.RemovePair(lSub.JsonString.Value).Free;
            lDiskLayouts.AddPair(lSub.JsonString.Value, TJSONValue(lSub.JsonValue.Clone));
            lAnyChange := True;
          end;
      end
      else if Changed(lPair.JsonString.Value, lPair.JsonValue) then
      begin
        lDisk.RemovePair(lPair.JsonString.Value).Free;
        lDisk.AddPair(lPair.JsonString.Value, TJSONValue(lPair.JsonValue.Clone));
        lAnyChange := True;
      end;
    end;
    if not lAnyChange then
      Exit;

    try
      TDirectory.CreateDirectory(ExtractFilePath(FFileName));
      // Atomisch: eerst een tijdelijk bestand, dan vervangen.
      lTemp := FFileName + '.tmp';
      TFile.WriteAllText(lTemp, lDisk.Format(2), TEncoding.UTF8);
      if not MoveFileEx(PChar(lTemp), PChar(FFileName), MOVEFILE_REPLACE_EXISTING) then
        RaiseLastOSError;
      TakeSnapshot;
    except
      // Instellingen niet kunnen schrijven is geen reden om de app te laten falen.
    end;
  finally
    lDisk.Free;
    lCurrent.Free;
  end;
end;

function TRdcAppSettings.BuildJson: TJSONObject;
var
  lLayoutObject: TJSONObject;
  lLayouts: TJSONObject;
  lPair: TPair<string, TRdcWindowLayout>;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('recentFiles', WriteList(FRecentFiles));
    lRoot.AddPair('openFiles', WriteList(FOpenFiles));
    lRoot.AddPair('lastLayout', FLastLayoutKey);
    lRoot.AddPair('gridColumns', TJSONNumber.Create(FGridColumns));
    lRoot.AddPair('gridRows', TJSONNumber.Create(FGridRows));
    lRoot.AddPair('columnRatios', WriteRatios(FColumnRatios));
    lRoot.AddPair('rowRatios', WriteRatios(FRowRatios));
    lRoot.AddPair('theme', FTheme);
    lRoot.AddPair('language', FLanguage);
    lRoot.AddPair('favorites', WriteShortcuts(FFavorites));
    lRoot.AddPair('recentServers', WriteShortcuts(FRecentServers));
    lRoot.AddPair('recentServerCount', TJSONNumber.Create(FRecentServerCount));
    lRoot.AddPair('autoSave', TJSONBool.Create(FAutoSave));
    lRoot.AddPair('rememberPasswords', TJSONBool.Create(FRememberPasswords));
    lRoot.AddPair('autoLockMinutes', TJSONNumber.Create(FAutoLockMinutes));
    lRoot.AddPair('pingIntervalSec', TJSONNumber.Create(FPingIntervalSec));
    lLayouts := TJSONObject.Create;
    for lPair in FLayouts do
    begin
      lLayoutObject := TJSONObject.Create;
      lLayoutObject.AddPair('left', TJSONNumber.Create(lPair.Value.Left));
      lLayoutObject.AddPair('top', TJSONNumber.Create(lPair.Value.Top));
      lLayoutObject.AddPair('width', TJSONNumber.Create(lPair.Value.Width));
      lLayoutObject.AddPair('height', TJSONNumber.Create(lPair.Value.Height));
      lLayoutObject.AddPair('maximized', TJSONBool.Create(lPair.Value.Maximized));
      lLayoutObject.AddPair('treeWidth', TJSONNumber.Create(lPair.Value.TreeWidth));
      lLayouts.AddPair(lPair.Key, lLayoutObject);
    end;
    lRoot.AddPair(cLayoutsKey, lLayouts);
    Result := lRoot;
  except
    lRoot.Free;
    raise;
  end;
end;

procedure TRdcAppSettings.MigrateSplitMode(const aSplitMode: string; aSplitRatio: Double);
begin
  // Vaste indelingen van vóór het vrije raster.
  FColumnRatios := [];
  FRowRatios := [];
  FGridColumns := 1;
  FGridRows := 1;
  if SameText(aSplitMode, 'sideBySide') then
  begin
    FGridColumns := 2;
    FColumnRatios := [aSplitRatio, 1 - aSplitRatio];
  end
  else if SameText(aSplitMode, 'stacked') then
  begin
    FGridRows := 2;
    FRowRatios := [aSplitRatio, 1 - aSplitRatio];
  end
  else if SameText(aSplitMode, 'grid4') then
  begin
    FGridColumns := 2;
    FGridRows := 2;
  end
  else if SameText(aSplitMode, 'grid8') then
  begin
    FGridColumns := 4;
    FGridRows := 2;
  end;
end;

procedure TRdcAppSettings.AddRecent(const aFileName: string);
var
  lIndex: Integer;
begin
  for lIndex := FRecentFiles.Count - 1 downto 0 do
    if SameFileName(FRecentFiles[lIndex], aFileName) then
      FRecentFiles.Delete(lIndex);
  FRecentFiles.Insert(0, aFileName);
  while FRecentFiles.Count > cMaxRecentFiles do
    FRecentFiles.Delete(FRecentFiles.Count - 1);
end;

function TRdcAppSettings.GetLayout(const aMonitorKey: string): TRdcWindowLayout;
begin
  if FLayouts.TryGetValue(aMonitorKey, Result) then
    Exit;
  if (FLastLayoutKey <> '') and FLayouts.TryGetValue(FLastLayoutKey, Result) then
    Exit;
  Result := Default(TRdcWindowLayout);
end;

procedure TRdcAppSettings.SetLayout(const aMonitorKey: string; const aLayout: TRdcWindowLayout);
begin
  FLayouts.AddOrSetValue(aMonitorKey, aLayout);
  FLastLayoutKey := aMonitorKey;
end;

end.
