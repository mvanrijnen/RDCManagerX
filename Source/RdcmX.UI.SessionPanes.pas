unit RdcmX.UI.SessionPanes;

{
  Het sessiegebied rechts in het hoofdvenster: een raster van kolommen x rijen (1..6 x 1..3) met een eigen
  tabbalk (RdcmX.UI.TabStrip) per vak. Tussen alle kolommen en rijen zit een versleepbare splitter; dubbelklik
  op een splitter verdeelt weer gelijk. Bedoeld o.a. voor ultrawide schermen (bijv. 4 kolommen op 5120x1440).

  Ontwerp (zie ook RdcmX.Rdp.Host):
  - Alles staat als kind in één container (pnlSession): de tabbalken, de splitters, de placeholder-teksten en alle
    RDP-hosts. Niets overlapt (behalve splitters onderling op kruispunten).
  - De RDP-hosts verhuizen dus nooit van VCL-Parent (dat zou de sessie verbreken); ze krijgen alleen een andere
    positie. Deze klasse rekent de vakken uit (Layout/HostRect); het hoofdvenster zet de hosts daar via
    TRdcSessionManager.ShowServers.
  - Vakken zijn genummerd per rij: index = rij * kolommen + kolom.
  - Per vak toont de geselecteerde tab de sessie. Het actieve vak (laatst aangeklikt: tab, sessie of leeg vak;
    zichtbaar aan de accentlijn onder de tab) bepaalt waar een nieuwe verbinding opent en welke sessie de
    statusbalk toont.
  - Tab naar een ander vak: slepen naar de tabbalk of het lege vak van het doel, of via het tab-menu (volgend vak).
  - Minder vakken kiezen zet de tabs van de vervallen vakken in het eerste vak.

  De tabbalken bevatten zelf geen sessies; een handle-recreate van een tabbalk raakt de sessies niet.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.Math, System.SysUtils, System.Types, System.UITypes,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.ImgList, Vcl.Menus, Vcl.StdCtrls,
  RdcmX.Model, RdcmX.UI.TabStrip;

const
  cRdcMaxColumns = 6;
  cRdcMaxRows = 3;
  cRdcMaxPanes = cRdcMaxColumns * cRdcMaxRows;

type
  TRdcPaneServerEvent = procedure(aSender: TObject; aServer: TRdcServer) of object;
  TRdcTabImageEvent = function(aServer: TRdcServer): Integer of object;

  TRdcSessionPanes = class
  private
    FContainer: TWinControl;
    FTabs: array[0..cRdcMaxPanes - 1] of TRdcTabStrip;
    FPlaceholders: array[0..cRdcMaxPanes - 1] of TLabel;
    FHostRects: array[0..cRdcMaxPanes - 1] of TRect;
    FColumnSplitters: array[0..cRdcMaxColumns - 2] of TPanel;
    FRowSplitters: array[0..cRdcMaxRows - 2] of TPanel;
    FColumns: Integer;
    FRows: Integer;
    FColumnRatios: TArray<Double>;
    FRowRatios: TArray<Double>;
    FActivePane: Integer;
    FDraggedSplitter: TPanel;
    FDragServer: TRdcServer;
    FMenuServer: TRdcServer;
    FEmptyText: string;
    FEmptyPaneText: string;
    FNotes: array[0..cRdcMaxPanes - 1] of string;
    FSplitterColor: TColor;
    FOnActiveChanged: TNotifyEvent;
    FOnCloseRequest: TRdcPaneServerEvent;
    FOnLayoutChanged: TNotifyEvent;
    FOnTabImage: TRdcTabImageEvent;
    // Event-handlers van de eigen controls: alleen doorverwijzen.
    procedure ContainerResize(Sender: TObject);
    procedure SplitterDblClick(Sender: TObject);
    procedure SplitterMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SplitterMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure SplitterMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TabChange(Sender: TObject);
    procedure TabClose(Sender: TObject; TabIndex: Integer);
    procedure TabContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure PlaceholderClick(Sender: TObject);
    procedure PaneDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure PaneDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure TabGetImageIndex(Sender: TObject; TabIndex: Integer; var ImageIndex: Integer);
    procedure TabMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TabMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    // Logica
    function CreateTabs: TRdcTabStrip;
    function CreatePlaceholder(aTemplate: TLabel): TLabel;
    function CreateSplitter(aCursor: TCursor; aTag: Integer): TPanel;
    function Scale(aValue: Integer): Integer;
    function PaneOfControl(aControl: TObject): Integer;
    function PaneAtContainerPoint(const aPoint: TPoint): Integer;
    function IndexIn(aPane: Integer; aServer: TRdcServer): Integer;
    function ServerAt(aPane: Integer; X, Y: Integer): TRdcServer;
    function ServerAtIndex(aPane, aIndex: Integer): TRdcServer;
    procedure AddToPane(aPane: Integer; aServer: TRdcServer);
    procedure DeleteFromPane(aPane: Integer; aServer: TRdcServer);
    procedure MoveServer(aServer: TRdcServer; aTarget: Integer);
    procedure SetActivePane(aPane: Integer; aNotify: Boolean);
    procedure UpdateIndicators;
    procedure UpdatePlaceholders;
    procedure DragSplitterToCursor;
    procedure MoveBoundary(var aRatios: TArray<Double>; aIndex: Integer; aCursor, aTotal: Integer);
    procedure DropDraggedTab(aSender: TObject; X, Y: Integer);
    function ReorderDraggedTab(aStrip: TRdcTabStrip; X, Y: Integer): Boolean;
    function CanDropDraggedTab(aSender, aSource: TObject; X, Y: Integer): Boolean;
    procedure TabClicked(aPane: Integer; aButton: TMouseButton; X, Y: Integer);
    procedure TabReleased(aPane: Integer; aButton: TMouseButton; X, Y: Integer);
    procedure PrepareTabMenu(aPane: Integer; const aMousePos: TPoint; var aHandled: Boolean);
    procedure DoActiveChanged;
    procedure DoLayoutChanged;
    procedure SetColumnRatios(const aValue: TArray<Double>);
    procedure SetRowRatios(const aValue: TArray<Double>);
  public
    /// <summary>aPlaceholder: bestaande label in de container (tekst bij een leeg vak); wordt het eerste vak.</summary>
    constructor Create(aContainer: TWinControl; aPlaceholder: TLabel; aImages: TCustomImageList; aTabMenu: TPopupMenu);
    destructor Destroy; override;
    /// <summary>Vakken, tabbalken en splitters positioneren; daarna OnLayoutChanged.</summary>
    procedure Layout;
    /// <summary>Raster van aColumns x aRows (begrensd op 1..6 x 1..3). Een gewijzigd aantal kolommen/rijen wordt gelijk verdeeld.</summary>
    procedure SetGrid(aColumns, aRows: Integer);
    /// <summary>Alle kolommen en rijen weer even groot.</summary>
    procedure Equalize;
    procedure SetImages(aImages: TCustomImageList);
    /// <summary>Kleuren van sessiegebied, splitters en placeholders volgens het thema.</summary>
    procedure ApplyColors(aDark: Boolean);
    function IsSplit: Boolean;
    function PaneCount: Integer;
    /// <summary>Vak met de tab van aServer, of -1.</summary>
    function PaneOf(aServer: TRdcServer): Integer;
    function Contains(aServer: TRdcServer): Boolean;
    function TabCount: Integer;
    /// <summary>Server van de geselecteerde tab in aPane (nil bij een leeg vak).</summary>
    function ServerOf(aPane: Integer): TRdcServer;
    /// <summary>Server van de geselecteerde tab in het actieve vak.</summary>
    function ActiveServer: TRdcServer;
    /// <summary>Plek voor de sessie van aPane, in client-coördinaten van de container.</summary>
    function HostRect(aPane: Integer): TRect;
    /// <summary>Tab van aServer selecteren (aanmaken in het actieve vak als hij er nog niet is); dat vak wordt actief. Geen OnActiveChanged.</summary>
    procedure Activate(aServer: TRdcServer);
    /// <summary>Klik in de sessie van aServer: het vak daarvan wordt actief (OnActiveChanged bij een wissel).</summary>
    procedure ActivatePaneOf(aServer: TRdcServer);
    procedure Remove(aServer: TRdcServer);
    procedure MoveToNextPane(aServer: TRdcServer);
    /// <summary>Vak actief maken zonder OnActiveChanged (bijv. om een groep over de vakken te verdelen).</summary>
    procedure SelectPane(aPane: Integer);
    /// <summary>Tekst in het vak, ook als er tabs zijn (bijv. "staat in een eigen venster"); '' = normale weergave.</summary>
    procedure SetPaneNote(aPane: Integer; const aText: string);
    procedure UpdateCaption(aServer: TRdcServer);
    procedure UpdateImages;
    property ActivePane: Integer read FActivePane;
    property Columns: Integer read FColumns;
    property Rows: Integer read FRows;
    /// <summary>Breedte-aandeel per kolom (som 1). Bij een ongeldige lengte: gelijk verdeeld.</summary>
    property ColumnRatios: TArray<Double> read FColumnRatios write SetColumnRatios;
    /// <summary>Hoogte-aandeel per rij (som 1).</summary>
    property RowRatios: TArray<Double> read FRowRatios write SetRowRatios;
    /// <summary>Server van de tab waarop het tab-menu geopend is.</summary>
    property MenuServer: TRdcServer read FMenuServer;
    /// <summary>Tekst in het lege sessiegebied bij één vak.</summary>
    property EmptyText: string read FEmptyText write FEmptyText;
    /// <summary>Korte tekst in een leeg vak bij meerdere vakken.</summary>
    property EmptyPaneText: string read FEmptyPaneText write FEmptyPaneText;
    /// <summary>Gebruiker koos een andere tab of een ander vak.</summary>
    property OnActiveChanged: TNotifyEvent read FOnActiveChanged write FOnActiveChanged;
    /// <summary>Sluitknop of middelklik op een tab.</summary>
    property OnCloseRequest: TRdcPaneServerEvent read FOnCloseRequest write FOnCloseRequest;
    /// <summary>Vakken verschoven of van inhoud gewisseld: hosts opnieuw plaatsen.</summary>
    property OnLayoutChanged: TNotifyEvent read FOnLayoutChanged write FOnLayoutChanged;
    property OnTabImage: TRdcTabImageEvent read FOnTabImage write FOnTabImage;
  end;

implementation

const
  cTabHeight = 34;
  cSplitterSize = 6;
  cMinPaneSize = 160;
  // Tag van een splitter: kolomsplitter i = i, rijsplitter j = 100 + j.
  cRowSplitterTag = 100;

function EqualRatios(aCount: Integer): TArray<Double>;
var
  lIndex: Integer;
begin
  SetLength(Result, aCount);
  for lIndex := 0 to aCount - 1 do
    Result[lIndex] := 1 / aCount;
end;

function NormalizedRatios(const aRatios: TArray<Double>; aCount: Integer): TArray<Double>;
var
  lIndex: Integer;
  lSum: Double;
begin
  // Verkeerde lengte of onzin (<= 0): gelijk verdelen; anders schalen naar som 1.
  if Length(aRatios) <> aCount then
    Exit(EqualRatios(aCount));
  lSum := 0;
  for lIndex := 0 to aCount - 1 do
  begin
    if aRatios[lIndex] <= 0 then
      Exit(EqualRatios(aCount));
    lSum := lSum + aRatios[lIndex];
  end;
  SetLength(Result, aCount);
  for lIndex := 0 to aCount - 1 do
    Result[lIndex] := aRatios[lIndex] / lSum;
end;

function SumOfRatios(const aRatios: TArray<Double>; aCount: Integer): Double;
var
  lIndex: Integer;
begin
  Result := 0;
  for lIndex := 0 to aCount - 1 do
    Result := Result + aRatios[lIndex];
end;

{ TRdcSessionPanes }

constructor TRdcSessionPanes.Create(aContainer: TWinControl; aPlaceholder: TLabel; aImages: TCustomImageList; aTabMenu: TPopupMenu);
var
  lIndex: Integer;
begin
  inherited Create;
  FContainer := aContainer;
  FColumns := 1;
  FRows := 1;
  FColumnRatios := EqualRatios(1);
  FRowRatios := EqualRatios(1);
  FSplitterColor := $00403D3B;
  aPlaceholder.Align := alNone;
  FPlaceholders[0] := aPlaceholder;
  for lIndex := 0 to cRdcMaxPanes - 1 do
  begin
    FTabs[lIndex] := CreateTabs;
    FTabs[lIndex].Images := aImages;
    FTabs[lIndex].PopupMenu := aTabMenu;
    if lIndex > 0 then
      FPlaceholders[lIndex] := CreatePlaceholder(aPlaceholder);
    FPlaceholders[lIndex].OnDragOver := PaneDragOver;
    FPlaceholders[lIndex].OnDragDrop := PaneDragDrop;
    FPlaceholders[lIndex].OnClick := PlaceholderClick;
  end;
  for lIndex := 0 to High(FColumnSplitters) do
    FColumnSplitters[lIndex] := CreateSplitter(crHSplit, lIndex);
  for lIndex := 0 to High(FRowSplitters) do
    FRowSplitters[lIndex] := CreateSplitter(crVSplit, cRowSplitterTag + lIndex);

  if FContainer is TPanel then
  begin
    TPanel(FContainer).OnResize := ContainerResize;
    TPanel(FContainer).OnDragOver := PaneDragOver;
    TPanel(FContainer).OnDragDrop := PaneDragDrop;
  end;
  UpdatePlaceholders;
  UpdateIndicators;
end;

destructor TRdcSessionPanes.Destroy;
var
  lIndex: Integer;
begin
  // De controls zijn van het formulier en leven langer: hun events mogen niet meer naar dit object wijzen.
  if FContainer is TPanel then
  begin
    TPanel(FContainer).OnResize := nil;
    TPanel(FContainer).OnDragOver := nil;
    TPanel(FContainer).OnDragDrop := nil;
  end;
  for lIndex := 0 to cRdcMaxPanes - 1 do
  begin
    FTabs[lIndex].OnChange := nil;
    FTabs[lIndex].OnTabClose := nil;
    FTabs[lIndex].OnContextPopup := nil;
    FTabs[lIndex].OnDragDrop := nil;
    FTabs[lIndex].OnDragOver := nil;
    FTabs[lIndex].OnGetImageIndex := nil;
    FTabs[lIndex].OnMouseDown := nil;
    FTabs[lIndex].OnMouseUp := nil;
    FPlaceholders[lIndex].OnDragOver := nil;
    FPlaceholders[lIndex].OnDragDrop := nil;
    FPlaceholders[lIndex].OnClick := nil;
  end;
  for lIndex := 0 to High(FColumnSplitters) do
  begin
    FColumnSplitters[lIndex].OnMouseDown := nil;
    FColumnSplitters[lIndex].OnMouseMove := nil;
    FColumnSplitters[lIndex].OnMouseUp := nil;
    FColumnSplitters[lIndex].OnDblClick := nil;
  end;
  for lIndex := 0 to High(FRowSplitters) do
  begin
    FRowSplitters[lIndex].OnMouseDown := nil;
    FRowSplitters[lIndex].OnMouseMove := nil;
    FRowSplitters[lIndex].OnMouseUp := nil;
    FRowSplitters[lIndex].OnDblClick := nil;
  end;
  inherited Destroy;
end;

function TRdcSessionPanes.CreateTabs: TRdcTabStrip;
begin
  Result := TRdcTabStrip.Create(FContainer);
  Result.Parent := FContainer;
  Result.Visible := False;
  Result.OnChange := TabChange;
  Result.OnTabClose := TabClose;
  Result.OnContextPopup := TabContextPopup;
  Result.OnDragDrop := PaneDragDrop;
  Result.OnDragOver := PaneDragOver;
  Result.OnGetImageIndex := TabGetImageIndex;
  Result.OnMouseDown := TabMouseDown;
  Result.OnMouseUp := TabMouseUp;
end;

function TRdcSessionPanes.CreatePlaceholder(aTemplate: TLabel): TLabel;
begin
  Result := TLabel.Create(FContainer);
  Result.Parent := FContainer;
  Result.AutoSize := False;
  Result.Alignment := aTemplate.Alignment;
  Result.Layout := aTemplate.Layout;
  Result.WordWrap := aTemplate.WordWrap;
  Result.ParentFont := False;
  Result.Font := aTemplate.Font;
  Result.StyleElements := aTemplate.StyleElements;
  Result.Caption := aTemplate.Caption;
  Result.Visible := False;
end;

function TRdcSessionPanes.CreateSplitter(aCursor: TCursor; aTag: Integer): TPanel;
begin
  Result := TPanel.Create(FContainer);
  Result.Parent := FContainer;
  Result.BevelOuter := bvNone;
  Result.ParentBackground := False;
  Result.StyleElements := [];
  Result.Color := FSplitterColor;
  Result.Cursor := aCursor;
  Result.Tag := aTag;
  Result.Visible := False;
  Result.OnMouseDown := SplitterMouseDown;
  Result.OnMouseMove := SplitterMouseMove;
  Result.OnMouseUp := SplitterMouseUp;
  Result.OnDblClick := SplitterDblClick;
end;

{ Event-handlers }

procedure TRdcSessionPanes.ContainerResize(Sender: TObject);
begin
  Layout;
end;

procedure TRdcSessionPanes.SplitterDblClick(Sender: TObject);
begin
  FDraggedSplitter := nil;
  Equalize;
end;

procedure TRdcSessionPanes.SplitterMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and not (ssDouble in Shift) then
    FDraggedSplitter := TPanel(Sender);
end;

procedure TRdcSessionPanes.SplitterMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FDraggedSplitter = Sender then
    DragSplitterToCursor;
end;

procedure TRdcSessionPanes.SplitterMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDraggedSplitter := nil;
end;

procedure TRdcSessionPanes.TabChange(Sender: TObject);
begin
  SetActivePane(PaneOfControl(Sender), False);
  DoActiveChanged;
end;

procedure TRdcSessionPanes.TabClose(Sender: TObject; TabIndex: Integer);
var
  lServer: TRdcServer;
begin
  lServer := ServerAtIndex(PaneOfControl(Sender), TabIndex);
  if (lServer <> nil) and Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self, lServer);
