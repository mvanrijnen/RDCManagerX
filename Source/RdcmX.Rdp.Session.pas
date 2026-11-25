unit RdcmX.Rdp.Session;

{
  TRdpSession: bezit de RDP ActiveX-control (mstscax.dll) van één verbinding.

  Verantwoordelijkheden:
  - De nieuwste beschikbare control-class kiezen (12 -> 11 -> 10 -> 9) en verder alles via interfaces met Supports
    benaderen, zodat oudere Windows-builds netjes degraderen.
  - Connect/disconnect en de state machine: Disconnected -> Connecting -> Connected -> LoggedIn -> Disconnecting.
  - Dynamische resolutie: na OnLoginComplete leidt elke resize van de host (na een debounce) tot
    IMsRdpClient9.UpdateSessionDisplaySettings. Een DPI-wissel doet hetzelfde met de nieuwe schaalfactor.
  - Fallback als dynamische resolutie niet werkt: optioneel reconnecten met de nieuwe afmeting.

  Geen UI-kennis buiten de eigen TRdpHost. Statusmeldingen gaan naar de host (getekende tekst) en via OnLog /
  OnStateChanged naar de eigenaar. Nooit modale dialogen vanuit RDP-events.

  Onzekerheden over het gedrag van de ActiveX-control en hoe die hier worden opgevangen:
  1. UpdateSessionDisplaySettings direct na OnLoginComplete kan mislukken als het display-control-kanaal van
     de server nog niet klaar is. Mislukte aanroepen worden daarom opnieuw geprobeerd met oplopende wachttijd
     (cMaxUpdateAttempts, samen ruim 25 s; een domeincontroller had meer dan 3 s nodig) voordat dynamische resolutie als "niet
     ondersteund" geldt. Gold dat door fouten (niet door een uitblijvende bevestiging), dan wordt het bij de
     volgende afmetingswijziging eerst nog eens dynamisch geprobeerd, pas daarna met de reconnect-fallback.
  2. Een oudere server (vóór Windows 8.1 / Server 2012 R2) kan de aanroep zonder fout accepteren en negeren.
     Daarom wordt na een geslaagde aanroep gewacht op OnRemoteDesktopSizeChange. Komt die er twee keer niet
     binnen cVerifyTimeoutMs, dan geldt dynamische resolutie als niet ondersteund. Dit is een heuristiek.
  3. ulPhysicalWidth/ulPhysicalHeight: volgens de Microsoft-documentatie in millimeters. De opdracht vraagt om
     dezelfde waarden als de pixelafmeting. Standaard volgen we de opdracht; PhysicalSizeInMillimeters schakelt
     om naar millimeters berekend uit de monitor-DPI.
  4. Fallback-reconnect gebruikt eerst IMsRdpClient8.Reconnect(W, H). Welke events die precies afvuurt is niet
     gedocumenteerd, dus de state wordt alleen door de events zelf bijgewerkt. Lukt Reconnect niet, dan volgt
     een gewone disconnect + connect.
}

interface

uses
  Winapi.ActiveX, Winapi.Messages, Winapi.MultiMon, Winapi.Windows,
  System.Classes, System.Math, System.StrUtils, System.SysUtils, System.Types, System.Variants,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.OleCtrls,
  MSTSCLib_TLB,
  RdcmX.Rdp.Host;

