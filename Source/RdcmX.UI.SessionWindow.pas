unit RdcmX.UI.SessionWindow;

{
  Eigen venster voor één losgemaakte sessie: gewoon venster (met balk "Volledig scherm" / "Terugzetten") of
  volledig scherm (randloos over de monitor; balk verschijnt als de muis tegen de bovenrand komt).

  - De RDP-host wordt met Winapi.Windows.SetParent in FHostArea gezet door TRdcSessionManager.Detach; dit venster
    geeft alleen de plek door (HostParentHandle/HostRect, OnHostAreaResized).
  - Wisselen tussen venster en volledig scherm = de host naar een NIEUW venster van de andere soort verplaatsen.
    De randstijl van een bestaand venster wordt nooit gewijzigd: dat maakt de handle opnieuw aan en zou de
    sessie (als Win32-kind) vernietigen.
  - Sluiten (X) verbreekt niets: het vraagt het hoofdvenster de sessie terug te zetten (OnDockRequest).
  - Eigen taakbalkknop (WS_EX_APPWINDOW, geen eigenaar), zodat het venster los op een andere monitor kan staan.
  - Knoppen zijn TSpeedButtons (nemen geen focus): de RDP-control pakt de toetsenbordfocus terug, en een TButton
    breekt een klik af zodra hij de focus verliest.
  - Het host-gebied (TRdcHostArea) heeft WS_CLIPCHILDREN en vult alleen het deel dat de sessie niet bedekt:
    anders schildert het bij elke formaatwijziging over de sessie heen (geknipper).
  - Tijdens het slepen van de vensterrand (WM_ENTERSIZEMOVE..WM_EXITSIZEMOVE) houdt de sessie zijn grootte; pas
    bij loslaten volgt één nieuwe maat (OnHostAreaResized). Elke tussenmaat zou de RDP-control laten wissen en
    hertekenen. Maximaliseren/herstellen gaat direct.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.Math, System.SysUtils, System.Types, System.UITypes,
  Vcl.Buttons, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  RdcmX.Model;

type
  TRdcSessionWindowEvent = procedure(aSender: TObject; aServer: TRdcServer) of object;

  /// <summary>Plek voor de losgemaakte RDP-host: tekent niets (de host bedekt alles) en knipt kinderen uit.</summary>
  TRdcHostArea = class(TWinControl)
  private
    FOnResized: TNotifyEvent;
    FFillColor: TColor;
    procedure WMEraseBkgnd(var aMessage: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Resize; override;
  public
    constructor Create(aOwner: TComponent); override;
    property OnResized: TNotifyEvent read FOnResized write FOnResized;
  end;

  TfrmSessionWindow = class(TForm)
  private
    FServer: TRdcServer;
    FFullScreen: Boolean;
    FBar: TPanel;
    FTitle: TLabel;
    FDockButton: TSpeedButton;
    FFullScreenButton: TSpeedButton;
    FHostArea: TRdcHostArea;
    FBarTimer: TTimer;
    FSizing: Boolean;
    FOnActivated: TRdcSessionWindowEvent;
    FOnDockRequest: TRdcSessionWindowEvent;
    FOnFullScreenToggle: TRdcSessionWindowEvent;
    FOnHostAreaResized: TRdcSessionWindowEvent;
    // Event-handlers: alleen doorverwijzen.
    procedure WindowActivate(Sender: TObject);
    procedure WindowClose(Sender: TObject; var Action: TCloseAction);
    procedure DockButtonClick(Sender: TObject);
    procedure FullScreenButtonClick(Sender: TObject);
    procedure HostAreaResize(Sender: TObject);
    procedure BarTimerTimer(Sender: TObject);
    // Logica
    function Scale(aValue: Integer): Integer;
    procedure BuildControls;
    procedure LayoutBar;
    procedure UpdateFullScreenBar;
    procedure Notify(aEvent: TRdcSessionWindowEvent);
    procedure WMEnterSizeMove(var aMessage: TMessage); message WM_ENTERSIZEMOVE;
    procedure WMExitSizeMove(var aMessage: TMessage); message WM_EXITSIZEMOVE;
    procedure SizingStarted;
    procedure SizingFinished;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    /// <summary>aArea: werkgebied (venster) of monitor (volledig scherm) waarop het venster komt.</summary>
    constructor CreateFor(aServer: TRdcServer; aFullScreen: Boolean; const aArea: TRect);
    function HostParentHandle: HWND;
    function HostRect: TRect;
    procedure UpdateCaption;
    property FullScreen: Boolean read FFullScreen;
    property Server: TRdcServer read FServer;
    property OnActivated: TRdcSessionWindowEvent read FOnActivated write FOnActivated;
    property OnDockRequest: TRdcSessionWindowEvent read FOnDockRequest write FOnDockRequest;
    property OnFullScreenToggle: TRdcSessionWindowEvent read FOnFullScreenToggle write FOnFullScreenToggle;
    property OnHostAreaResized: TRdcSessionWindowEvent read FOnHostAreaResized write FOnHostAreaResized;
  end;

implementation

{ TRdcHostArea }

procedure TRdcHostArea.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

constructor TRdcHostArea.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  FFillColor := $00302D2B;
end;

procedure TRdcHostArea.WMEraseBkgnd(var aMessage: TWMEraseBkgnd);
var
  lBrush: HBRUSH;
  lRect: TRect;
begin
  // Dankzij WS_CLIPCHILDREN raakt dit alleen het deel naast de sessie (bijv. tijdens het slepen van de rand).
  Winapi.Windows.GetClientRect(Handle, lRect);
  lBrush := CreateSolidBrush(ColorToRGB(FFillColor));
  try
    FillRect(aMessage.DC, lRect, lBrush);
  finally
    DeleteObject(lBrush);
  end;
  aMessage.Result := 1;
end;

procedure TRdcHostArea.Resize;
begin
  inherited Resize;
  if Assigned(FOnResized) then
    FOnResized(Self);
end;

const
  cBarHeight = 34;
  cWindowWidth = 1280;
  cWindowHeight = 800;
  cHotEdge = 3;

constructor TfrmSessionWindow.CreateFor(aServer: TRdcServer; aFullScreen: Boolean; const aArea: TRect);
var
  lHeight: Integer;
  lWidth: Integer;
begin
  inherited CreateNew(nil);
  FServer := aServer;
  FFullScreen := aFullScreen;
  Position := poDesigned;
  if FFullScreen then
  begin
    BorderStyle := bsNone; // vóór het aanmaken van de handle; daarna nooit meer wijzigen
    BoundsRect := aArea;
  end
  else
  begin
    lWidth := Min(MulDiv(cWindowWidth, Screen.PixelsPerInch, 96), aArea.Width);
    lHeight := Min(MulDiv(cWindowHeight, Screen.PixelsPerInch, 96), aArea.Height);
    SetBounds(aArea.Left + (aArea.Width - lWidth) div 2, aArea.Top + (aArea.Height - lHeight) div 2, lWidth, lHeight);
  end;
  OnActivate := WindowActivate;
  OnClose := WindowClose;
  BuildControls;
  UpdateCaption;
end;

procedure TfrmSessionWindow.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // Eigen taakbalkknop en niet gebonden aan het hoofdvenster (los op een andere monitor te zetten).
  Params.ExStyle := Params.ExStyle or WS_EX_APPWINDOW;
  Params.WndParent := 0;
end;

function TfrmSessionWindow.Scale(aValue: Integer): Integer;
begin
  Result := MulDiv(aValue, CurrentPPI, 96);
end;

procedure TfrmSessionWindow.BuildControls;
begin
  FHostArea := TRdcHostArea.Create(Self);
  FHostArea.Parent := Self;
  FHostArea.Align := alClient;
  FHostArea.OnResized := HostAreaResize;

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.BevelOuter := bvNone;
  FBar.Height := Scale(cBarHeight);
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FBar;
  FTitle.Layout := tlCenter;
  FTitle.AutoSize := False;
  FDockButton := TSpeedButton.Create(Self);
  FDockButton.Parent := FBar;
  FDockButton.Flat := True;
  FDockButton.Caption := 'Terugzetten in hoofdvenster';
  FDockButton.OnClick := DockButtonClick;
  FFullScreenButton := TSpeedButton.Create(Self);
  FFullScreenButton.Parent := FBar;
  FFullScreenButton.Flat := True;
  if FFullScreen then
    FFullScreenButton.Caption := 'Venster'
  else
    FFullScreenButton.Caption := 'Volledig scherm';
  FFullScreenButton.OnClick := FullScreenButtonClick;

  if FFullScreen then
  begin
    // Balk over de sessie heen (eigen z-volgorde), alleen zichtbaar als de muis tegen de bovenrand komt.
    FBar.Align := alNone;
    FBar.Visible := False;
    FBarTimer := TTimer.Create(Self);
    FBarTimer.Interval := 200;
    FBarTimer.OnTimer := BarTimerTimer;
  end
  else
    FBar.Align := alTop;
  LayoutBar;
end;

procedure TfrmSessionWindow.LayoutBar;
var
  lButtonHeight: Integer;
  lMargin: Integer;
  lRight: Integer;
  lWidth: Integer;
begin
  lMargin := Scale(6);
  lButtonHeight := Scale(26);
  if FFullScreen then
    FBar.SetBounds(0, 0, ClientWidth, Scale(cBarHeight));
  lRight := FBar.ClientWidth - lMargin;
  lWidth := Scale(190);
  FDockButton.SetBounds(lRight - lWidth, (FBar.ClientHeight - lButtonHeight) div 2, lWidth, lButtonHeight);
  lRight := FDockButton.Left - lMargin;
  lWidth := Scale(130);
  FFullScreenButton.SetBounds(lRight - lWidth, FDockButton.Top, lWidth, lButtonHeight);
  FTitle.SetBounds(Scale(10), 0, Max(0, FFullScreenButton.Left - Scale(20)), FBar.ClientHeight);
end;

function TfrmSessionWindow.HostParentHandle: HWND;
begin
  Result := FHostArea.Handle;
end;

function TfrmSessionWindow.HostRect: TRect;
begin
  Result := FHostArea.ClientRect;
end;

procedure TfrmSessionWindow.UpdateCaption;
begin
  Caption := Format('%s - RDCManagerX', [FServer.Caption]);
  FTitle.Caption := FServer.Caption;
end;

procedure TfrmSessionWindow.Notify(aEvent: TRdcSessionWindowEvent);
begin
  if Assigned(aEvent) then
    aEvent(Self, FServer);
end;

procedure TfrmSessionWindow.UpdateFullScreenBar;
var
  lCursor: TPoint;
  lInside: Boolean;
begin
  // De sessie (ActiveX) krijgt de muisberichten; daarom de cursorpositie volgen.
  lCursor := ScreenToClient(Mouse.CursorPos);
  lInside := (lCursor.X >= 0) and (lCursor.X < ClientWidth) and (GetForegroundWindow = Handle);
  if not FBar.Visible and lInside and (lCursor.Y >= 0) and (lCursor.Y <= Scale(cHotEdge)) then
  begin
    LayoutBar;
    FBar.Visible := True;
    FBar.BringToFront;
  end
  else if FBar.Visible and ((lCursor.Y > FBar.Height + Scale(24)) or not lInside) then
    FBar.Visible := False;
end;

{ Event-handlers }

procedure TfrmSessionWindow.WindowActivate(Sender: TObject);
begin
  Notify(FOnActivated);
end;

procedure TfrmSessionWindow.WindowClose(Sender: TObject; var Action: TCloseAction);
begin
  // Sluiten = terugzetten in het hoofdvenster (niet verbreken); het hoofdvenster ruimt dit venster op.
  Action := caNone;
  Notify(FOnDockRequest);
end;

procedure TfrmSessionWindow.DockButtonClick(Sender: TObject);
begin
  Notify(FOnDockRequest);
end;

procedure TfrmSessionWindow.FullScreenButtonClick(Sender: TObject);
begin
  Notify(FOnFullScreenToggle);
end;

procedure TfrmSessionWindow.HostAreaResize(Sender: TObject);
begin
  if FBar <> nil then
    LayoutBar;
  // Tijdens het slepen van de rand niet bij elke pixel de sessie aanpassen (zie unit-kop).
  if not FSizing then
    Notify(FOnHostAreaResized);
end;

procedure TfrmSessionWindow.WMEnterSizeMove(var aMessage: TMessage);
begin
  inherited;
  SizingStarted;
end;

procedure TfrmSessionWindow.WMExitSizeMove(var aMessage: TMessage);
begin
  inherited;
  SizingFinished;
end;

procedure TfrmSessionWindow.SizingStarted;
begin
  FSizing := True;
end;

procedure TfrmSessionWindow.SizingFinished;
begin
  FSizing := False;
  Notify(FOnHostAreaResized);
end;

procedure TfrmSessionWindow.BarTimerTimer(Sender: TObject);
begin
  UpdateFullScreenBar;
end;

end.