end;

procedure TRdcSessionPanes.TabContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  PrepareTabMenu(PaneOfControl(Sender), MousePos, Handled);
end;

procedure TRdcSessionPanes.PlaceholderClick(Sender: TObject);
begin
  // Klik in een leeg vak: dat vak wordt actief, zodat de volgende verbinding daar opent.
  SetActivePane(PaneOfControl(Sender), True);
end;

procedure TRdcSessionPanes.PaneDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  DropDraggedTab(Sender, X, Y);
end;

procedure TRdcSessionPanes.PaneDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
begin
  if ReorderDraggedTab(TRdcTabStrip(Sender), X, Y) then
    Accept := True
  else
    Accept := CanDropDraggedTab(Sender, Source, X, Y);
end;

function TRdcSessionPanes.ReorderDraggedTab(aStrip: TRdcTabStrip; X, Y: Integer): Boolean;
var
  lFrom: Integer;
  lPane: Integer;
  lTarget: Integer;
  lTargetRect: TRect;
  lWidth: Integer;
begin
  // Slepen binnen de eigen tabbalk: volgorde direct aanpassen (zoals in een browser).
  Result := False;
  if FDragServer = nil then
    Exit;
  lPane := PaneOf(FDragServer);
  if (lPane < 0) or (TObject(aStrip) <> FTabs[lPane]) then
    Exit;
  Result := True;
  lFrom := IndexIn(lPane, FDragServer);
  lTarget := aStrip.IndexOfTabAt(X, Y);
  if (lTarget < 0) or (lTarget = lFrom) then
    Exit;
  // Pas verplaatsen als de muis na het verplaatsen óp de gesleepte tab staat; anders springt hij heen en weer bij
  // tabs van verschillende breedte.
  lTargetRect := aStrip.TabBounds(lTarget);
  lWidth := aStrip.TabBounds(lFrom).Width;
  if ((lTarget > lFrom) and (X >= lTargetRect.Right - lWidth)) or ((lTarget < lFrom) and (X < lTargetRect.Left + lWidth)) then
    aStrip.MoveTab(lFrom, lTarget);