type
  TRdpSessionState = (rssDisconnected, rssConnecting, rssConnected, rssLoggedIn, rssDisconnecting);

  TRdpSizeMode = (
    rsmDynamic,      // meeschalen met het venster (standaard)
    rsmClientArea,   // gelijk aan client-gebied, vast bij verbinden
    rsmFixed,        // vaste afmeting
    rsmFullScreen);  // volledig scherm (wordt in fase 4 uitgewerkt; nu: afmeting van de monitor)

  TRdpDynamicSupport = (rdsUnknown, rdsConfirmed, rdsUnsupported);

  TRdpLogEvent = procedure(aSender: TObject; const aMessage: string) of object;

  TRdpConnectionSettings = record
    /// <summary>Adres waarmee de control verbindt (via Tailscale: de lokale forward, bijv. 127.0.0.2).</summary>
    Server: string;
    Port: Integer;
    /// <summary>Naam voor statusteksten (de echte server); leeg = Server.</summary>
    DisplayName: string;
    UserName: string;
    Domain: string;
    Password: string;
    AuthenticationLevel: Cardinal;
    ColorDepth: Integer;
    SizeMode: TRdpSizeMode;
    FixedWidth: Integer;
    FixedHeight: Integer;
    SmartSizing: Boolean;
    ResizeDebounceMs: Integer;
    ReconnectOnResizeFallback: Boolean;
    PhysicalSizeInMillimeters: Boolean;
    // Lokale bronnen
    RedirectClipboard: Boolean;
    RedirectDrives: Boolean;
    RedirectPrinters: Boolean;
    RedirectPorts: Boolean;
    RedirectSmartCards: Boolean;
    RedirectDevices: Boolean;
    /// <summary>0 = lokaal afspelen, 1 = op de remote computer, 2 = geen geluid.</summary>
    AudioRedirectionMode: Integer;
    /// <summary>0 = dynamisch, 1 = gemiddeld, 2 = hoog.</summary>
    AudioQualityMode: Integer;
    AudioCaptureRedirection: Boolean;
    /// <summary>Windows-toetscombinaties: 0 = lokaal, 1 = remote, 2 = alleen remote bij volledig scherm.</summary>
    KeyboardHookMode: Integer;
    /// <summary>Schaal in de sessie in procenten (100..500); 0 = automatisch (volgt de DPI van de monitor).</summary>
    DesktopScale: Cardinal;
    // Verbinding
    ConnectToConsole: Boolean;
    StartProgram: string;
    WorkingDir: string;
    LoadBalanceInfo: string;
    // Extern bureaublad-gateway. Wachtwoord alleen bij route "RDP-gateway" met eigen aanmeldgegevens uit de kluis;
    // anders vraagt Windows er zelf om indien nodig.
    GatewayEnabled: Boolean;
    GatewayHostName: string;
    GatewayBypassLocal: Boolean;
    /// <summary>Gateway-instellingen automatisch detecteren (GatewayProfileUsageMethod 0).</summary>
    GatewayAutoDetect: Boolean;
    GatewayPassword: string;
    GatewayCredSharing: Boolean;
    /// <summary>GatewayCredsSource: 0 = wachtwoord (NTLM), 1 = smartcard, 4 = later kiezen.</summary>
    GatewayCredsSource: Cardinal;
    GatewayUserName: string;
    GatewayDomain: string;
    class function Default: TRdpConnectionSettings; static;
  end;

  TRdpDisplayInfo = record
    HostWidth: Integer;
    HostHeight: Integer;
    SentWidth: Cardinal;
    SentHeight: Cardinal;
    SentDesktopScale: Cardinal;
    SentDeviceScale: Cardinal;
    RemoteWidth: Integer;
    RemoteHeight: Integer;
    Dpi: Integer;
    DynamicSupport: TRdpDynamicSupport;
    SizeMode: TRdpSizeMode;
  end;

  TRdpSession = class
  private
    FHost: TRdpHost;
    FControl: TOleControl;
    FControlClassName: string;
    FClient: IMsRdpClient;
    FSettings: TRdpConnectionSettings;
    FState: TRdpSessionState;
    FDestroying: Boolean;
    FUserDisconnect: Boolean;
    FReconnectPending: Boolean;
    FUnsupportedByError: Boolean;   // "niet ondersteund" door mislukte aanroepen (kan ook "te vroeg" zijn)
    FPreparing: Boolean;            // BeginPrepare..Connect/PrepareFailed (bijv. Tailscale-netwerk starten)
    FResizeReconnecting: Boolean;   // IMsRdpClient8.Reconnect(W, H) loopt
    FResizeReconnectFailed: Boolean; // die mislukte eerder: niet opnieuw proberen (blijft over Connect heen staan)
    FDynamicSupport: TRdpDynamicSupport;
    FLastDisconnectReason: Integer;
    FLastDisconnectText: string;
    FSentWidth: Cardinal;
    FSentHeight: Cardinal;
    FSentDesktopScale: Cardinal;
    FSentDeviceScale: Cardinal;
    FRemoteWidth: Integer;
    FRemoteHeight: Integer;
    FUpdateFailures: Integer;
    FVerifyMisses: Integer;
    FResizeTimer: TTimer;
    FVerifyTimer: TTimer;
    FMsgWnd: HWND;
    FLastError: string;
    FData: TObject;
    FOriginalControlWndProc: TWndMethod;
    FOnDisplayChanged: TNotifyEvent;
    FOnLog: TRdpLogEvent;
    FOnStateChanged: TNotifyEvent;
    procedure ApplyConnectSettings(aWidth, aHeight: Integer);
    procedure ApplyConnectionOptions(aAdvanced: IMsRdpClientAdvancedSettings);
    procedure ApplyGatewaySettings;
    procedure ControlWndProc(var aMessage: TMessage);
    procedure SetError(const aText: string);
    procedure ApplyDisplayUpdate;
    procedure ApplyScaleFactors(aDesktopScale, aDeviceScale: Cardinal);
    procedure BindEvents;
    function ComputeConnectSize: TSize;
    procedure CreateControl;
    function CurrentDpi: Integer;
    procedure DoDisplayChanged;
    procedure FallbackResize(aWidth, aHeight: Cardinal);
    function GetDisplayInfo: TRdpDisplayInfo;
    function HostClientSize: TSize;
    procedure HostDpiChanged(aSender: TObject);
    procedure HostResized(aSender: TObject);
    procedure Log(const aMessage: string);
    procedure MsgWndProc(var aMessage: TMessage);
    procedure ResizeTimerFired(aSender: TObject);
    procedure RestartResizeTimer(aIntervalMs: Integer);
    procedure SetState(aState: TRdpSessionState);
    procedure SetStatus(const aText: string);
    procedure ShowControl(aVisible: Boolean);
    procedure StopTimers;
    procedure VerifyTimerFired(aSender: TObject);
    // RDP-events
    procedure RdpAutoReconnected(aSender: TObject);
    procedure RdpAutoReconnecting2(aSender: TObject; aDisconnectReason: Integer; aNetworkAvailable: WordBool; aAttemptCount: Integer; aMaxAttemptCount: Integer);
    procedure RdpConnected(aSender: TObject);
    procedure RdpConnecting(aSender: TObject);
    procedure RdpDisconnected(aSender: TObject; aDiscReason: Integer);
    procedure RdpFatalError(aSender: TObject; aErrorCode: Integer);
    procedure RdpLoginComplete(aSender: TObject);
    procedure RdpLogonError(aSender: TObject; aError: Integer);
    procedure RdpRemoteDesktopSizeChange(aSender: TObject; aWidth: Integer; aHeight: Integer);
    procedure RdpWarning(aSender: TObject; aWarningCode: Integer);
  public
    constructor Create(aParent: TWinControl);
    destructor Destroy; override;
    procedure Connect;
    /// <summary>Voorbereiden vóór Connect (bijv. Tailscale-netwerk starten): toont aText en de status "verbinden".
    /// Daarna Connect (na SetEndpoint), of PrepareFailed.</summary>
    procedure BeginPrepare(const aText: string);
    procedure PrepareFailed(const aError: string);
    /// <summary>Adres en poort waarmee de control verbindt (de rest van de instellingen blijft).</summary>
    procedure SetEndpoint(const aServer: string; aPort: Integer);
    procedure Disconnect;
    procedure NotifyDpiChanged;
    class function DesktopScaleFromDpi(aDpi: Integer): Cardinal; static;
    /// <summary>Ingestelde schaal, of bij "automatisch" de schaal van de monitor.</summary>
    function EffectiveDesktopScale: Cardinal;
    /// <summary>Schaal wijzigen tijdens de sessie (0 = automatisch). Dynamisch: direct toegepast; anders bij de volgende verbinding.</summary>
    procedure SetDesktopScale(aPercent: Cardinal);
    class function DeviceScaleFromDesktopScale(aDesktopScale: Cardinal): Cardinal; static;
    class function NormalizeDesktopSize(aWidth, aHeight: Integer): TSize; static;
    property ControlClassName: string read FControlClassName;
    /// <summary>Vrij te gebruiken koppeling voor de eigenaar (bijv. het TRdcServer-object).</summary>
    property Data: TObject read FData write FData;
    property DisplayInfo: TRdpDisplayInfo read GetDisplayInfo;
    property Host: TRdpHost read FHost;
    /// <summary>Niet leeg als de laatste verbinding met een fout eindigde; wordt bij Connect gewist.</summary>
    property LastError: string read FLastError;
    /// <summary>True tussen het verbreken en het opnieuw verbinden van een fallback-reconnect (nieuwe afmeting).</summary>
    property ReconnectPending: Boolean read FReconnectPending;
    /// <summary>Reden (discReason) van de laatste verbreking; 0 = nog niet verbroken.</summary>
    property LastDisconnectReason: Integer read FLastDisconnectReason;
    /// <summary>Omschrijving van de laatste verbreking (GetErrorDescription), of leeg.</summary>
    property LastDisconnectText: string read FLastDisconnectText;
    /// <summary>Het wachtwoord in Settings wordt direct na doorgeven aan de control gewist en nooit bewaard.</summary>
    property Settings: TRdpConnectionSettings read FSettings write FSettings;
    property State: TRdpSessionState read FState;
    property OnDisplayChanged: TNotifyEvent read FOnDisplayChanged write FOnDisplayChanged;
    property OnLog: TRdpLogEvent read FOnLog write FOnLog;
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
  end;

const
  cRdpSessionStateNames: array[TRdpSessionState] of string = ('Niet verbonden', 'Verbinden', 'Verbonden', 'Ingelogd', 'Verbreken');
  // rdsUnknown: pas na de eerste formaatwijziging na het aanmelden is te zien of de server meegaat.
  cRdpDynamicSupportNames: array[TRdpDynamicSupport] of string = ('nog niet getest (volgt bij de eerste formaatwijziging)', 'werkt', 'niet ondersteund (opnieuw verbinden bij formaatwijziging)');
  cRdpSizeModeNames: array[TRdpSizeMode] of string = ('dynamisch', 'venstergrootte bij verbinden', 'vaste grootte', 'volledig scherm');

/// <summary>Session state as UI text in the active language (the const arrays above stay Dutch for the log).</summary>
function RdpSessionStateText(aState: TRdpSessionState): string;
/// <summary>Dynamic-resolution support as UI text in the active language.</summary>
function RdpDynamicSupportText(aSupport: TRdpDynamicSupport): string;
/// <summary>Display mode as UI text in the active language.</summary>
function RdpSizeModeText(aMode: TRdpSizeMode): string;

implementation

uses
  RdcmX.Credentials,
  RdcmX.Lang;

const
  cMinDesktopSize = 200;
  cMaxDesktopSize = 8192;
  cMaxUpdateAttempts = 8;
  cUpdateRetryMs = 1000;
  cMaxUpdateRetryMs = 5000;
  cVerifyTimeoutMs = 5000;
  cMaxVerifyMisses = 2;
  cDefaultDebounceMs = 400;

  WM_RDPX_DEFERRED = WM_USER + 1;
  cDeferredConnect = 1;

  // discReason-waarden die een normale, verwachte verbreking betekenen.
  cDiscLocalByUser = 1;
  cDiscRemoteByUser = 2;
  cDiscRemoteByServer = 3;

function RdpSessionStateText(aState: TRdpSessionState): string;
begin
  case aState of
    rssConnecting: Result := _('Bezig met verbinden');
    rssConnected: Result := _('Verbonden');
    rssLoggedIn: Result := _('Ingelogd');
    rssDisconnecting: Result := _('Bezig met verbreken');
  else
    Result := _('Niet verbonden');
  end;
end;

