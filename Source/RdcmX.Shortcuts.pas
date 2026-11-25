unit RdcmX.Shortcuts;

{
  Favorieten en recent verbonden servers: client-instellingen (settings.json), niet in het bestand.

  - Favorieten horen bij een bestand (bestandsnaam + pad); bij meerdere open bestanden staan ze samen bovenaan
    de boom. Recent: de laatste MaxRecent (instelbaar, standaard 5) verbonden servers, nieuwste eerst, over alle
    bestanden heen.
  - Zolang een bestand open is, wijst een item naar het server-object zelf. Hernoemen of verplaatsen breekt een
    favoriet daardoor niet; het pad wordt pas bij opslaan/sluiten opnieuw uit het object bepaald (RefreshPaths).
  - Items van een bestand dat niet open is blijven bewaard (Server = nil) en worden niet getoond.
  - Pad = TRdcNode.Path(True): het formaat van RDCMan's <favorites>, met #n bij dubbele namen.
}

interface

uses
  System.Generics.Collections, System.Math, System.SysUtils,
  RdcmX.AppSettings, RdcmX.Model;

const
  cRdcDefaultMaxRecent = 5;
  cRdcMaxRecentLimit = 25;

type
  TRdcShortcut = class
  public
    FileName: string;
    Path: string;
    /// <summary>De server zolang zijn bestand open is; anders nil.</summary>
    Server: TRdcServer;
  end;

  TRdcClientShortcuts = class
  private
    FFavorites: TObjectList<TRdcShortcut>;
    FRecent: TObjectList<TRdcShortcut>;
    FMaxRecent: Integer;
    procedure TrimRecent;
    procedure SetMaxRecent(aValue: Integer);
    class function IndexOfServer(aList: TObjectList<TRdcShortcut>; aServer: TRdcServer): Integer; static;
    class procedure LoadList(aList: TObjectList<TRdcShortcut>; const aStored: TArray<TRdcStoredShortcut>); static;
    class function StoreList(aList: TObjectList<TRdcShortcut>): TArray<TRdcStoredShortcut>; static;
    class procedure ResolveList(aList: TObjectList<TRdcShortcut>; aFile: TRdcFile); static;
    class procedure ReleaseList(aList: TObjectList<TRdcShortcut>; aFile: TRdcFile); static;
    class procedure RemoveUnder(aList: TObjectList<TRdcShortcut>; aNode: TRdcNode); static;
    class function ResolvedServers(aList: TObjectList<TRdcShortcut>): TArray<TRdcServer>; static;
    function NewShortcut(aServer: TRdcServer): TRdcShortcut;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFrom(const aFavorites, aRecent: TArray<TRdcStoredShortcut>);
    /// <summary>Paden bijwerken en als bestand+pad teruggeven.</summary>
    procedure SaveTo(out aFavorites, aRecent: TArray<TRdcStoredShortcut>);
    /// <summary>Bestand is geopend: items van dit bestand aan hun server koppelen.</summary>
    procedure FileOpened(aFile: TRdcFile);
    /// <summary>Bestand gaat dicht: paden bijwerken en de koppeling loslaten.</summary>
    procedure FileClosing(aFile: TRdcFile);
    /// <summary>Node (server of groep met alles eronder) wordt verwijderd: bijbehorende items verdwijnen.</summary>
    procedure NodeRemoved(aNode: TRdcNode);
    /// <summary>Paden en bestandsnamen uit de gekoppelde servers opnieuw bepalen (na hernoemen, verplaatsen, opslaan als).</summary>
    procedure RefreshPaths;
    function IsFavorite(aServer: TRdcServer): Boolean;
    procedure AddFavorite(aServer: TRdcServer);
    procedure RemoveFavorite(aServer: TRdcServer);
    procedure AddRecent(aServer: TRdcServer);
    procedure RemoveRecent(aServer: TRdcServer);
    /// <summary>Favorieten waarvan het bestand open is, in volgorde van toevoegen.</summary>
    function FavoriteServers: TArray<TRdcServer>;
    /// <summary>Recent verbonden servers waarvan het bestand open is, nieuwste eerst.</summary>
    function RecentServers: TArray<TRdcServer>;
    /// <summary>Aantal recente servers dat bewaard en getoond wordt (0 = geen lijst Recent).</summary>
    property MaxRecent: Integer read FMaxRecent write SetMaxRecent;
  end;