end;

procedure TRdcSessionPanes.TabGetImageIndex(Sender: TObject; TabIndex: Integer; var ImageIndex: Integer);
var
  lServer: TRdcServer;
begin
  lServer := ServerAtIndex(PaneOfControl(Sender), TabIndex);
  if (lServer <> nil) and Assigned(FOnTabImage) then
    ImageIndex := FOnTabImage(lServer)
  else
    ImageIndex := -1;
end;

procedure TRdcSessionPanes.TabMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  TabClicked(PaneOfControl(Sender), Button, X, Y);
end;

procedure TRdcSessionPanes.TabMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  TabReleased(PaneOfControl(Sender), Button, X, Y);
end;

{ Hulpfuncties }

function TRdcSessionPanes.Scale(aValue: Integer): Integer;
begin
  Result := MulDiv(aValue, FContainer.CurrentPPI, 96);
end;

function TRdcSessionPanes.PaneOfControl(aControl: TObject): Integer;
var
  lPane: Integer;
begin
  for lPane := 0 to cRdcMaxPanes - 1 do
    if (aControl = FTabs[lPane]) or (aControl = FPlaceholders[lPane]) then
      Exit(lPane);
  Result := -1;
end;

function TRdcSessionPanes.PaneAtContainerPoint(const aPoint: TPoint): Integer;
var
  lPane: Integer;
  lRect: TRect;