function RdpDynamicSupportText(aSupport: TRdpDynamicSupport): string;
begin
  case aSupport of
    rdsConfirmed: Result := _('werkt');
    rdsUnsupported: Result := _('niet ondersteund (opnieuw verbinden bij formaatwijziging)');
  else
    Result := _('nog niet getest (volgt bij de eerste formaatwijziging)');
  end;
end;

function RdpSizeModeText(aMode: TRdpSizeMode): string;
begin
  case aMode of
    rsmClientArea: Result := _('venstergrootte bij verbinden');
    rsmFixed: Result := _('vaste grootte');
    rsmFullScreen: Result := _('volledig scherm');
  else
    Result := _('dynamisch');
  end;
end;

{ TRdpConnectionSettings }

class function TRdpConnectionSettings.Default: TRdpConnectionSettings;
begin
  Result := System.Default(TRdpConnectionSettings);
  Result.Port := 3389;
  Result.AuthenticationLevel := 2; // 0 = verbinden zonder waarschuwing, 1 = niet verbinden bij falen, 2 = waarschuwen
  Result.ColorDepth := 32;
  Result.SizeMode := rsmDynamic;
  Result.FixedWidth := 1920;
  Result.FixedHeight := 1080;
  Result.SmartSizing := False;
  Result.ResizeDebounceMs := cDefaultDebounceMs;
  Result.ReconnectOnResizeFallback := True;
  Result.PhysicalSizeInMillimeters := False;
  Result.RedirectClipboard := True;
  Result.RedirectDrives := False;
  Result.RedirectPrinters := False;
  Result.RedirectPorts := False;
  Result.RedirectSmartCards := False;
  Result.RedirectDevices := False;
  Result.AudioRedirectionMode := 0;
  Result.AudioQualityMode := 0;
  Result.AudioCaptureRedirection := False;
  Result.KeyboardHookMode := 2;
end;

{ TRdpSession }

constructor TRdpSession.Create(aParent: TWinControl);
begin
  inherited Create;
  FSettings := TRdpConnectionSettings.Default;
  FMsgWnd := System.Classes.AllocateHWnd(MsgWndProc);

  FResizeTimer := TTimer.Create(nil);
  FResizeTimer.Enabled := False;
  FResizeTimer.OnTimer := ResizeTimerFired;

  FVerifyTimer := TTimer.Create(nil);
  FVerifyTimer.Enabled := False;
  FVerifyTimer.Interval := cVerifyTimeoutMs;
  FVerifyTimer.OnTimer := VerifyTimerFired;

  FHost := TRdpHost.Create(nil);
  FHost.Parent := aParent;
  // Geen alClient: de eigenaar (RdcmX.UI.SessionPanes) zet de positie, zodat een host in elk vak kan staan
  // zonder dat de VCL-Parent ooit verandert. Tot die tijd het hele sessiegebied.
  FHost.Align := alNone;
  FHost.BoundsRect := aParent.ClientRect;
  FHost.OnResized := HostResized;
  FHost.OnDpiChanged := HostDpiChanged;
  FHost.StatusText := _('Niet verbonden');

  CreateControl;
end;

destructor TRdpSession.Destroy;
begin
  FDestroying := True;
  StopTimers;
  if (FClient <> nil) and (FState <> rssDisconnected) then
  begin
    try
      FClient.Disconnect;
    except
      // bij afsluiten negeren
    end;
  end;
  FClient := nil;
  FreeAndNil(FControl);
  FreeAndNil(FHost);
  FreeAndNil(FResizeTimer);
  FreeAndNil(FVerifyTimer);
  if FMsgWnd <> 0 then
    System.Classes.DeallocateHWnd(FMsgWnd);
  inherited Destroy;
end;

procedure TRdpSession.CreateControl;
type
  TOleControlClass = class of TOleControl;
  TRdpControlCandidate = record
    ControlClass: TOleControlClass;
    ClassId: TGUID;
  end;
const
  cCandidates: array[0..3] of TRdpControlCandidate = (
    (ControlClass: TMsRdpClient12NotSafeForScripting; ClassId: '{3F859AA3-C2D4-4FAA-B0E4-FD0C9C4E5E3A}'),
    (ControlClass: TMsRdpClient11NotSafeForScripting; ClassId: '{1DF7C823-B2D4-4B54-975A-F2AC5D7CF8B8}'),
    (ControlClass: TMsRdpClient10NotSafeForScripting; ClassId: '{A0C63C30-F08D-4AB4-907C-34905D770C7D}'),
    (ControlClass: TMsRdpClient9NotSafeForScripting; ClassId: '{8B918B82-7985-4C24-89DF-C33AD2BBFBCD}'));
var
  lCandidate: TRdpControlCandidate;
  lHr: HResult;
  lProbe: IUnknown;
begin
  // De type library kan nieuwere classes noemen dan mstscax.dll daadwerkelijk kan leveren
  // (CLASS_E_CLASSNOTAVAILABLE). Eerst met CoCreateInstance proberen, dat geeft alleen een HRESULT;
  // zo ontstaat er geen (first chance) exception in de TOleControl-constructor.
  FControl := nil;
  for lCandidate in cCandidates do
  begin
    lProbe := nil;
    lHr := CoCreateInstance(lCandidate.ClassId, nil, CLSCTX_INPROC_SERVER, IUnknown, lProbe);
    lProbe := nil;
    if Failed(lHr) then
    begin
      Log(Format('%s niet beschikbaar (0x%.8x)', [lCandidate.ControlClass.ClassName, lHr]));
      Continue;
    end;
    try
      FControl := lCandidate.ControlClass.Create(FHost);
      FControlClassName := lCandidate.ControlClass.ClassName;
      Break;
    except
      on E: Exception do
        Log(Format('%s niet beschikbaar: %s', [lCandidate.ControlClass.ClassName, E.Message]));
    end;
  end;
  if FControl = nil then
    raise Exception.Create(_('Geen bruikbare Remote Desktop ActiveX-control (mstscax.dll) gevonden.'));

  if not Supports(FControl.DefaultDispatch, IMsRdpClient, FClient) then
    raise Exception.Create(_('De Remote Desktop ActiveX-control ondersteunt IMsRdpClient niet.'));

  FControl.Visible := False;
  FControl.Parent := FHost;
  FControl.Align := alClient;
  FOriginalControlWndProc := FControl.WindowProc;
  FControl.WindowProc := ControlWndProc;
  BindEvents;
  Log('RDP-control: ' + FControlClassName);
end;

procedure TRdpSession.ControlWndProc(var aMessage: TMessage);
var
  lActiveObject: IOleInPlaceActiveObject;
  lMsg: TMsg;
begin
  // TApplication.IsKeyMsg stuurt elke toetsaanslag in de RDP-window eerst als CN_KEYDOWN/CN_CHAR/... naar
  // deze VCL-control. De standaard TOleControl.WndProc laat daarna de VCL sneltoetsen (menu's, acties),
  // dialoognavigatie (Tab, pijltjes, Enter -> Default-knop) en Alt (menubalk) afhandelen. Die toetsen zijn
  // dan weg voor de remote sessie. Daarom: alleen de control zelf (TranslateAccelerator) laten kijken, en
  // anders 0 teruggeven zodat het bericht gewoon naar de RDP-window gaat.
  if (aMessage.Msg >= CN_BASE + WM_KEYFIRST) and (aMessage.Msg <= CN_BASE + WM_KEYLAST) then
  begin
    aMessage.Result := 0;
    if Supports(FControl.DefaultDispatch, IOleInPlaceActiveObject, lActiveObject) then
    begin
      lMsg.hwnd := FControl.Handle;
      lMsg.message := aMessage.Msg - CN_BASE;
      lMsg.wParam := aMessage.WParam;
      lMsg.lParam := aMessage.LParam;
      lMsg.time := Cardinal(GetMessageTime);
      lMsg.pt := Point(0, 0);
      if lActiveObject.TranslateAccelerator(lMsg) = S_OK then
        aMessage.Result := 1;
    end;
    Exit;
  end;
  FOriginalControlWndProc(aMessage);