implementation

{ TRdcClientShortcuts }

constructor TRdcClientShortcuts.Create;
begin
  inherited Create;
  FFavorites := TObjectList<TRdcShortcut>.Create(True);
  FRecent := TObjectList<TRdcShortcut>.Create(True);
  FMaxRecent := cRdcDefaultMaxRecent;
end;

procedure TRdcClientShortcuts.TrimRecent;
begin
  while FRecent.Count > FMaxRecent do
    FRecent.Delete(FRecent.Count - 1);
end;

procedure TRdcClientShortcuts.SetMaxRecent(aValue: Integer);
begin
  FMaxRecent := EnsureRange(aValue, 0, cRdcMaxRecentLimit);
  TrimRecent;
end;

destructor TRdcClientShortcuts.Destroy;
begin
  FRecent.Free;
  FFavorites.Free;
  inherited Destroy;
end;

class function TRdcClientShortcuts.IndexOfServer(aList: TObjectList<TRdcShortcut>; aServer: TRdcServer): Integer;
begin
  for Result := 0 to aList.Count - 1 do
    if aList[Result].Server = aServer then
      Exit;
  Result := -1;
end;

class procedure TRdcClientShortcuts.LoadList(aList: TObjectList<TRdcShortcut>; const aStored: TArray<TRdcStoredShortcut>);
var
  lShortcut: TRdcShortcut;
  lStored: TRdcStoredShortcut;
begin
  aList.Clear;
  for lStored in aStored do
  begin
    lShortcut := TRdcShortcut.Create;
    lShortcut.FileName := lStored.FileName;
    lShortcut.Path := lStored.Path;
    aList.Add(lShortcut);
  end;
end;

class function TRdcClientShortcuts.StoreList(aList: TObjectList<TRdcShortcut>): TArray<TRdcStoredShortcut>;
var
  lIndex: Integer;
begin
  SetLength(Result, aList.Count);
  for lIndex := 0 to aList.Count - 1 do
  begin
    Result[lIndex].FileName := aList[lIndex].FileName;
    Result[lIndex].Path := aList[lIndex].Path;
  end;
end;

class procedure TRdcClientShortcuts.ResolveList(aList: TObjectList<TRdcShortcut>; aFile: TRdcFile);
var
  lNode: TRdcNode;
  lShortcut: TRdcShortcut;
begin
  if aFile.FileName = '' then
    Exit;
  for lShortcut in aList do
    if (lShortcut.Server = nil) and SameFileName(lShortcut.FileName, aFile.FileName) then
    begin
      lNode := aFile.FindByPath(lShortcut.Path);
      if lNode is TRdcServer then
        lShortcut.Server := TRdcServer(lNode);
    end;
end;

class procedure TRdcClientShortcuts.ReleaseList(aList: TObjectList<TRdcShortcut>; aFile: TRdcFile);
var
  lShortcut: TRdcShortcut;
begin
  for lShortcut in aList do
    if (lShortcut.Server <> nil) and (lShortcut.Server.RdcFile = aFile) then
    begin
      lShortcut.FileName := aFile.FileName;
      lShortcut.Path := lShortcut.Server.Path(True);
      lShortcut.Server := nil;
    end;
end;

class procedure TRdcClientShortcuts.RemoveUnder(aList: TObjectList<TRdcShortcut>; aNode: TRdcNode);
var
  lIndex: Integer;
  lServer: TRdcServer;
begin
  for lIndex := aList.Count - 1 downto 0 do
  begin
    lServer := aList[lIndex].Server;
    if (lServer <> nil) and ((lServer = aNode) or ((aNode is TRdcGroup) and lServer.IsDescendantOf(TRdcGroup(aNode)))) then
      aList.Delete(lIndex);
  end;
end;