begin
  for lPane := 0 to PaneCount - 1 do
  begin
    lRect := FHostRects[lPane];
    lRect.Top := FTabs[lPane].Top;
    if PtInRect(lRect, aPoint) then
      Exit(lPane);
  end;
  Result := -1;
end;

function TRdcSessionPanes.IndexIn(aPane: Integer; aServer: TRdcServer): Integer;
begin
  for Result := 0 to FTabs[aPane].Tabs.Count - 1 do
    if FTabs[aPane].Tabs.Objects[Result] = aServer then
      Exit;
  Result := -1;
end;

function TRdcSessionPanes.ServerAtIndex(aPane, aIndex: Integer): TRdcServer;
begin
  if (aPane >= 0) and (aIndex >= 0) and (aIndex < FTabs[aPane].Tabs.Count) then
    Result := TRdcServer(FTabs[aPane].Tabs.Objects[aIndex])
  else
    Result := nil;
end;

function TRdcSessionPanes.ServerAt(aPane: Integer; X, Y: Integer): TRdcServer;
begin
  Result := ServerAtIndex(aPane, FTabs[aPane].IndexOfTabAt(X, Y));
end;

function TRdcSessionPanes.IsSplit: Boolean;
begin
  Result := PaneCount > 1;
end;

function TRdcSessionPanes.PaneCount: Integer;
begin
  Result := FColumns * FRows;
