unit RdcmX.Rdp.Host;

{
  TRdpHost: de vaste host-window van één RDP-sessie.

  Waarom een aparte host?
  Het wijzigen van de VCL-Parent van een TOleControl (of van een container waar hij in zit) recreëert de
  window handle van de control en verbreekt daarmee de RDP-sessie. Elke sessie krijgt daarom precies één
  TRdpHost die de ActiveX-control bevat. De ActiveX-control verhuist nooit; alleen de host wordt
  (vanaf fase 4) op handle-niveau verplaatst.

  Gekozen aanpak voor undock/fullscreen/thumbnails (fase 4):
  - De VCL-Parent van de host blijft altijd hetzelfde (het sessiegebied van het hoofdvenster) en wordt nooit
    gewijzigd. Align blijft dan alNone en de eigenaar van de weergave positioneert de host zelf.
  - Voor weergave in een ander venster wordt de host via Winapi.Windows.SetParent op handle-niveau verplaatst.
    Omdat de VCL-Parent gelijk blijft, recreëert de VCL nooit de handle van host of control.
  Sinds het gesplitste sessiegebied staat de host met Align = alNone en zet RdcmX.UI.SessionPanes de positie.

  OnActivated: klikken in de sessie gaat naar de ActiveX-vensters, niet naar de VCL. Windows meldt een
  muisklik in een kindvenster wel aan alle ouders (WM_PARENTNOTIFY); zo weet het hoofdvenster welk vak actief is.

  Als de ActiveX-control niet zichtbaar is (niet verbonden, fout), tekent de host zelf een statustekst. Zo
  komen disconnect-meldingen in het sessiepaneel en niet in een modale dialoog.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.Graphics;

type
  TRdpHost = class(TCustomControl)
  private
    FStatusText: string;
    FOnActivated: TNotifyEvent;
    FOnDpiChanged: TNotifyEvent;
    FOnResized: TNotifyEvent;
    procedure DoActivated;
    procedure SetStatusText(const aValue: string);
    procedure WMParentNotify(var aMessage: TWMParentNotify); message WM_PARENTNOTIFY;
    procedure WMDpiChangedAfterParent(var aMessage: TMessage); message WM_DPICHANGED_AFTERPARENT;
    procedure WMEraseBkgnd(var aMessage: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure CreateParams(var aParams: TCreateParams); override;
    procedure MouseDown(aButton: TMouseButton; aShift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(aOwner: TComponent); override;
    property StatusText: string read FStatusText write SetStatusText;
    /// <summary>Muisklik in de host of in de sessie (de ActiveX-control).</summary>
    property OnActivated: TNotifyEvent read FOnActivated write FOnActivated;
    property OnDpiChanged: TNotifyEvent read FOnDpiChanged write FOnDpiChanged;
    property OnResized: TNotifyEvent read FOnResized write FOnResized;
  end;

implementation

{ TRdpHost }

constructor TRdpHost.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csAcceptsControls];
  Color := $00302D2B;
  ParentBackground := False;
  ParentFont := True;
  TabStop := False;
  // Eigen tekenwerk; een VCL-stijl (donkere modus) mag hier niets aan veranderen.
  StyleElements := [];
end;

procedure TRdpHost.DoActivated;
begin
  if Assigned(FOnActivated) then
    FOnActivated(Self);
end;

procedure TRdpHost.MouseDown(aButton: TMouseButton; aShift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(aButton, aShift, X, Y);
  DoActivated;
end;

procedure TRdpHost.WMParentNotify(var aMessage: TWMParentNotify);
begin
  inherited;
  if (aMessage.Event = WM_LBUTTONDOWN) or (aMessage.Event = WM_RBUTTONDOWN) or (aMessage.Event = WM_MBUTTONDOWN) then
    DoActivated;
end;

procedure TRdpHost.CreateParams(var aParams: TCreateParams);
begin
  inherited CreateParams(aParams);
  aParams.Style := aParams.Style or WS_CLIPCHILDREN or WS_CLIPSIBLINGS;
end;

procedure TRdpHost.Paint;
var
  lRect: TRect;
  lTextRect: TRect;
begin
  lRect := ClientRect;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(lRect);
  if FStatusText = '' then
    Exit;
  Canvas.Font := Font;
  Canvas.Font.Color := $00E0E0E0;
  Canvas.Brush.Style := bsClear;
  InflateRect(lRect, -MulDiv(24, CurrentPPI, 96), -MulDiv(24, CurrentPPI, 96));
  lTextRect := lRect;
  DrawText(Canvas.Handle, PChar(FStatusText), Length(FStatusText), lTextRect, DT_CENTER or DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  OffsetRect(lTextRect, 0, (lRect.Height - lTextRect.Height) div 2);
  lTextRect.Left := lRect.Left;
  lTextRect.Right := lRect.Right;
  DrawText(Canvas.Handle, PChar(FStatusText), Length(FStatusText), lTextRect, DT_CENTER or DT_WORDBREAK or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
end;

procedure TRdpHost.Resize;
begin
  inherited Resize;
  Invalidate;
  if Assigned(FOnResized) then
    FOnResized(Self);
end;

procedure TRdpHost.SetStatusText(const aValue: string);
begin
  if FStatusText = aValue then
    Exit;
  FStatusText := aValue;
  Invalidate;
end;

procedure TRdpHost.WMDpiChangedAfterParent(var aMessage: TMessage);
begin
  inherited;
  if Assigned(FOnDpiChanged) then
    FOnDpiChanged(Self);
end;

procedure TRdpHost.WMEraseBkgnd(var aMessage: TWMEraseBkgnd);
begin
  aMessage.Result := 1;
end;

end.