class function TRdcClientShortcuts.ResolvedServers(aList: TObjectList<TRdcShortcut>): TArray<TRdcServer>;
var
  lShortcut: TRdcShortcut;
begin
  Result := [];
  for lShortcut in aList do
    if lShortcut.Server <> nil then
      Result := Result + [lShortcut.Server];
end;

function TRdcClientShortcuts.NewShortcut(aServer: TRdcServer): TRdcShortcut;
begin
  Result := TRdcShortcut.Create;
  Result.Server := aServer;
  if aServer.RdcFile <> nil then
    Result.FileName := aServer.RdcFile.FileName;
  Result.Path := aServer.Path(True);
end;

procedure TRdcClientShortcuts.LoadFrom(const aFavorites, aRecent: TArray<TRdcStoredShortcut>);
begin
  LoadList(FFavorites, aFavorites);
  LoadList(FRecent, aRecent);
  TrimRecent;
end;

procedure TRdcClientShortcuts.SaveTo(out aFavorites, aRecent: TArray<TRdcStoredShortcut>);
begin
  RefreshPaths;
  aFavorites := StoreList(FFavorites);
  aRecent := StoreList(FRecent);
end;

procedure TRdcClientShortcuts.FileOpened(aFile: TRdcFile);
begin
  ResolveList(FFavorites, aFile);
  ResolveList(FRecent, aFile);
end;

procedure TRdcClientShortcuts.FileClosing(aFile: TRdcFile);
begin
  ReleaseList(FFavorites, aFile);
  ReleaseList(FRecent, aFile);
end;

procedure TRdcClientShortcuts.NodeRemoved(aNode: TRdcNode);
begin
  RemoveUnder(FFavorites, aNode);
  RemoveUnder(FRecent, aNode);
end;

procedure TRdcClientShortcuts.RefreshPaths;
var
  lShortcut: TRdcShortcut;
begin
  for lShortcut in FFavorites do
    if lShortcut.Server <> nil then
    begin
      lShortcut.FileName := lShortcut.Server.RdcFile.FileName;
      lShortcut.Path := lShortcut.Server.Path(True);
    end;
  for lShortcut in FRecent do
    if lShortcut.Server <> nil then
    begin
      lShortcut.FileName := lShortcut.Server.RdcFile.FileName;
      lShortcut.Path := lShortcut.Server.Path(True);
    end;
end;

function TRdcClientShortcuts.IsFavorite(aServer: TRdcServer): Boolean;
begin
  Result := (aServer <> nil) and (IndexOfServer(FFavorites, aServer) >= 0);
end;

procedure TRdcClientShortcuts.AddFavorite(aServer: TRdcServer);
begin
  if (aServer <> nil) and not IsFavorite(aServer) then
    FFavorites.Add(NewShortcut(aServer));
end;

procedure TRdcClientShortcuts.RemoveFavorite(aServer: TRdcServer);
var
  lIndex: Integer;
begin
  lIndex := IndexOfServer(FFavorites, aServer);
  if lIndex >= 0 then
    FFavorites.Delete(lIndex);
end;

procedure TRdcClientShortcuts.AddRecent(aServer: TRdcServer);
var
  lIndex: Integer;
begin
  if (aServer = nil) or (FMaxRecent = 0) then
    Exit;
  lIndex := IndexOfServer(FRecent, aServer);
  if lIndex >= 0 then
    FRecent.Move(lIndex, 0)
  else
    FRecent.Insert(0, NewShortcut(aServer));
  TrimRecent;
end;

procedure TRdcClientShortcuts.RemoveRecent(aServer: TRdcServer);
var
  lIndex: Integer;
begin
  lIndex := IndexOfServer(FRecent, aServer);
  if lIndex >= 0 then
    FRecent.Delete(lIndex);
end;

function TRdcClientShortcuts.FavoriteServers: TArray<TRdcServer>;
begin
  Result := ResolvedServers(FFavorites);
end;

function TRdcClientShortcuts.RecentServers: TArray<TRdcServer>;
begin
  Result := ResolvedServers(FRecent);
end;

end.