end;

function TRdcSessionPanes.PaneOf(aServer: TRdcServer): Integer;
var
  lPane: Integer;
begin
  if aServer <> nil then
    for lPane := 0 to cRdcMaxPanes - 1 do
      if IndexIn(lPane, aServer) >= 0 then
        Exit(lPane);
  Result := -1;
end;

function TRdcSessionPanes.Contains(aServer: TRdcServer): Boolean;
begin
  Result := PaneOf(aServer) >= 0;
end;

function TRdcSessionPanes.TabCount: Integer;
var
  lPane: Integer;
begin
  Result := 0;
  for lPane := 0 to cRdcMaxPanes - 1 do
    Inc(Result, FTabs[lPane].Tabs.Count);
end;

function TRdcSessionPanes.ServerOf(aPane: Integer): TRdcServer;
begin
  Result := ServerAtIndex(aPane, FTabs[aPane].TabIndex);
end;

function TRdcSessionPanes.ActiveServer: TRdcServer;
begin
  Result := ServerOf(FActivePane);
end;

function TRdcSessionPanes.HostRect(aPane: Integer): TRect;
begin
  Result := FHostRects[aPane];
end;

procedure TRdcSessionPanes.DoActiveChanged;
begin
  if Assigned(FOnActiveChanged) then
    FOnActiveChanged(Self);
end;

procedure TRdcSessionPanes.DoLayoutChanged;
begin
  if Assigned(FOnLayoutChanged) then
    FOnLayoutChanged(Self);
end;

procedure TRdcSessionPanes.SetColumnRatios(const aValue: TArray<Double>);
begin
  FColumnRatios := NormalizedRatios(aValue, FColumns);
end;

procedure TRdcSessionPanes.SetRowRatios(const aValue: TArray<Double>);
begin
  FRowRatios := NormalizedRatios(aValue, FRows);
end;

{ Indeling }

procedure TRdcSessionPanes.Layout;
var
  lColumn: Integer;
  lColumnEdges: array[0..cRdcMaxColumns] of Integer;
  lHeight: Integer;
  lIndex: Integer;
  lPane: Integer;
  lPaneRect: TRect;
  lPos: Double;
  lRow: Integer;
  lRowEdges: array[0..cRdcMaxRows] of Integer;
  lSplitter: Integer;
  lTabHeight: Integer;
  lUsable: Integer;
  lWidth: Integer;
