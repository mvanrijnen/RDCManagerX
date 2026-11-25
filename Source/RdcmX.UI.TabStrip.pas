unit RdcmX.UI.TabStrip;

{
  TRdcTabStrip: platte, moderne tabbalk voor de sessievakken (vervangt TTabControl).

  - Actieve tab: achtergrond in de vensterkleur met een accentlijn onderaan; andere tabs vlak, hover lichter.
  - Per tab een statusicoon (OnGetImageIndex) en een sluitknop (x) op de actieve tab en bij hover.
  - Kleuren uit StyleServices: licht, donker en de gewone Windows-weergave kloppen vanzelf.
  - API zoals TTabControl (Tabs.Objects, TabIndex, IndexOfTabAt, OnChange), zodat RdcmX.UI.SessionPanes hem
    direct kan gebruiken. OnChange alleen bij een klik van de gebruiker, niet bij het zetten van TabIndex.
  - Zitten er meer tabs in dan passen, dan worden ze smaller (tot een minimum) en vallen de laatste weg;
    het actieve vak toont altijd de geselecteerde tab.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.Math, System.SysUtils, System.Types, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.ImgList, Vcl.Themes;

type
  TRdcTabImageIndexEvent = procedure(Sender: TObject; TabIndex: Integer; var ImageIndex: Integer) of object;
  TRdcTabCloseEvent = procedure(Sender: TObject; TabIndex: Integer) of object;

  TRdcTabStrip = class(TCustomControl)
  private
    FTabs: TStringList;
    FTabIndex: Integer;
    FHotIndex: Integer;
    FHotClose: Boolean;
    FPressedClose: Integer;
    FImages: TCustomImageList;
    FActiveIndicator: Boolean;
    FOnChange: TNotifyEvent;
    FOnGetImageIndex: TRdcTabImageIndexEvent;
    FOnTabClose: TRdcTabCloseEvent;
    procedure TabsChanged(Sender: TObject);
    procedure SetTabIndex(aValue: Integer);
    procedure SetImages(aValue: TCustomImageList);
    procedure SetActiveIndicator(aValue: Boolean);
    function Scale(aValue: Integer): Integer;
    function NaturalWidth(aIndex: Integer): Integer;
    function TabWidths: TArray<Integer>;
    function TabRect(aIndex: Integer): TRect;
    function CloseRect(const aTabRect: TRect): TRect;
    function ShowsClose(aIndex: Integer): Boolean;
    procedure UpdateHot(X, Y: Integer);
    procedure CMMouseLeave(var aMessage: TMessage); message CM_MOUSELEAVE;
    procedure WMEraseBkgnd(var aMessage: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    function IndexOfTabAt(X, Y: Integer): Integer;
    /// <summary>Plaats van tab aIndex (client-coördinaten).</summary>
    function TabBounds(aIndex: Integer): TRect;
    /// <summary>Tab aFrom naar positie aTo verplaatsen (de geselecteerde tab blijft geselecteerd).</summary>
    procedure MoveTab(aFrom, aTo: Integer);
    /// <summary>Statusiconen opnieuw ophalen (zelfde naam als TTabControl).</summary>
    procedure UpdateTabImages;
    property Tabs: TStringList read FTabs;
    property TabIndex: Integer read FTabIndex write SetTabIndex;
    property Images: TCustomImageList read FImages write SetImages;
    /// <summary>Accentlijn onder de actieve tab tonen (alleen in het actieve vak).</summary>
    property ActiveIndicator: Boolean read FActiveIndicator write SetActiveIndicator;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnGetImageIndex: TRdcTabImageIndexEvent read FOnGetImageIndex write FOnGetImageIndex;
    property OnTabClose: TRdcTabCloseEvent read FOnTabClose write FOnTabClose;
    property OnContextPopup;
    property OnDragDrop;
    property OnDragOver;
    property OnMouseDown;
    property OnMouseUp;
    property PopupMenu;
  end;

implementation

const
  cMinTabWidth = 60;
  cPadding = 10;
  cCloseSize = 18;
  cAccentHeight = 2;

function BlendColor(aColor1, aColor2: TColor; aPercent2: Integer): TColor;
var
  lColor1: TColorRef;
  lColor2: TColorRef;
begin
  lColor1 := ColorToRGB(aColor1);
  lColor2 := ColorToRGB(aColor2);
  Result := RGB(
    (GetRValue(lColor1) * (100 - aPercent2) + GetRValue(lColor2) * aPercent2) div 100,
    (GetGValue(lColor1) * (100 - aPercent2) + GetGValue(lColor2) * aPercent2) div 100,
    (GetBValue(lColor1) * (100 - aPercent2) + GetBValue(lColor2) * aPercent2) div 100);
end;

function IconFontName: string;
begin
  // Windows 11: Segoe Fluent Icons; Windows 10: Segoe MDL2 Assets.
  if Screen.Fonts.IndexOf('Segoe Fluent Icons') >= 0 then
    Result := 'Segoe Fluent Icons'
  else
    Result := 'Segoe MDL2 Assets';
end;

{ TRdcTabStrip }

constructor TRdcTabStrip.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csAcceptsControls];
  StyleElements := [];
  DoubleBuffered := True;
  ParentFont := True;
  TabStop := False;
  FTabs := TStringList.Create;
  FTabs.OnChange := TabsChanged;
  FTabIndex := -1;
  FHotIndex := -1;
  FPressedClose := -1;
  FActiveIndicator := True;
end;

destructor TRdcTabStrip.Destroy;
begin
  FTabs.OnChange := nil;
  FTabs.Free;
  inherited Destroy;
end;

function TRdcTabStrip.Scale(aValue: Integer): Integer;
begin
  Result := MulDiv(aValue, CurrentPPI, 96);
end;

procedure TRdcTabStrip.TabsChanged(Sender: TObject);
begin
  if FTabIndex >= FTabs.Count then
    FTabIndex := FTabs.Count - 1;
  FHotIndex := -1;
  Invalidate;
end;

procedure TRdcTabStrip.SetTabIndex(aValue: Integer);
begin
  if (aValue < -1) or (aValue >= FTabs.Count) then
    aValue := -1;
  if aValue = FTabIndex then
    Exit;
  FTabIndex := aValue;
  Invalidate;
end;

procedure TRdcTabStrip.SetImages(aValue: TCustomImageList);
begin
  FImages := aValue;
  Invalidate;
end;

procedure TRdcTabStrip.SetActiveIndicator(aValue: Boolean);
begin
  if aValue = FActiveIndicator then
    Exit;
  FActiveIndicator := aValue;
  Invalidate;
end;

procedure TRdcTabStrip.UpdateTabImages;
begin
  Invalidate;
end;

function TRdcTabStrip.NaturalWidth(aIndex: Integer): Integer;
var
  lTextWidth: Integer;
begin
  // Precies passend: marge + icoon + naam + ruimte voor de sluitknop (altijd gereserveerd, zodat de tab niet
  // verspringt als de knop verschijnt) + marge.
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    lTextWidth := Canvas.TextWidth(FTabs[aIndex]);
  end
  else
    lTextWidth := Scale(7) * Length(FTabs[aIndex]);
  Result := Scale(cPadding) + lTextWidth + Scale(4) + Scale(cCloseSize) + Scale(6);
  if FImages <> nil then
    Inc(Result, FImages.Width + Scale(6));
  Result := Max(Result, Scale(cMinTabWidth));
end;

function TRdcTabStrip.TabWidths: TArray<Integer>;
var
  lCap: Integer;
  lHigh: Integer;
  lIndex: Integer;
  lLow: Integer;
  lMid: Integer;
  lNatural: TArray<Integer>;
  lTotal: Integer;

  function TotalWithCap(aCap: Integer): Integer;
  var
    lItem: Integer;
  begin
    Result := 0;
    for lItem in lNatural do
      Inc(Result, Min(lItem, aCap));
  end;

begin
  SetLength(lNatural, FTabs.Count);
  lTotal := 0;
  for lIndex := 0 to FTabs.Count - 1 do
  begin
    lNatural[lIndex] := NaturalWidth(lIndex);
    Inc(lTotal, lNatural[lIndex]);
  end;
  Result := lNatural;
  if (lTotal <= ClientWidth) or (FTabs.Count = 0) then
    Exit;
  // Te breed: de breedste tabs eerst inkorten (tot een gemeenschappelijk maximum), de naam krijgt dan "...".
  lLow := Scale(cMinTabWidth);
  lHigh := MaxIntValue(lNatural);
  while lLow < lHigh do
  begin
    lMid := (lLow + lHigh + 1) div 2;
    if TotalWithCap(lMid) <= ClientWidth then
      lLow := lMid
    else
      lHigh := lMid - 1;
  end;
  lCap := lLow;
  for lIndex := 0 to High(Result) do
    Result[lIndex] := Min(Result[lIndex], lCap);
end;

function TRdcTabStrip.TabRect(aIndex: Integer): TRect;
var
  lIndex: Integer;
  lLeft: Integer;
  lWidths: TArray<Integer>;
begin
  lWidths := TabWidths;
  lLeft := 0;
  for lIndex := 0 to aIndex - 1 do
    Inc(lLeft, lWidths[lIndex]);
  Result := Rect(lLeft, 0, lLeft + lWidths[aIndex], ClientHeight);
end;

function TRdcTabStrip.CloseRect(const aTabRect: TRect): TRect;
var
  lSize: Integer;
begin
  lSize := Scale(cCloseSize);
  Result.Right := aTabRect.Right - Scale(6);
  Result.Left := Result.Right - lSize;
  Result.Top := aTabRect.Top + (aTabRect.Height - lSize) div 2;
  Result.Bottom := Result.Top + lSize;
end;

function TRdcTabStrip.ShowsClose(aIndex: Integer): Boolean;
begin
  Result := (aIndex = FTabIndex) or (aIndex = FHotIndex);
end;

function TRdcTabStrip.TabBounds(aIndex: Integer): TRect;
begin
  Result := TabRect(aIndex);
end;

procedure TRdcTabStrip.MoveTab(aFrom, aTo: Integer);
var
  lSelected: TObject;
begin
  if (aFrom = aTo) or (aFrom < 0) or (aTo < 0) or (aFrom >= FTabs.Count) or (aTo >= FTabs.Count) then
    Exit;
  if FTabIndex >= 0 then
    lSelected := FTabs.Objects[FTabIndex]
  else
    lSelected := nil;
  FTabs.Move(aFrom, aTo);
  if lSelected <> nil then
    FTabIndex := FTabs.IndexOfObject(lSelected);
  Invalidate;
end;

function TRdcTabStrip.IndexOfTabAt(X, Y: Integer): Integer;
var
  lIndex: Integer;
  lLeft: Integer;
  lWidths: TArray<Integer>;
begin
  Result := -1;
  if (Y < 0) or (Y >= ClientHeight) or (X < 0) then
    Exit;
  lWidths := TabWidths;
  lLeft := 0;
  for lIndex := 0 to High(lWidths) do
  begin
    if X < lLeft + lWidths[lIndex] then
      Exit(lIndex);
    Inc(lLeft, lWidths[lIndex]);
  end;
end;

procedure TRdcTabStrip.UpdateHot(X, Y: Integer);
var
  lHot: Integer;
  lHotClose: Boolean;
begin
  lHot := IndexOfTabAt(X, Y);
  lHotClose := (lHot >= 0) and PtInRect(CloseRect(TabRect(lHot)), Point(X, Y));
  if (lHot <> FHotIndex) or (lHotClose <> FHotClose) then
  begin
    FHotIndex := lHot;
    FHotClose := lHotClose;
    Invalidate;
  end;
end;

procedure TRdcTabStrip.CMMouseLeave(var aMessage: TMessage);
begin
  inherited;
  FHotIndex := -1;
  FHotClose := False;
  Invalidate;
end;

procedure TRdcTabStrip.WMEraseBkgnd(var aMessage: TWMEraseBkgnd);
begin
  aMessage.Result := 1;
end;

procedure TRdcTabStrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  lIndex: Integer;
begin
  lIndex := IndexOfTabAt(X, Y);
  if (Button = mbLeft) and (lIndex >= 0) then
  begin
    if ShowsClose(lIndex) and PtInRect(CloseRect(TabRect(lIndex)), Point(X, Y)) then
      FPressedClose := lIndex // sluiten pas bij loslaten op dezelfde knop
    else if lIndex <> FTabIndex then
    begin
      FTabIndex := lIndex;
      Invalidate;
      if Assigned(FOnChange) then
        FOnChange(Self);
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TRdcTabStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  UpdateHot(X, Y);
  inherited MouseMove(Shift, X, Y);
end;

procedure TRdcTabStrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  lIndex: Integer;
begin
  lIndex := FPressedClose;
  FPressedClose := -1;
  if (Button = mbLeft) and (lIndex >= 0) and (lIndex = IndexOfTabAt(X, Y)) and PtInRect(CloseRect(TabRect(lIndex)), Point(X, Y)) and Assigned(FOnTabClose) then
    FOnTabClose(Self, lIndex);
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TRdcTabStrip.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TRdcTabStrip.Paint;
var
  lAccent: TColor;
  lActiveBack: TColor;
  lBack: TColor;
  lCloseRect: TRect;
  lHotBack: TColor;
  lImageIndex: Integer;
  lIndex: Integer;
  lLine: TColor;
  lRect: TRect;
  lStyle: TCustomStyleServices;
  lText: TColor;
  lTextRect: TRect;
  lCaption: string;
  lGlyph: string;
begin
  // De actieve stijl zelf (niet StyleServices(Self)): deze control heeft StyleElements = [] en zou dan de
  // systeemkleuren krijgen, ook in donker.
  lStyle := TStyleManager.ActiveStyle;
  lBack := lStyle.GetSystemColor(clBtnFace);
  lActiveBack := lStyle.GetSystemColor(clWindow);
  lText := lStyle.GetSystemColor(clWindowText);
  lAccent := lStyle.GetSystemColor(clHighlight);
  lHotBack := BlendColor(lBack, lText, 8);
  lLine := BlendColor(lBack, lText, 18);

  Canvas.Brush.Color := lBack;
  Canvas.FillRect(ClientRect);
  // Dunne scheidingslijn onderaan, zodat de balk loskomt van de sessie.
  Canvas.Pen.Color := lLine;
  Canvas.MoveTo(0, ClientHeight - 1);
  Canvas.LineTo(ClientWidth, ClientHeight - 1);

  Canvas.Font := Font;
  for lIndex := 0 to FTabs.Count - 1 do
  begin
    lRect := TabRect(lIndex);
    if lRect.Left >= ClientWidth then
      Break;
    if lIndex = FTabIndex then
      Canvas.Brush.Color := lActiveBack
    else if lIndex = FHotIndex then
      Canvas.Brush.Color := lHotBack
    else
      Canvas.Brush.Color := lBack;
    Canvas.FillRect(Rect(lRect.Left, lRect.Top, lRect.Right, lRect.Bottom - 1));

    if (lIndex = FTabIndex) and FActiveIndicator then
    begin
      Canvas.Brush.Color := lAccent;
      Canvas.FillRect(Rect(lRect.Left, lRect.Bottom - Scale(cAccentHeight), lRect.Right, lRect.Bottom));
    end
    else if (lIndex <> FTabIndex) and (lIndex + 1 <> FTabIndex) and (lIndex <> FHotIndex) and (lIndex + 1 <> FHotIndex) then
    begin
      // Subtiele scheiding tussen twee niet-actieve tabs.
      Canvas.Pen.Color := lLine;
      Canvas.MoveTo(lRect.Right - 1, lRect.Top + Scale(8));
      Canvas.LineTo(lRect.Right - 1, lRect.Bottom - Scale(8));
    end;

    lTextRect := Rect(lRect.Left + Scale(cPadding), lRect.Top, lRect.Right - Scale(cPadding), lRect.Bottom);
    lImageIndex := -1;
    if (FImages <> nil) and Assigned(FOnGetImageIndex) then
      FOnGetImageIndex(Self, lIndex, lImageIndex);
    if lImageIndex >= 0 then
    begin
      FImages.Draw(Canvas, lTextRect.Left, lRect.Top + (lRect.Height - FImages.Height) div 2, lImageIndex);
      Inc(lTextRect.Left, FImages.Width + Scale(6));
    end;
    if ShowsClose(lIndex) then
      lTextRect.Right := CloseRect(lRect).Left - Scale(4);

    Canvas.Brush.Style := bsClear;
    if lIndex = FTabIndex then
      Canvas.Font.Color := lText
    else
      Canvas.Font.Color := BlendColor(lText, lBack, 25);
    lCaption := FTabs[lIndex];
    DrawText(Canvas.Handle, PChar(lCaption), Length(lCaption), lTextRect, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

    if ShowsClose(lIndex) then
    begin
      lCloseRect := CloseRect(lRect);
      if (lIndex = FHotIndex) and FHotClose then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := BlendColor(Canvas.Brush.Color, lText, 15);
        Canvas.FillRect(lCloseRect);
        Canvas.Brush.Style := bsClear;
      end;
      Canvas.Font.Name := IconFontName;
      Canvas.Font.Height := -Scale(10);
      Canvas.Font.Color := lText;
      lGlyph := #$E8BB; // ChromeClose
      DrawText(Canvas.Handle, PChar(lGlyph), 1, lCloseRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
      Canvas.Font := Font;
    end;
    Canvas.Brush.Style := bsSolid;
  end;
end;

end.