end;

procedure TRdpSession.BindEvents;
begin
  // De TLB-wrapper heeft per class eigen (signatuur-identieke) event-types; daarom per class toewijzen.
  if FControl is TMsRdpClient12NotSafeForScripting then
  begin
    TMsRdpClient12NotSafeForScripting(FControl).OnConnecting := RdpConnecting;
    TMsRdpClient12NotSafeForScripting(FControl).OnConnected := RdpConnected;
    TMsRdpClient12NotSafeForScripting(FControl).OnLoginComplete := RdpLoginComplete;
    TMsRdpClient12NotSafeForScripting(FControl).OnDisconnected := RdpDisconnected;
    TMsRdpClient12NotSafeForScripting(FControl).OnLogonError := RdpLogonError;
    TMsRdpClient12NotSafeForScripting(FControl).OnWarning := RdpWarning;
    TMsRdpClient12NotSafeForScripting(FControl).OnFatalError := RdpFatalError;
    TMsRdpClient12NotSafeForScripting(FControl).OnRemoteDesktopSizeChange := RdpRemoteDesktopSizeChange;
    TMsRdpClient12NotSafeForScripting(FControl).OnAutoReconnecting2 := RdpAutoReconnecting2;
    TMsRdpClient12NotSafeForScripting(FControl).OnAutoReconnected := RdpAutoReconnected;
  end
  else if FControl is TMsRdpClient11NotSafeForScripting then
  begin
    TMsRdpClient11NotSafeForScripting(FControl).OnConnecting := RdpConnecting;
    TMsRdpClient11NotSafeForScripting(FControl).OnConnected := RdpConnected;
    TMsRdpClient11NotSafeForScripting(FControl).OnLoginComplete := RdpLoginComplete;
    TMsRdpClient11NotSafeForScripting(FControl).OnDisconnected := RdpDisconnected;
    TMsRdpClient11NotSafeForScripting(FControl).OnLogonError := RdpLogonError;
    TMsRdpClient11NotSafeForScripting(FControl).OnWarning := RdpWarning;
    TMsRdpClient11NotSafeForScripting(FControl).OnFatalError := RdpFatalError;
    TMsRdpClient11NotSafeForScripting(FControl).OnRemoteDesktopSizeChange := RdpRemoteDesktopSizeChange;
    TMsRdpClient11NotSafeForScripting(FControl).OnAutoReconnecting2 := RdpAutoReconnecting2;
    TMsRdpClient11NotSafeForScripting(FControl).OnAutoReconnected := RdpAutoReconnected;
  end
  else if FControl is TMsRdpClient10NotSafeForScripting then
  begin
    TMsRdpClient10NotSafeForScripting(FControl).OnConnecting := RdpConnecting;
    TMsRdpClient10NotSafeForScripting(FControl).OnConnected := RdpConnected;
    TMsRdpClient10NotSafeForScripting(FControl).OnLoginComplete := RdpLoginComplete;
    TMsRdpClient10NotSafeForScripting(FControl).OnDisconnected := RdpDisconnected;
    TMsRdpClient10NotSafeForScripting(FControl).OnLogonError := RdpLogonError;
    TMsRdpClient10NotSafeForScripting(FControl).OnWarning := RdpWarning;
    TMsRdpClient10NotSafeForScripting(FControl).OnFatalError := RdpFatalError;
    TMsRdpClient10NotSafeForScripting(FControl).OnRemoteDesktopSizeChange := RdpRemoteDesktopSizeChange;
    TMsRdpClient10NotSafeForScripting(FControl).OnAutoReconnecting2 := RdpAutoReconnecting2;
    TMsRdpClient10NotSafeForScripting(FControl).OnAutoReconnected := RdpAutoReconnected;
  end
  else if FControl is TMsRdpClient9NotSafeForScripting then
  begin
    TMsRdpClient9NotSafeForScripting(FControl).OnConnecting := RdpConnecting;
    TMsRdpClient9NotSafeForScripting(FControl).OnConnected := RdpConnected;
    TMsRdpClient9NotSafeForScripting(FControl).OnLoginComplete := RdpLoginComplete;
    TMsRdpClient9NotSafeForScripting(FControl).OnDisconnected := RdpDisconnected;
    TMsRdpClient9NotSafeForScripting(FControl).OnLogonError := RdpLogonError;
    TMsRdpClient9NotSafeForScripting(FControl).OnWarning := RdpWarning;
    TMsRdpClient9NotSafeForScripting(FControl).OnFatalError := RdpFatalError;
    TMsRdpClient9NotSafeForScripting(FControl).OnRemoteDesktopSizeChange := RdpRemoteDesktopSizeChange;
    TMsRdpClient9NotSafeForScripting(FControl).OnAutoReconnecting2 := RdpAutoReconnecting2;
    TMsRdpClient9NotSafeForScripting(FControl).OnAutoReconnected := RdpAutoReconnected;
  end;
end;

{ Schaal en afmetingen }

class function TRdpSession.DesktopScaleFromDpi(aDpi: Integer): Cardinal;
begin
  if aDpi <= 0 then
    aDpi := 96;
  Result := EnsureRange(MulDiv(aDpi, 100, 96), 100, 500);
end;

function TRdpSession.EffectiveDesktopScale: Cardinal;
begin
  if FSettings.DesktopScale > 0 then
    Result := EnsureRange(FSettings.DesktopScale, 100, 500)
  else
    Result := DesktopScaleFromDpi(CurrentDpi);
end;

procedure TRdpSession.SetDesktopScale(aPercent: Cardinal);
begin
  FSettings.DesktopScale := aPercent;
  if aPercent = 0 then
    Log('Schaal: automatisch')
  else
    Log(Format('Schaal: %d%%', [aPercent]));
  DoDisplayChanged;
  // ApplyDisplayUpdate vergelijkt met de laatst verstuurde schaal en stuurt alleen bij een verschil.
  if (FSettings.SizeMode = rsmDynamic) and (FState = rssLoggedIn) then
    RestartResizeTimer(1);
end;

class function TRdpSession.DeviceScaleFromDesktopScale(aDesktopScale: Cardinal): Cardinal;
begin
  if aDesktopScale < 140 then
    Result := 100
  else if aDesktopScale < 180 then
    Result := 140
  else
    Result := 180;
end;

class function TRdpSession.NormalizeDesktopSize(aWidth, aHeight: Integer): TSize;
begin
  Result.cx := EnsureRange(aWidth, cMinDesktopSize, cMaxDesktopSize);
  Result.cx := Result.cx and not 1; // breedte moet even zijn
  Result.cy := EnsureRange(aHeight, cMinDesktopSize, cMaxDesktopSize);
end;

function TRdpSession.CurrentDpi: Integer;
begin
  Result := 0;
  if FHost.HandleAllocated then
    Result := Integer(GetDpiForWindow(FHost.Handle));
  if Result <= 0 then
    Result := FHost.CurrentPPI;
  if Result <= 0 then
    Result := 96;
end;

function TRdpSession.HostClientSize: TSize;
begin
  // De host krijgt zijn positie (vak) al vóór het verbinden, ook als hij nog verborgen is.
  // Vangnet voor een host zonder bruikbare afmeting: het client-gebied van de parent.
  if ((FHost.ClientWidth < 64) or (FHost.ClientHeight < 64)) and (FHost.Parent <> nil) then
    Result := NormalizeDesktopSize(FHost.Parent.ClientWidth, FHost.Parent.ClientHeight)
  else
    Result := NormalizeDesktopSize(FHost.ClientWidth, FHost.ClientHeight);
end;

function TRdpSession.ComputeConnectSize: TSize;
var
  lMonitorRect: TRect;
  lMonitorInfo: TMonitorInfo;