begin
  lWidth := FContainer.ClientWidth;
  lHeight := FContainer.ClientHeight;
  lTabHeight := Scale(cTabHeight);
  lSplitter := Scale(cSplitterSize);

  // Grenzen: lColumnEdges[i] = linkerkant van kolom i; lColumnEdges[n] = rand + splitter (rekentruc voor de laatste kolom).
  lUsable := Max(0, lWidth - (FColumns - 1) * lSplitter);
  lPos := 0;
  for lColumn := 0 to FColumns - 1 do
  begin
    lColumnEdges[lColumn] := Round(lPos) + lColumn * lSplitter;
    lPos := lPos + FColumnRatios[lColumn] * lUsable;
  end;
  lColumnEdges[FColumns] := lWidth + lSplitter;
  lUsable := Max(0, lHeight - (FRows - 1) * lSplitter);
  lPos := 0;
  for lRow := 0 to FRows - 1 do
  begin
    lRowEdges[lRow] := Round(lPos) + lRow * lSplitter;
    lPos := lPos + FRowRatios[lRow] * lUsable;
  end;
  lRowEdges[FRows] := lHeight + lSplitter;

  for lIndex := 0 to High(FColumnSplitters) do
  begin
    FColumnSplitters[lIndex].Visible := lIndex < FColumns - 1;
    if lIndex < FColumns - 1 then
      FColumnSplitters[lIndex].SetBounds(lColumnEdges[lIndex + 1] - lSplitter, 0, lSplitter, lHeight);
  end;
  for lIndex := 0 to High(FRowSplitters) do
  begin
    FRowSplitters[lIndex].Visible := lIndex < FRows - 1;
    if lIndex < FRows - 1 then
      FRowSplitters[lIndex].SetBounds(0, lRowEdges[lIndex + 1] - lSplitter, lWidth, lSplitter);
  end;

  for lPane := 0 to cRdcMaxPanes - 1 do
  begin
    FTabs[lPane].Visible := lPane < PaneCount;
    if lPane >= PaneCount then
    begin
      FHostRects[lPane] := Rect(0, 0, 0, 0);
      Continue;
    end;
    lColumn := lPane mod FColumns;
    lRow := lPane div FColumns;
    lPaneRect := Rect(lColumnEdges[lColumn], lRowEdges[lRow], lColumnEdges[lColumn + 1] - lSplitter, lRowEdges[lRow + 1] - lSplitter);
    FTabs[lPane].SetBounds(lPaneRect.Left, lPaneRect.Top, Max(0, lPaneRect.Width), lTabHeight);
    FHostRects[lPane] := Rect(lPaneRect.Left, lPaneRect.Top + lTabHeight, lPaneRect.Right, Max(lPaneRect.Top + lTabHeight, lPaneRect.Bottom));
    FPlaceholders[lPane].BoundsRect := FHostRects[lPane];
  end;
  UpdatePlaceholders;
  UpdateIndicators;
  DoLayoutChanged;
end;

procedure TRdcSessionPanes.UpdatePlaceholders;
var
  lPane: Integer;
  lText: string;
begin
  if PaneCount = 1 then
    lText := FEmptyText
  else
    lText := FEmptyPaneText;
  for lPane := 0 to cRdcMaxPanes - 1 do
  begin
    FPlaceholders[lPane].Visible := (lPane < PaneCount) and ((FTabs[lPane].Tabs.Count = 0) or (FNotes[lPane] <> ''));
    if (FNotes[lPane] <> '') and (FTabs[lPane].Tabs.Count > 0) then
      FPlaceholders[lPane].Caption := FNotes[lPane]
    else
      FPlaceholders[lPane].Caption := lText;
  end;
end;

procedure TRdcSessionPanes.UpdateIndicators;
var
  lPane: Integer;
begin
  // Accentlijn onder de geselecteerde tab alleen in het actieve vak (bij één vak altijd).
  for lPane := 0 to cRdcMaxPanes - 1 do
    FTabs[lPane].ActiveIndicator := lPane = FActivePane;
end;

procedure TRdcSessionPanes.ApplyColors(aDark: Boolean);
var
  lIndex: Integer;
  lText: TColor;
begin
  if aDark then
  begin
    TPanel(FContainer).Color := $00302D2B;
    FSplitterColor := $00403D3B;
    lText := $00D0D0D0;
  end
  else
  begin
    TPanel(FContainer).Color := $00EBE8E6;
    FSplitterColor := $00D2CFCC;
    lText := $00605C59;
  end;
  for lIndex := 0 to High(FColumnSplitters) do
    FColumnSplitters[lIndex].Color := FSplitterColor;
  for lIndex := 0 to High(FRowSplitters) do
    FRowSplitters[lIndex].Color := FSplitterColor;
  for lIndex := 0 to cRdcMaxPanes - 1 do
    FPlaceholders[lIndex].Font.Color := lText;
end;

procedure TRdcSessionPanes.SetGrid(aColumns, aRows: Integer);
var
  lPane: Integer;
  lServer: TRdcServer;
begin
  aColumns := EnsureRange(aColumns, 1, cRdcMaxColumns);
  aRows := EnsureRange(aRows, 1, cRdcMaxRows);
  if (aColumns = FColumns) and (aRows = FRows) then
    Exit;
  // Minder vakken: tabs van de vervallen vakken naar het eerste vak; de actieve sessie blijft actief.
  lServer := ActiveServer;
  for lPane := aColumns * aRows to cRdcMaxPanes - 1 do
    while FTabs[lPane].Tabs.Count > 0 do
    begin
      FTabs[0].Tabs.AddObject(FTabs[lPane].Tabs[0], FTabs[lPane].Tabs.Objects[0]);
      FTabs[lPane].Tabs.Delete(0);
    end;
  if aColumns <> FColumns then
    FColumnRatios := EqualRatios(aColumns);
  if aRows <> FRows then
    FRowRatios := EqualRatios(aRows);
  FColumns := aColumns;
  FRows := aRows;
  if FActivePane >= PaneCount then
  begin
    FActivePane := 0;
    if lServer <> nil then
      FTabs[0].TabIndex := IndexIn(0, lServer);
  end;
  if (FTabs[0].TabIndex < 0) and (FTabs[0].Tabs.Count > 0) then
    FTabs[0].TabIndex := 0;
  Layout;
  UpdateImages;
end;

procedure TRdcSessionPanes.Equalize;
begin
  FColumnRatios := EqualRatios(FColumns);
  FRowRatios := EqualRatios(FRows);
  Layout;
end;

procedure TRdcSessionPanes.SetImages(aImages: TCustomImageList);
var
  lPane: Integer;
begin
  for lPane := 0 to cRdcMaxPanes - 1 do
    FTabs[lPane].Images := aImages;
end;

procedure TRdcSessionPanes.SetActivePane(aPane: Integer; aNotify: Boolean);
var
  lChanged: Boolean;
begin
  if (aPane < 0) or (aPane >= PaneCount) then
    aPane := 0;
  lChanged := aPane <> FActivePane;
  FActivePane := aPane;
  UpdateIndicators;
  if lChanged and aNotify then
    DoActiveChanged;
end;

procedure TRdcSessionPanes.MoveBoundary(var aRatios: TArray<Double>; aIndex: Integer; aCursor, aTotal: Integer);
var
  lMin: Double;
  lPair: Double;
  lSplitter: Integer;
  lStart: Double;
  lUsable: Integer;
begin
  // Alleen de grens tussen deel aIndex en aIndex+1 verschuift; de andere kolommen/rijen blijven staan.
  lSplitter := Scale(cSplitterSize);
  lUsable := Max(1, aTotal - (Length(aRatios) - 1) * lSplitter);
  lStart := SumOfRatios(aRatios, aIndex);
  lPair := aRatios[aIndex] + aRatios[aIndex + 1];
  lMin := Min(Scale(cMinPaneSize) / lUsable, lPair / 2);
  aRatios[aIndex] := EnsureRange((aCursor - aIndex * lSplitter - lSplitter / 2) / lUsable - lStart, lMin, lPair - lMin);
  aRatios[aIndex + 1] := lPair - aRatios[aIndex];
end;

procedure TRdcSessionPanes.DragSplitterToCursor;
var
  lPoint: TPoint;
begin
  if FDraggedSplitter = nil then
    Exit;
  lPoint := FContainer.ScreenToClient(Mouse.CursorPos);
  if FDraggedSplitter.Tag < cRowSplitterTag then
    MoveBoundary(FColumnRatios, FDraggedSplitter.Tag, lPoint.X, FContainer.ClientWidth)
  else
    MoveBoundary(FRowRatios, FDraggedSplitter.Tag - cRowSplitterTag, lPoint.Y, FContainer.ClientHeight);
  Layout;
end;

{ Tabs }

function TabCaptionOf(aServer: TRdcServer): string;
var
  lLabel: string;
  lLabels: TArray<string>;
  lNumeric: Boolean;
  lValue: Integer;
begin
  // Tab: de naam zonder domein (dc01.contoso.local -> dc01), tenzij de server een eigen weergavenaam heeft.
  // IP-adressen blijven heel.
  Result := aServer.Caption;
  if (aServer.DisplayName <> '') or (Pos('.', Result) = 0) or (Pos(':', Result) > 0) then
    Exit;
  lLabels := Result.Split(['.']);
  lNumeric := True;
  for lLabel in lLabels do
    if not TryStrToInt(lLabel, lValue) then
      lNumeric := False;
  if not lNumeric and (lLabels[0] <> '') then
    Result := lLabels[0];
end;

procedure TRdcSessionPanes.AddToPane(aPane: Integer; aServer: TRdcServer);
begin
  FTabs[aPane].TabIndex := FTabs[aPane].Tabs.AddObject(TabCaptionOf(aServer), aServer);
end;

procedure TRdcSessionPanes.DeleteFromPane(aPane: Integer; aServer: TRdcServer);
var
  lIndex: Integer;
begin
  lIndex := IndexIn(aPane, aServer);
  if lIndex < 0 then
    Exit;
  FTabs[aPane].Tabs.Delete(lIndex);
  if FTabs[aPane].Tabs.Count > 0 then
    FTabs[aPane].TabIndex := Min(lIndex, FTabs[aPane].Tabs.Count - 1)
  else
    FTabs[aPane].TabIndex := -1;
end;

procedure TRdcSessionPanes.Activate(aServer: TRdcServer);
var
  lPane: Integer;
begin
  lPane := PaneOf(aServer);
  if lPane < 0 then
  begin
    lPane := FActivePane;
    AddToPane(lPane, aServer);
  end
  else
    FTabs[lPane].TabIndex := IndexIn(lPane, aServer);
  SetActivePane(lPane, False);
  UpdatePlaceholders;
  UpdateImages;