begin
  case FSettings.SizeMode of
    rsmFixed:
      Result := NormalizeDesktopSize(FSettings.FixedWidth, FSettings.FixedHeight);
    rsmFullScreen:
      begin
        lMonitorInfo.cbSize := SizeOf(lMonitorInfo);
        if FHost.HandleAllocated and GetMonitorInfo(MonitorFromWindow(FHost.Handle, MONITOR_DEFAULTTONEAREST), @lMonitorInfo) then
          lMonitorRect := lMonitorInfo.rcMonitor
        else
          lMonitorRect := Rect(0, 0, 1920, 1080);
        Result := NormalizeDesktopSize(lMonitorRect.Width, lMonitorRect.Height);
      end;
  else
    Result := HostClientSize;
  end;
end;

function TRdpSession.GetDisplayInfo: TRdpDisplayInfo;
begin
  Result.HostWidth := FHost.ClientWidth;
  Result.HostHeight := FHost.ClientHeight;
  Result.SentWidth := FSentWidth;
  Result.SentHeight := FSentHeight;
  Result.SentDesktopScale := FSentDesktopScale;
  Result.SentDeviceScale := FSentDeviceScale;
  Result.RemoteWidth := FRemoteWidth;
  Result.RemoteHeight := FRemoteHeight;
  Result.Dpi := CurrentDpi;
  Result.DynamicSupport := FDynamicSupport;
  Result.SizeMode := FSettings.SizeMode;
end;

{ Verbinden }

procedure TRdpSession.ApplyScaleFactors(aDesktopScale, aDeviceScale: Cardinal);
var
  lExt: IMsRdpExtendedSettings;
  lHr: HResult;
begin
  if not Supports(FControl.DefaultDispatch, IMsRdpExtendedSettings, lExt) then
  begin
    Log('IMsRdpExtendedSettings niet beschikbaar; schaalfactor niet ingesteld.');
    Exit;
  end;
  lHr := lExt.Set_Property_('DesktopScaleFactor', OleVariant(aDesktopScale));
  if Failed(lHr) then
    Log(Format('DesktopScaleFactor instellen mislukt (0x%.8x)', [lHr]));
  lHr := lExt.Set_Property_('DeviceScaleFactor', OleVariant(aDeviceScale));
  if Failed(lHr) then
    Log(Format('DeviceScaleFactor instellen mislukt (0x%.8x)', [lHr]));
end;

procedure TRdpSession.ApplyGatewaySettings;
const
  // TSC_PROXY_MODE_*: 0 = geen gateway, 1 = altijd, 2 = gateway behalve voor lokale adressen.
  cProxyNone = 0;
  cProxyDirect = 1;
  cProxyDetect = 2;
  cProxyDefault = 3;
  cProfileUsageDefault = 0;
  cProfileUsageExplicit = 1;
var
  lClient5: IMsRdpClient5;
  lClient6: IMsRdpClient6;
  lTransport: IMsRdpClientTransportSettings;
  lTransport2: IMsRdpClientTransportSettings2;
begin
  if not Supports(FClient, IMsRdpClient5, lClient5) then
  begin
    WipeString(FSettings.GatewayPassword);
    if FSettings.GatewayEnabled then
      raise Exception.Create(_('deze versie van de Remote Desktop-client kan geen gateway instellen (IMsRdpClient5 ontbreekt).'));
    Exit;
  end;
  lTransport := lClient5.TransportSettings;
  if not FSettings.GatewayEnabled then
  begin
    lTransport.GatewayUsageMethod := cProxyNone;
    Exit;
  end;
  // Gateway gevraagd maar niet ondersteund: niet stilletjes direct verbinden.
  if lTransport.GatewayIsSupported = 0 then
    raise Exception.Create(_('deze versie van de Remote Desktop-client (mstscax.dll) ondersteunt geen Extern bureaublad-gateway.'));
  lTransport.GatewayHostname := FSettings.GatewayHostName;
  if FSettings.GatewayAutoDetect then
  begin
    // ONZEKER: automatisch detecteren = profielgebruik "standaard" met TSC_PROXY_MODE_DEFAULT.
    lTransport.GatewayProfileUsageMethod := cProfileUsageDefault;
    lTransport.GatewayUsageMethod := cProxyDefault;
  end
  else
  begin
    lTransport.GatewayProfileUsageMethod := cProfileUsageExplicit;
    if FSettings.GatewayBypassLocal then
      lTransport.GatewayUsageMethod := cProxyDetect
    else
      lTransport.GatewayUsageMethod := cProxyDirect;
  end;
  lTransport.GatewayCredsSource := FSettings.GatewayCredsSource;
  if Supports(FClient, IMsRdpClient6, lClient6) then
  begin
    lTransport2 := lClient6.TransportSettings2;
    lTransport2.GatewayCredSharing := Ord(FSettings.GatewayCredSharing);
    if not FSettings.GatewayCredSharing then
    begin
      lTransport2.GatewayUsername := FSettings.GatewayUserName;
      lTransport2.GatewayDomain := FSettings.GatewayDomain;
      if FSettings.GatewayPassword <> '' then
        lTransport2.GatewayPassword := FSettings.GatewayPassword;
    end;
  end;
  // Het gateway-wachtwoord staat nu in de control: hier niet langer bewaren.
  WipeString(FSettings.GatewayPassword);
  Log(Format('Gateway: %s (automatisch %s, lokaal overslaan %s, gedeelde aanmeldgegevens %s, bron %d)', [FSettings.GatewayHostName, BoolToStr(FSettings.GatewayAutoDetect, True), BoolToStr(FSettings.GatewayBypassLocal, True), BoolToStr(FSettings.GatewayCredSharing, True), FSettings.GatewayCredsSource]));
end;

procedure TRdpSession.ApplyConnectionOptions(aAdvanced: IMsRdpClientAdvancedSettings);
var
  lAdv6: IMsRdpClientAdvancedSettings6;
  lSecured: IMsTscSecuredSettings;
begin
  // Vanaf RDP 6.1 heet "console" de beheersessie (/admin); ConnectToServerConsole is dan verouderd.
  if Supports(aAdvanced, IMsRdpClientAdvancedSettings6, lAdv6) then
    lAdv6.ConnectToAdministerServer := FSettings.ConnectToConsole
  else
    aAdvanced.ConnectToServerConsole := FSettings.ConnectToConsole;
  if FSettings.LoadBalanceInfo <> '' then
    aAdvanced.LoadBalanceInfo := FSettings.LoadBalanceInfo;
  if (FSettings.StartProgram <> '') and Supports(FClient.SecuredSettings2, IMsTscSecuredSettings, lSecured) then
  begin
    lSecured.StartProgram := FSettings.StartProgram;
    lSecured.WorkDir := FSettings.WorkingDir;
  end;
end;

procedure TRdpSession.ApplyConnectSettings(aWidth, aHeight: Integer);
var
  lAdv: IMsRdpClientAdvancedSettings;
  lAdv2: IMsRdpClientAdvancedSettings2;
  lAdv4: IMsRdpClientAdvancedSettings4;
  lAdv5: IMsRdpClientAdvancedSettings5;
  lAdv6: IMsRdpClientAdvancedSettings6;
  lAdv7: IMsRdpClientAdvancedSettings7;
  lSecured: IMsRdpClientSecuredSettings;
  lDesktopScale: Cardinal;
  lDeviceScale: Cardinal;
  lNonScriptable: IMsTscNonScriptable;
  lNonScriptable3: IMsRdpClientNonScriptable3;
  lNonScriptable4: IMsRdpClientNonScriptable4;