end;

procedure TRdcSessionPanes.ActivatePaneOf(aServer: TRdcServer);
var
  lPane: Integer;
begin
  lPane := PaneOf(aServer);
  if lPane >= 0 then
    SetActivePane(lPane, True);
end;

procedure TRdcSessionPanes.Remove(aServer: TRdcServer);
var
  lPane: Integer;
begin
  lPane := PaneOf(aServer);
  if lPane >= 0 then
    DeleteFromPane(lPane, aServer);
  if FMenuServer = aServer then
    FMenuServer := nil;
  if FDragServer = aServer then
    FDragServer := nil;
  UpdatePlaceholders;
  UpdateImages;
end;

procedure TRdcSessionPanes.MoveServer(aServer: TRdcServer; aTarget: Integer);
var
  lSource: Integer;
begin
  lSource := PaneOf(aServer);
  if (lSource < 0) or (aTarget < 0) or (aTarget >= PaneCount) or (lSource = aTarget) then
    Exit;
  DeleteFromPane(lSource, aServer);
  AddToPane(aTarget, aServer);
  SetActivePane(aTarget, False);
  UpdatePlaceholders;
  UpdateImages;
  DoActiveChanged;
end;

procedure TRdcSessionPanes.MoveToNextPane(aServer: TRdcServer);
var
  lPane: Integer;
begin
  lPane := PaneOf(aServer);
  if (lPane >= 0) and IsSplit then
    MoveServer(aServer, (lPane + 1) mod PaneCount);
end;

procedure TRdcSessionPanes.SelectPane(aPane: Integer);
begin
  SetActivePane(aPane, False);
end;

procedure TRdcSessionPanes.SetPaneNote(aPane: Integer; const aText: string);
begin
  if (aPane < 0) or (aPane >= cRdcMaxPanes) or (FNotes[aPane] = aText) then
    Exit;
  FNotes[aPane] := aText;
  UpdatePlaceholders;
end;

procedure TRdcSessionPanes.UpdateCaption(aServer: TRdcServer);
var
  lPane: Integer;
begin
  lPane := PaneOf(aServer);
  if lPane >= 0 then
    FTabs[lPane].Tabs[IndexIn(lPane, aServer)] := TabCaptionOf(aServer);
end;

procedure TRdcSessionPanes.UpdateImages;
var
  lPane: Integer;
begin
  for lPane := 0 to cRdcMaxPanes - 1 do
    FTabs[lPane].UpdateTabImages;
end;

function TRdcSessionPanes.CanDropDraggedTab(aSender, aSource: TObject; X, Y: Integer): Boolean;
var
  lTarget: Integer;
begin
  Result := False;
  if (FDragServer = nil) or not (aSource is TRdcTabStrip) then
    Exit;
  lTarget := PaneOfControl(aSender);
  if (lTarget < 0) and (aSender = FContainer) then
    lTarget := PaneAtContainerPoint(Point(X, Y));
  Result := (lTarget >= 0) and (lTarget < PaneCount) and (lTarget <> PaneOf(FDragServer));
end;

procedure TRdcSessionPanes.DropDraggedTab(aSender: TObject; X, Y: Integer);
var
  lTarget: Integer;
begin
  if FDragServer = nil then
    Exit;
  lTarget := PaneOfControl(aSender);
  if (lTarget < 0) and (aSender = FContainer) then
    lTarget := PaneAtContainerPoint(Point(X, Y));
  // Losgelaten in het eigen vak: de volgorde is al aangepast tijdens het slepen.
  if lTarget = PaneOf(FDragServer) then
    Exit;
  MoveServer(FDragServer, lTarget);
end;

procedure TRdcSessionPanes.TabClicked(aPane: Integer; aButton: TMouseButton; X, Y: Integer);
begin
  // Klik op een tabbalk maakt dat vak actief (ook als de tab al geselecteerd was). Een tab kan gesleept worden:
  // binnen de balk om de volgorde te wijzigen, of naar een ander vak.
  if aButton <> mbLeft then
    Exit;
  SetActivePane(aPane, True);
  FDragServer := ServerAt(aPane, X, Y);
  if FDragServer <> nil then
    FTabs[aPane].BeginDrag(False, Mouse.DragThreshold);
end;

procedure TRdcSessionPanes.TabReleased(aPane: Integer; aButton: TMouseButton; X, Y: Integer);
var
  lServer: TRdcServer;
begin
  if aButton <> mbMiddle then
    Exit;
  lServer := ServerAt(aPane, X, Y);
  if (lServer <> nil) and Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self, lServer);
end;

procedure TRdcSessionPanes.PrepareTabMenu(aPane: Integer; const aMousePos: TPoint; var aHandled: Boolean);
begin
  // Het menu werkt op de tab waarop geklikt is (niet per se de actieve tab). Geen tab = geen menu.
  if (aMousePos.X < 0) and (aMousePos.Y < 0) then
    FMenuServer := ServerOf(aPane) // via toetsenbord
  else
    FMenuServer := ServerAt(aPane, aMousePos.X, aMousePos.Y);
  aHandled := FMenuServer = nil;
end;

end.