begin
  FClient.Server := FSettings.Server;
  FClient.UserName := FSettings.UserName;
  FClient.Domain := FSettings.Domain;
  FClient.DesktopWidth := aWidth;
  FClient.DesktopHeight := aHeight;
  FClient.ColorDepth := FSettings.ColorDepth;

  lAdv := FClient.AdvancedSettings2;
  lAdv.RDPPort := FSettings.Port;
  lAdv.SmartSizing := (FSettings.SizeMode <> rsmDynamic) and FSettings.SmartSizing;

  if Supports(lAdv, IMsRdpClientAdvancedSettings6, lAdv6) then
    lAdv6.EnableCredSspSupport := True
  else if Supports(FControl.DefaultDispatch, IMsRdpClientNonScriptable3, lNonScriptable3) then
    lNonScriptable3.Set_EnableCredSspSupport(True)
  else
    Log('CredSSP kon niet worden ingeschakeld (interface ontbreekt).');

  if Supports(lAdv, IMsRdpClientAdvancedSettings4, lAdv4) then
    lAdv4.AuthenticationLevel := FSettings.AuthenticationLevel;

  if Supports(lAdv, IMsRdpClientAdvancedSettings2, lAdv2) then
    lAdv2.EnableAutoReconnect := True;

  ApplyConnectionOptions(lAdv);
  ApplyGatewaySettings;

  // Lokale bronnen. Klembord (ook bestanden kopiëren/plakken) gaat via het cliprdr-kanaal; daarvoor moet
  // de server klembordomleiding toestaan (groepsbeleid/RDS-instelling) en draait daar rdpclip.exe.
  lAdv.RedirectDrives := FSettings.RedirectDrives;
  lAdv.RedirectPrinters := FSettings.RedirectPrinters;
  lAdv.RedirectPorts := FSettings.RedirectPorts;
  lAdv.RedirectSmartCards := FSettings.RedirectSmartCards;
  if Supports(lAdv, IMsRdpClientAdvancedSettings5, lAdv5) then
  begin
    lAdv5.RedirectClipboard := FSettings.RedirectClipboard;
    lAdv5.RedirectDevices := FSettings.RedirectDevices;
    lAdv5.AudioRedirectionMode := Cardinal(FSettings.AudioRedirectionMode);
  end
  else
    Log('IMsRdpClientAdvancedSettings5 niet beschikbaar: klembord/audio-instellingen niet gezet.');
  if Supports(lAdv, IMsRdpClientAdvancedSettings7, lAdv7) then
  begin
    lAdv7.AudioQualityMode := Cardinal(FSettings.AudioQualityMode);
    lAdv7.AudioCaptureRedirectionMode := FSettings.AudioCaptureRedirection;
  end;
  if Supports(FClient.SecuredSettings2, IMsRdpClientSecuredSettings, lSecured) then
    lSecured.KeyboardHookMode := FSettings.KeyboardHookMode;
  Log(Format('Lokale bronnen: klembord %s, drives %s, printers %s, audio %d, toetsenbord-hook %d', [BoolToStr(FSettings.RedirectClipboard, True), BoolToStr(FSettings.RedirectDrives, True), BoolToStr(FSettings.RedirectPrinters, True), FSettings.AudioRedirectionMode, FSettings.KeyboardHookMode]));

  // Wachtwoorden worden nooit opgeslagen: alleen doorgeven aan de control en daarna direct wissen.
  if Supports(FControl.DefaultDispatch, IMsTscNonScriptable, lNonScriptable) then
  begin
    if FSettings.Password <> '' then
      lNonScriptable.Set_ClearTextPassword(FSettings.Password)
    else
      lNonScriptable.ResetPassword;
  end;
  WipeString(FSettings.Password);
  // Ook de control zelf mag niets onthouden (geen "Remember me" in een eventuele Windows-prompt).
  if Supports(FControl.DefaultDispatch, IMsRdpClientNonScriptable4, lNonScriptable4) then
    lNonScriptable4.Set_AllowCredentialSaving(False);

  lDesktopScale := EffectiveDesktopScale;
  lDeviceScale := DeviceScaleFromDesktopScale(lDesktopScale);
  ApplyScaleFactors(lDesktopScale, lDeviceScale);

  FSentWidth := Cardinal(aWidth);
  FSentHeight := Cardinal(aHeight);
  FSentDesktopScale := lDesktopScale;
  FSentDeviceScale := lDeviceScale;
  FRemoteWidth := aWidth;
  FRemoteHeight := aHeight;
end;

procedure TRdpSession.BeginPrepare(const aText: string);
begin
  if FState <> rssDisconnected then
    Exit;
  FLastError := '';
  FLastDisconnectReason := 0;
  FPreparing := True;
  SetState(rssConnecting);
  SetStatus(aText);
end;

procedure TRdpSession.PrepareFailed(const aError: string);
begin
  if not FPreparing then
    Exit;
  FPreparing := False;
  WipeString(FSettings.Password);
  WipeString(FSettings.GatewayPassword);
  SetError(aError);
  SetState(rssDisconnected);
  Log('Voorbereiden mislukt: ' + aError);
end;

procedure TRdpSession.SetEndpoint(const aServer: string; aPort: Integer);
begin
  FSettings.Server := aServer;
  FSettings.Port := aPort;
end;


procedure TRdpSession.Connect;
var
  lSize: TSize;
begin
  if FPreparing then
  begin
    // Einde van de voorbereiding: weer als "niet verbonden" beginnen (zonder event; de state wordt zo connecting).
    FPreparing := False;
    FState := rssDisconnected;
  end;
  if FState <> rssDisconnected then
    Exit;
  if Trim(FSettings.Server) = '' then
  begin
    SetError(_('Geen server opgegeven.'));
    Exit;
  end;

  FLastError := '';
  FLastDisconnectReason := 0;
  FUserDisconnect := False;
  FReconnectPending := False;
  FResizeReconnecting := False;
  FUnsupportedByError := False;
  FDynamicSupport := rdsUnknown;
  FUpdateFailures := 0;
  FVerifyMisses := 0;
  StopTimers;

  ShowControl(True);
  lSize := ComputeConnectSize;
  try
    // Ook als de host (nog) verborgen is moet de control in-place actief zijn.
    FControl.HandleNeeded;
    ApplyConnectSettings(lSize.cx, lSize.cy);
    SetState(rssConnecting);
    Log(Format('Verbinden met %s:%d als %dx%d, schaal %d/%d', [FSettings.Server, FSettings.Port, lSize.cx, lSize.cy, FSentDesktopScale, FSentDeviceScale]));
    FClient.Connect;
  except
    on E: Exception do
    begin
      FSettings.Password := '';
      WipeString(FSettings.GatewayPassword);
      ShowControl(False);
      SetError(Format(_('Verbinden mislukt: %s'), [E.Message]));
      SetState(rssDisconnected);
      Log('Connect-fout: ' + E.Message);
    end;
  end;
  DoDisplayChanged;
end;

procedure TRdpSession.Disconnect;
begin
  FReconnectPending := False;
  if FPreparing then
  begin
    // Nog aan het voorbereiden (tailnet starten): er is geen verbinding om te verbreken.
    FPreparing := False;
    FUserDisconnect := True;
    WipeString(FSettings.Password);
    WipeString(FSettings.GatewayPassword);
    SetStatus(_('Verbinding verbroken.'));
    SetState(rssDisconnected);
    Exit;
  end;
  if FState in [rssDisconnected, rssDisconnecting] then
    Exit;
  FUserDisconnect := True;
  StopTimers;
  SetState(rssDisconnecting);
  try
    if FClient.Connected <> 0 then
      FClient.Disconnect
    else
      RdpDisconnected(nil, cDiscLocalByUser);
  except
    on E: Exception do
    begin
      Log('Disconnect-fout: ' + E.Message);
      RdpDisconnected(nil, cDiscLocalByUser);
    end;
  end;
end;

{ Dynamische resolutie }

procedure TRdpSession.HostResized(aSender: TObject);
begin
  DoDisplayChanged;
  if FSettings.SizeMode <> rsmDynamic then
    Exit;
  // Pas na OnLoginComplete versturen; resizes tijdens het verbinden worden bij login opgepakt.
  if FState = rssLoggedIn then
    RestartResizeTimer(FSettings.ResizeDebounceMs);
end;

procedure TRdpSession.HostDpiChanged(aSender: TObject);
begin
  NotifyDpiChanged;
end;

procedure TRdpSession.NotifyDpiChanged;
begin
  Log(Format('DPI gewijzigd: %d', [CurrentDpi]));
  DoDisplayChanged;
  if (FSettings.SizeMode = rsmDynamic) and (FState = rssLoggedIn) then
    RestartResizeTimer(FSettings.ResizeDebounceMs);
end;

procedure TRdpSession.RestartResizeTimer(aIntervalMs: Integer);
begin
  FResizeTimer.Enabled := False;
  FResizeTimer.Interval := Cardinal(Max(aIntervalMs, 1));
  FResizeTimer.Enabled := True;
end;

procedure TRdpSession.ResizeTimerFired(aSender: TObject);
begin
  FResizeTimer.Enabled := False;
  if FDestroying or (FState <> rssLoggedIn) or (FSettings.SizeMode <> rsmDynamic) then
    Exit;
  ApplyDisplayUpdate;
end;

procedure TRdpSession.ApplyDisplayUpdate;
var
  lClient9: IMsRdpClient9;
  lDesktopScale: Cardinal;
  lDeviceScale: Cardinal;
  lDpi: Integer;
  lPhysicalHeight: Cardinal;
  lPhysicalWidth: Cardinal;
  lSize: TSize;
begin
  lSize := HostClientSize;
  lDpi := CurrentDpi;
  lDesktopScale := EffectiveDesktopScale;
  lDeviceScale := DeviceScaleFromDesktopScale(lDesktopScale);

  if (Cardinal(lSize.cx) = FSentWidth) and (Cardinal(lSize.cy) = FSentHeight) and (lDesktopScale = FSentDesktopScale) and (lDeviceScale = FSentDeviceScale) then
    Exit;

  if FDynamicSupport = rdsUnsupported then
  begin
    if not FUnsupportedByError then
    begin
      FallbackResize(lSize.cx, lSize.cy);
      Exit;
    end;
    // Eerder alleen mislukt (mogelijk te vroeg na het aanmelden): nog één keer dynamisch proberen; mislukt dat
    // weer, dan volgt hieronder de fallback.
    Log('Dynamische resolutie opnieuw proberen na eerdere fouten.');
    FDynamicSupport := rdsUnknown;
    FUnsupportedByError := False;
    FUpdateFailures := cMaxUpdateAttempts - 1;
  end;

  if not Supports(FControl.DefaultDispatch, IMsRdpClient9, lClient9) then
  begin
    Log('IMsRdpClient9 niet beschikbaar: dynamische resolutie niet mogelijk.');
    FDynamicSupport := rdsUnsupported;
    FallbackResize(lSize.cx, lSize.cy);
    Exit;
  end;

  if FSettings.PhysicalSizeInMillimeters then
  begin
    lPhysicalWidth := Cardinal(MulDiv(lSize.cx, 254, lDpi * 10));
    lPhysicalHeight := Cardinal(MulDiv(lSize.cy, 254, lDpi * 10));
  end
  else
  begin
    lPhysicalWidth := Cardinal(lSize.cx);
    lPhysicalHeight := Cardinal(lSize.cy);
  end;

  try
    lClient9.UpdateSessionDisplaySettings(Cardinal(lSize.cx), Cardinal(lSize.cy), lPhysicalWidth, lPhysicalHeight, 0, lDesktopScale, lDeviceScale);
    Log(Format('UpdateSessionDisplaySettings %dx%d (fysiek %dx%d), schaal %d/%d', [lSize.cx, lSize.cy, lPhysicalWidth, lPhysicalHeight, lDesktopScale, lDeviceScale]));
    FSentWidth := Cardinal(lSize.cx);
    FSentHeight := Cardinal(lSize.cy);
    FSentDesktopScale := lDesktopScale;
    FSentDeviceScale := lDeviceScale;
    FUpdateFailures := 0;
    // Bevestiging afwachten zolang nog niet vaststaat dat de server dit ondersteunt.
    if (FDynamicSupport = rdsUnknown) and ((lSize.cx <> FRemoteWidth) or (lSize.cy <> FRemoteHeight)) then
    begin
      FVerifyTimer.Enabled := False;
      FVerifyTimer.Enabled := True;
    end;
  except
    on E: Exception do
    begin
      Inc(FUpdateFailures);
      Log(Format('UpdateSessionDisplaySettings mislukt (poging %d/%d): %s', [FUpdateFailures, cMaxUpdateAttempts, E.Message]));
      if FUpdateFailures < cMaxUpdateAttempts then
        RestartResizeTimer(Min(cUpdateRetryMs * FUpdateFailures, cMaxUpdateRetryMs))
      else
      begin
        FDynamicSupport := rdsUnsupported;
        FUnsupportedByError := True;
        Log('Dynamische resolutie geldt als niet ondersteund voor deze sessie.');
        FallbackResize(lSize.cx, lSize.cy);
      end;
    end;
  end;
  DoDisplayChanged;
end;

procedure TRdpSession.VerifyTimerFired(aSender: TObject);
begin
  FVerifyTimer.Enabled := False;
  if FDestroying or (FState <> rssLoggedIn) or (FDynamicSupport <> rdsUnknown) then
    Exit;
  Inc(FVerifyMisses);
  Log(Format('Geen OnRemoteDesktopSizeChange ontvangen na UpdateSessionDisplaySettings (%d/%d).', [FVerifyMisses, cMaxVerifyMisses]));
  if FVerifyMisses < cMaxVerifyMisses then
  begin
    // Nog één keer proberen: laatst verstuurde waarden wissen zodat de update opnieuw gaat.
    FSentWidth := 0;
    FSentHeight := 0;
    RestartResizeTimer(cUpdateRetryMs);
  end
  else
  begin
    FDynamicSupport := rdsUnsupported;
    Log('Server reageert niet op dynamische resolutie; geldt als niet ondersteund.');
    FallbackResize(HostClientSize.cx, HostClientSize.cy);
  end;
  DoDisplayChanged;
end;

procedure TRdpSession.FallbackResize(aWidth, aHeight: Cardinal);
var
  lClient8: IMsRdpClient8;
  lStatus: ControlReconnectStatus;
begin
  // Niets opnieuw proberen tot de afmeting opnieuw wijzigt.
  FSentWidth := aWidth;
  FSentHeight := aHeight;
  FSentDesktopScale := EffectiveDesktopScale;
  FSentDeviceScale := DeviceScaleFromDesktopScale(FSentDesktopScale);
  if not FSettings.ReconnectOnResizeFallback then
  begin
    Log('Dynamische resolutie niet beschikbaar en reconnect-fallback staat uit.');
    Exit;
  end;
  // Afmeting gelijk aan die van de sessie (alleen de schaal wijkt af): niet opnieuw verbinden. Dat zou de sessie
  // voor niets riskeren (gezien op een domeincontroller: Reconnect direct na het aanmelden faalde met "interne fout").
  if (Integer(aWidth) = FRemoteWidth) and (Integer(aHeight) = FRemoteHeight) then
  begin
    Log(Format('Dynamische resolutie niet beschikbaar; afmeting %dx%d klopt al, dus geen reconnect.', [aWidth, aHeight]));
    Exit;
  end;
  if FResizeReconnectFailed then
  begin
    Log('Dynamische resolutie niet beschikbaar en reconnect met nieuwe afmeting mislukte eerder; afmeting blijft vast.');
    Exit;
  end;

  if Supports(FControl.DefaultDispatch, IMsRdpClient8, lClient8) then
  begin
    try
      lStatus := lClient8.Reconnect(aWidth, aHeight);
      if lStatus = controlReconnectStarted then
      begin
        Log(Format('Reconnect gestart met %dx%d', [aWidth, aHeight]));
        FResizeReconnecting := True;
        Exit;
      end;
      Log('Reconnect geblokkeerd door de control; val terug op disconnect + connect.');
    except
      on E: Exception do
        Log('Reconnect mislukt: ' + E.Message + '; val terug op disconnect + connect.');
    end;
  end;

  FReconnectPending := True;
  FUserDisconnect := True;
  SetState(rssDisconnecting);
  try
    FClient.Disconnect;
  except
    on E: Exception do
    begin
      Log('Disconnect voor reconnect mislukt: ' + E.Message);
      FReconnectPending := False;
    end;
  end;
end;

{ RDP-events }

procedure TRdpSession.RdpConnecting(aSender: TObject);
begin
  if FDestroying then
    Exit;
  Log('OnConnecting');
  SetState(rssConnecting);
end;

procedure TRdpSession.RdpConnected(aSender: TObject);
begin
  if FDestroying then
    Exit;
  Log('OnConnected');
  SetState(rssConnected);
end;

procedure TRdpSession.RdpLoginComplete(aSender: TObject);
begin
  if FDestroying then
    Exit;
  Log('OnLoginComplete');
  FResizeReconnecting := False;
  SetState(rssLoggedIn);
  SetStatus('');
  // Een ingestelde schaal na het aanmelden nog eens expliciet sturen: niet elke server neemt de schaal uit de
  // verbindingsinstellingen over (ONZEKER per serverversie). Door de laatst verstuurde schaal te wissen stuurt
  // ApplyDisplayUpdate hem gegarandeerd.
  if FSettings.DesktopScale > 0 then
    FSentDesktopScale := 0;
  // Eventuele resizes tijdens het verbinden nu alsnog verwerken.
  if FSettings.SizeMode = rsmDynamic then
    RestartResizeTimer(FSettings.ResizeDebounceMs);
end;

procedure TRdpSession.RdpDisconnected(aSender: TObject; aDiscReason: Integer);
var
  lClient5: IMsRdpClient5;
  lDescription: string;
  lExtended: Integer;
begin
  if FDestroying then
    Exit;
  StopTimers;

  lExtended := 0;
  try
    lExtended := Integer(FClient.ExtendedDisconnectReason);
  except
    // niet beschikbaar
  end;
  lDescription := '';
  if Supports(FControl.DefaultDispatch, IMsRdpClient5, lClient5) then
  begin
    try
      lDescription := lClient5.GetErrorDescription(Cardinal(aDiscReason), Cardinal(lExtended));
    except
      lDescription := '';
    end;
  end;
  Log(Format('OnDisconnected: reden %d, uitgebreid %d: %s', [aDiscReason, lExtended, lDescription]));
  FLastDisconnectReason := aDiscReason;
  FLastDisconnectText := lDescription;

  ShowControl(False);

  if FReconnectPending then
  begin
    SetState(rssDisconnected);
    SetStatus(_('Opnieuw verbinden met nieuwe afmeting...'));
    PostMessage(FMsgWnd, WM_RDPX_DEFERRED, cDeferredConnect, 0);
    Exit;
  end;

  // Reconnect met nieuwe afmeting mislukt: als fout melden (tab blijft staan) en voor deze sessie niet meer proberen.
  if FResizeReconnecting then
  begin
    FResizeReconnecting := False;
    FResizeReconnectFailed := True;
    if lDescription <> '' then
      SetError(Format(_('De server ondersteunt geen dynamische resolutie, en opnieuw verbinden met de nieuwe afmeting is mislukt (%s).'#13#10#13#10'Verbind opnieuw: de sessie houdt dan een vaste afmeting.'), [lDescription]))
    else
      SetError(_('De server ondersteunt geen dynamische resolutie, en opnieuw verbinden met de nieuwe afmeting is mislukt.'#13#10#13#10'Verbind opnieuw: de sessie houdt dan een vaste afmeting.'));
    SetState(rssDisconnected);
    Exit;
  end;

  // Status/fout zetten vóór de state-wissel, zodat OnStateChanged de juiste fouttoestand ziet.
  if (FUserDisconnect and (aDiscReason = cDiscLocalByUser)) or (aDiscReason in [cDiscRemoteByUser, cDiscRemoteByServer]) then
    SetStatus(_('Verbinding verbroken.') + IfThen(lDescription <> '', #13#10#13#10 + lDescription, ''))
  else if lDescription <> '' then
    SetError(Format(_('Verbinding verbroken: %s'#13#10#13#10'(code %d, uitgebreid %d)'), [lDescription, aDiscReason, lExtended]))
  else
    SetError(Format(_('Verbinding verbroken (code %d, uitgebreid %d).'), [aDiscReason, lExtended]));
  SetState(rssDisconnected);
end;

procedure TRdpSession.RdpLogonError(aSender: TObject; aError: Integer);
begin
  if not FDestroying then
    Log(Format('OnLogonError: %d', [aError]));
end;

procedure TRdpSession.RdpWarning(aSender: TObject; aWarningCode: Integer);
begin
  if not FDestroying then
    Log(Format('OnWarning: %d', [aWarningCode]));
end;

procedure TRdpSession.RdpFatalError(aSender: TObject; aErrorCode: Integer);
begin
  if FDestroying then
    Exit;
  Log(Format('OnFatalError: %d', [aErrorCode]));
  SetStatus(Format(_('Fatale fout in de RDP-control (code %d).'), [aErrorCode]));
end;

procedure TRdpSession.RdpRemoteDesktopSizeChange(aSender: TObject; aWidth: Integer; aHeight: Integer);
begin
  if FDestroying then
    Exit;
  Log(Format('OnRemoteDesktopSizeChange: %dx%d', [aWidth, aHeight]));
  FRemoteWidth := aWidth;
  FRemoteHeight := aHeight;
  if FVerifyTimer.Enabled then
  begin
    FVerifyTimer.Enabled := False;
    if FDynamicSupport = rdsUnknown then
    begin
      FDynamicSupport := rdsConfirmed;
      Log('Dynamische resolutie bevestigd door de server.');
    end;
  end;
  DoDisplayChanged;
end;

procedure TRdpSession.RdpAutoReconnecting2(aSender: TObject; aDisconnectReason: Integer; aNetworkAvailable: WordBool; aAttemptCount: Integer; aMaxAttemptCount: Integer);
begin
  if FDestroying then
    Exit;
  Log(Format('OnAutoReconnecting2: reden %d, poging %d/%d, netwerk %s', [aDisconnectReason, aAttemptCount, aMaxAttemptCount, BoolToStr(aNetworkAvailable, True)]));
  SetStatus(Format(_('Automatisch opnieuw verbinden (poging %d van %d)...'), [aAttemptCount, aMaxAttemptCount]));
end;

procedure TRdpSession.RdpAutoReconnected(aSender: TObject);
begin
  if FDestroying then
    Exit;
  Log('OnAutoReconnected');
  SetStatus('');
end;

{ Overig }

procedure TRdpSession.MsgWndProc(var aMessage: TMessage);
begin
  if aMessage.Msg = WM_RDPX_DEFERRED then
  begin
    if (aMessage.WParam = cDeferredConnect) and not FDestroying then
    begin
      FReconnectPending := False;
      Connect;
    end;
  end
  else
    aMessage.Result := DefWindowProc(FMsgWnd, aMessage.Msg, aMessage.WParam, aMessage.LParam);
end;

procedure TRdpSession.ShowControl(aVisible: Boolean);
begin
  FControl.Visible := aVisible;
  FHost.Invalidate;
end;

procedure TRdpSession.StopTimers;
begin
  if FResizeTimer <> nil then
    FResizeTimer.Enabled := False;
  if FVerifyTimer <> nil then
    FVerifyTimer.Enabled := False;
end;

procedure TRdpSession.SetState(aState: TRdpSessionState);
begin
  if FState = aState then
    Exit;
  FState := aState;
  case aState of
    rssConnecting:
      SetStatus(Format(_('Verbinden met %s...'), [IfThen(FSettings.DisplayName <> '', FSettings.DisplayName, FSettings.Server)]));
    rssDisconnecting:
      SetStatus(_('Verbinding verbreken...'));
  end;
  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self);
end;

procedure TRdpSession.SetStatus(const aText: string);
begin
  FHost.StatusText := aText;
end;

procedure TRdpSession.SetError(const aText: string);
begin
  FLastError := aText;
  SetStatus(aText);
end;

procedure TRdpSession.DoDisplayChanged;
begin
  if Assigned(FOnDisplayChanged) and not FDestroying then
    FOnDisplayChanged(Self);
end;

procedure TRdpSession.Log(const aMessage: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, aMessage);
end;

end.
