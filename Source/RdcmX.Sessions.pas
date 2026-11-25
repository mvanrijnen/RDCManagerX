unit RdcmX.Sessions;

{
  TRdcSessionManager: koppelt servers uit het model aan RDP-sessies.

  - Eén TRdpSession per server, aangemaakt bij de eerste Connect. Alle hosts staan permanent in dezelfde
    container (het sessiegebied). ShowServers toont per vak de actieve sessie op de opgegeven positie en verbergt
    de rest. Verbergen/tonen/verplaatsen wijzigt geen Parent en recreëert dus geen handles, zodat sessies op de
    achtergrond doorlopen.
  - OnPlaceHost: een nieuwe host krijgt zijn positie (het vak) vóór het verbinden, want de beginresolutie volgt
    de afmeting van de host.
  - Losmaken (eigen venster / volledig scherm): de host verhuist met Winapi.Windows.SetParent naar een ander
    venster; de VCL-Parent blijft pnlSession (een VCL-Parent-wissel zou de handle en dus de sessie vernietigen).
    ShowServers laat losgemaakte hosts met rust; PlaceDetached zet ze op hun plek in het andere venster.
    Terugzetten (Reattach) gebeurt vóór vrijgeven, zodat de host nooit met een ander venster mee verdwijnt.
  - Bij verbinden worden de effectieve instellingen uit het model omgezet naar TRdpConnectionSettings.
    Het wachtwoord wordt via OnCredentialRequest gevraagd en nooit bewaard.
  - Een sessie wordt nooit vrijgegeven vanuit haar eigen events (dat zou de ActiveX-control vrijgeven terwijl
    die nog in een callback zit); vrijgeven na verbreken gaat via een geposte message.

  Waarom een aparte unit (niet in de opdracht-indeling): zo blijft het model vrij van RDP-kennis en het
  hoofdvenster vrij van sessiebeheer.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.ExtCtrls,
  RdcmX.Credentials, RdcmX.Model, RdcmX.Rdp.Session, RdcmX.Tailscale;

type
  TRdcSessionEvent = procedure(aSender: TObject; aServer: TRdcServer) of object;
  TRdcCredentialRequest = function(aServer: TRdcServer; var aUserName, aDomain: string; out aPassword: string): Boolean of object;
  TRdcPlaceHostEvent = procedure(aServer: TRdcServer; aHost: TControl) of object;

  /// <summary>Tailscale-route van één sessie: het netwerk (refcount in TRdcTailnetManager) en de lokale forward.
  /// Blijft bestaan zolang de sessie bestaat (ook na verbreken: "Opnieuw verbinden" en automatisch opnieuw verbinden
  /// gebruiken dezelfde forward); wordt opgeruimd als de sessie wordt vrijgegeven (tab dicht).</summary>
  TRdcTunnel = class
  public
    TailnetId: string;
    TailnetName: string;
    LocalAddress: string;
    Target: string;
    /// <summary>0 zolang het netwerk nog start.</summary>
    Port: Integer;
    Guard: IRdcCallbackGuard;
    AuthUrlOpened: string;
  end;

  TRdcSessionManager = class
  private
    FContainer: TWinControl;
    FSessions: TDictionary<TRdcServer, TRdpSession>;
    FTunnels: TObjectDictionary<TRdpSession, TRdcTunnel>;
    FTunnelTimer: TTimer;
    FTailnets: TRdcTailnetManager;
    FSecrets: IRdcSecretAccess;
    FPendingFree: TList<TRdpSession>;
    FDetached: TList<TRdcServer>;
    FMsgWnd: HWND;
    FOnActivated: TRdcSessionEvent;
    FOnCredentialRequest: TRdcCredentialRequest;
    FOnPlaceHost: TRdcPlaceHostEvent;
    FOnDisplayChanged: TRdcSessionEvent;
    FOnStateChanged: TRdcSessionEvent;
    function BuildSettings(aServer: TRdcServer; out aSettings: TRdpConnectionSettings; out aError: string): Boolean;
    function ApplyGatewayRoute(aServer: TRdcServer; var aSettings: TRdpConnectionSettings; out aError: string): Boolean;
    procedure ConnectViaTailnet(aServer: TRdcServer; aSession: TRdpSession);
    procedure TunnelReady(aSession: TRdpSession; aSuccess: Boolean; const aError: string);
    procedure ReleaseTunnel(aSession: TRdpSession);
    procedure TunnelTimerFired(aSender: TObject);
    procedure FreePendingSessions;
    procedure HostActivated(aSender: TObject);
    procedure MsgWndProc(var aMessage: TMessage);
    procedure PendingSessionStateChanged(aSender: TObject);
    procedure SessionDisplayChanged(aSender: TObject);
    procedure SessionLog(aSender: TObject; const aMessage: string);
    procedure SessionStateChanged(aSender: TObject);
  public
    constructor Create(aContainer: TWinControl);
    destructor Destroy; override;
    /// <summary>Vraagt (via OnCredentialRequest) het wachtwoord en verbindt. False als de gebruiker annuleert.</summary>
    function Connect(aServer: TRdcServer): Boolean;
    procedure Disconnect(aServer: TRdcServer);
    procedure DisconnectAll;
    function Find(aServer: TRdcServer): TRdpSession;
    function HasError(aServer: TRdcServer): Boolean;
    procedure NotifyDpiChanged;
    /// <summary>Server wordt verwijderd: verbreken en de sessie (uitgesteld) vrijgeven.</summary>
    procedure Release(aServer: TRdcServer);
    /// <summary>Toont de hosts van aServers op de bijbehorende aRects (client-coördinaten van de container) en
    /// verbergt alle andere. nil-items worden overgeslagen.</summary>
    procedure ShowServers(const aServers: array of TRdcServer; const aRects: array of TRect);
    function ActiveCount: Integer;
    /// <summary>Servers met een sessie die niet verbroken is.</summary>
    function ActiveServers: TArray<TRdcServer>;
    function StateOf(aServer: TRdcServer): TRdpSessionState;
    /// <summary>Host van aServer naar een ander venster verplaatsen (op Win32-niveau; VCL-Parent blijft gelijk).</summary>
    procedure Detach(aServer: TRdcServer; aParentWnd: HWND);
    /// <summary>Host terug in het sessiegebied (wordt daarna door ShowServers weer geplaatst).</summary>
    procedure Reattach(aServer: TRdcServer);
    function IsDetached(aServer: TRdcServer): Boolean;
    /// <summary>Positie van een losgemaakte host, in client-coördinaten van zijn venster.</summary>
    procedure PlaceDetached(aServer: TRdcServer; const aRect: TRect);
    /// <summary>Venster van het RDP-control binnen de host (voor de toetsenbordfocus), of 0.</summary>
    function ControlHandle(aServer: TRdcServer): HWND;
    /// <summary>Schaal van de open sessie wijzigen (0 = automatisch); geldt tot die sessie wordt gesloten.</summary>
    procedure SetDesktopScale(aServer: TRdcServer; aPercent: Cardinal);
    /// <summary>Reden van de laatste verbreking van de sessie van aServer (0 = geen/onbekend).</summary>
    function LastDisconnectReasonOf(aServer: TRdcServer): Integer;
    /// <summary>True als de sessie van aServer zonder fout verbroken is (door de gebruiker, afgemeld of door de
    /// server) en er geen fallback-reconnect volgt.</summary>
    function EndedNormally(aServer: TRdcServer): Boolean;
    function LastDisconnectTextOf(aServer: TRdcServer): string;
    /// <summary>Ingestelde schaal van de sessie (0 = automatisch), of -1 zonder sessie.</summary>
    function DesktopScaleOf(aServer: TRdcServer): Integer;
    /// <summary>Muisklik in de sessie van aServer.</summary>
    property OnActivated: TRdcSessionEvent read FOnActivated write FOnActivated;
    property OnPlaceHost: TRdcPlaceHostEvent read FOnPlaceHost write FOnPlaceHost;
    property OnCredentialRequest: TRdcCredentialRequest read FOnCredentialRequest write FOnCredentialRequest;
    property OnDisplayChanged: TRdcSessionEvent read FOnDisplayChanged write FOnDisplayChanged;
    property OnStateChanged: TRdcSessionEvent read FOnStateChanged write FOnStateChanged;
    /// <summary>Voor de route via Tailscale (van het hoofdvenster; moet langer leven dan deze manager).</summary>
    property TailnetManager: TRdcTailnetManager read FTailnets write FTailnets;
    /// <summary>Kluis voor de auth key / state-sleutel van een netwerk en het wachtwoord van een gateway.</summary>
    property Secrets: IRdcSecretAccess read FSecrets write FSecrets;
  end;

implementation

uses
  System.StrUtils,
  RdcmX.Log;

const
  WM_RDCX_FREE_PENDING = WM_USER + 10;

{ TRdcSessionManager }

constructor TRdcSessionManager.Create(aContainer: TWinControl);
begin
  inherited Create;
  FContainer := aContainer;
  FSessions := TDictionary<TRdcServer, TRdpSession>.Create;
  FPendingFree := TList<TRdpSession>.Create;
  FDetached := TList<TRdcServer>.Create;
  FTunnels := TObjectDictionary<TRdpSession, TRdcTunnel>.Create([doOwnsValues]);
  FTunnelTimer := TTimer.Create(nil);
  FTunnelTimer.Enabled := False;
  FTunnelTimer.Interval := 1000;
  FTunnelTimer.OnTimer := TunnelTimerFired;
  FMsgWnd := System.Classes.AllocateHWnd(MsgWndProc);
end;

destructor TRdcSessionManager.Destroy;
var
  lSession: TRdpSession;
begin
  FOnStateChanged := nil;
  FOnDisplayChanged := nil;
  FreeAndNil(FTunnelTimer);
  for lSession in FTunnels.Keys.ToArray do
    ReleaseTunnel(lSession);
  FTunnels.Free;
  for lSession in FSessions.Values do
  begin
    lSession.OnStateChanged := nil;
    lSession.OnDisplayChanged := nil;
    lSession.Free;
  end;
  FSessions.Free;
  for lSession in FPendingFree do
  begin
    lSession.OnStateChanged := nil;
    lSession.Free;
  end;
  FPendingFree.Free;
  FDetached.Free;
  if FMsgWnd <> 0 then
    System.Classes.DeallocateHWnd(FMsgWnd);
  inherited Destroy;
end;

function TRdcSessionManager.BuildSettings(aServer: TRdcServer; out aSettings: TRdpConnectionSettings; out aError: string): Boolean;
const
  cSizeModes: array[TRdcDisplayMode] of TRdpSizeMode = (rsmDynamic, rsmClientArea, rsmFixed, rsmFullScreen);
  // GatewayCredsSource van de control: 0 = wachtwoord (NTLM), 1 = smartcard, 4 = later kiezen.
  cGatewayCredsSource: array[TRdcGatewayLogonMethod] of Cardinal = (0, 1, 4);
var
  lConnection: TRdcConnectionSettings;
  lDomain: string;
  lExtras: TRdcxSettings;
  lGateway: TRdcGatewaySettings;
  lLocal: TRdcLocalResources;
  lRemoteDesktop: TRdcRemoteDesktopSettings;
  lUserName: string;
begin
  aError := '';
  aSettings := TRdpConnectionSettings.Default;
  aSettings.Server := aServer.Name;
  aSettings.DisplayName := aServer.Name;
  lConnection := aServer.EffectiveConnection;
  aSettings.Port := lConnection.Port;
  aSettings.ConnectToConsole := lConnection.ConnectToConsole;
  aSettings.StartProgram := lConnection.StartProgram;
  aSettings.WorkingDir := lConnection.WorkingDir;
  aSettings.LoadBalanceInfo := lConnection.LoadBalanceInfo;

  // Route Direct: de gatewaySettings uit de .rdg (RDCMan-compatibel), zoals altijd.
  lGateway := aServer.EffectiveGateway;
  aSettings.GatewayEnabled := lGateway.Enabled and (Trim(lGateway.HostName) <> '');
  aSettings.GatewayHostName := Trim(lGateway.HostName);
  aSettings.GatewayBypassLocal := lGateway.LocalBypass;
  aSettings.GatewayCredSharing := lGateway.CredSharing;
  aSettings.GatewayCredsSource := cGatewayCredsSource[lGateway.LogonMethod];
  aSettings.GatewayUserName := lGateway.UserName;
  aSettings.GatewayDomain := lGateway.Domain;
  // Extern RDCMan-profiel (buiten het bestand) is niet beschikbaar: dan vraagt de prompt de gebruikersnaam.
  if aServer.ResolveLogon(lDomain, lUserName) then
  begin
    aSettings.UserName := lUserName;
    aSettings.Domain := lDomain;
  end;
  aSettings.AuthenticationLevel := Cardinal(Ord(aServer.EffectiveSecurity.Authentication));

  lRemoteDesktop := aServer.EffectiveRemoteDesktop;
  aSettings.ColorDepth := lRemoteDesktop.ColorDepth;
  aSettings.FixedWidth := lRemoteDesktop.Width;
  aSettings.FixedHeight := lRemoteDesktop.Height;
  aSettings.SmartSizing := aServer.EffectiveDisplay.SmartSizeDockedWindows = ssScale;

  // Lokale bronnen (RDCMan localResources). Enum-volgorde = waarde voor de RDP-control.
  lLocal := aServer.EffectiveLocalResources;
  aSettings.RedirectClipboard := lLocal.RedirectClipboard;
  aSettings.RedirectDrives := lLocal.RedirectDrives;
  aSettings.RedirectPrinters := lLocal.RedirectPrinters;
  aSettings.RedirectPorts := lLocal.RedirectPorts;
  aSettings.RedirectSmartCards := lLocal.RedirectSmartCards;
  aSettings.RedirectDevices := lLocal.RedirectPnpDevices;
  aSettings.AudioRedirectionMode := Ord(lLocal.AudioRedirection);
  aSettings.AudioQualityMode := Ord(lLocal.AudioQuality);
  aSettings.AudioCaptureRedirection := lLocal.AudioCapture = acRecord;
  aSettings.KeyboardHookMode := Ord(lLocal.KeyboardHook);

  lExtras := aServer.EffectiveExtras;
  aSettings.SizeMode := cSizeModes[lExtras.DisplayMode];
  aSettings.ResizeDebounceMs := lExtras.ResizeDebounceMs;
  aSettings.ReconnectOnResizeFallback := lExtras.ReconnectOnResizeFallback;
  aSettings.DesktopScale := Cardinal(lExtras.DesktopScale);

  Result := True;
  case aServer.EffectiveRoute.Kind of
    rkGateway:
      Result := ApplyGatewayRoute(aServer, aSettings, aError);
    rkTailscale:
      // De gatewaySettings uit de .rdg gelden niet via Tailscale ("gateway via tailnet" komt later).
      aSettings.GatewayEnabled := False;
  end;
end;

function TRdcSessionManager.ApplyGatewayRoute(aServer: TRdcServer; var aSettings: TRdpConnectionSettings; out aError: string): Boolean;
const
  // GatewayCredsSource van de control: 0 = wachtwoord (NTLM), 1 = smartcard, 4 = later kiezen.
  cCredsSource: array[TRdcGatewayLogonMethod] of Cardinal = (0, 1, 4);
var
  lGateway: TRdcGatewayDef;
  lPassword: string;
begin
  aError := '';
  lGateway := nil;
  if aServer.RdcFile <> nil then
    lGateway := aServer.RdcFile.FindGateway(aServer.EffectiveRoute.GatewayId);
  if (lGateway = nil) or (Trim(lGateway.HostName) = '') then
  begin
    aError := 'De route "Via RDP-gateway" verwijst naar een gateway die niet (meer) in dit bestand staat. Kies in Eigenschappen > Route een gateway.';
    Exit(False);
  end;
  aSettings.GatewayEnabled := True;
  aSettings.GatewayHostName := lGateway.Address;
  aSettings.GatewayAutoDetect := lGateway.Usage = guAutoDetect;
  aSettings.GatewayBypassLocal := lGateway.Usage = guBypassLocal;
  aSettings.GatewayCredsSource := cCredsSource[lGateway.AuthMethod];
  aSettings.GatewayUserName := '';
  aSettings.GatewayDomain := '';
  case lGateway.CredsMode of
    gcmSession:
      aSettings.GatewayCredSharing := True;
    gcmSeparate:
      begin
        aSettings.GatewayCredSharing := False;
        aSettings.GatewayUserName := lGateway.UserName;
        aSettings.GatewayDomain := lGateway.Domain;
        // Zonder opgeslagen wachtwoord (of als de kluis dicht blijft) vraagt Windows er zelf om.
        // Het wachtwoord is gebonden aan id én host:poort: een bestand dat de host heeft veranderd krijgt het niet.
        if (FSecrets <> nil) and FSecrets.HasSecret(TRdcPasswordVault.GatewayTarget(lGateway.Id, lGateway.Address)) and FSecrets.LoadSecret(TRdcPasswordVault.GatewayTarget(lGateway.Id, lGateway.Address), Format('Gateway "%s" gebruikt een wachtwoord uit de wachtwoordkluis.', [lGateway.Name]), lPassword) then
        begin
          aSettings.GatewayPassword := lPassword;
          WipeString(lPassword);
        end;
      end;
    gcmAsk:
      aSettings.GatewayCredSharing := False;
    gcmSmartCard:
      begin
        aSettings.GatewayCredSharing := False;
        aSettings.GatewayCredsSource := cCredsSource[glmSmartCard];
      end;
  end;
  TRdcLog.Write(Format('%s: route via gateway "%s" (%s)', [aServer.Caption, lGateway.Name, lGateway.Address]));
  Result := True;
end;

procedure TRdcSessionManager.ConnectViaTailnet(aServer: TRdcServer; aSession: TRdpSession);
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lGuard: IRdcCallbackGuard;
  lHost: string;
  lRoute: TRdcxRouteSettings;
  lTarget: string;
  lTunnel: TRdcTunnel;
begin
  lRoute := aServer.EffectiveRoute;
  lDef := nil;
  if aServer.RdcFile <> nil then
    lDef := aServer.RdcFile.FindTailnet(lRoute.TailnetId);
  aSession.BeginPrepare('Verbinden via Tailscale...');
  if lDef = nil then
  begin
    aSession.PrepareFailed('De route "Via Tailscale-netwerk" verwijst naar een netwerk dat niet (meer) in dit bestand staat. Kies in Eigenschappen > Route een netwerk.');
    Exit;
  end;
  if (FTailnets = nil) or not TRdcTsBridge.Available then
  begin
    aSession.PrepareFailed('Verbinden via Tailscale is niet beschikbaar: ' + TRdcTsBridge.LoadError);
    Exit;
  end;
  lHost := Trim(lRoute.TailnetHost);
  if lHost = '' then
    lHost := aServer.Name;
  if Pos('@', lHost) > 0 then
  begin
    aSession.PrepareFailed(Format('"%s" is een e-mailadres (het Tailscale-account), geen apparaat. Vul in Eigenschappen > Route bij "Adres in het tailnet" de machinenaam in (adminconsole > Machines, bijv. thuis-pc) of het 100.x-adres.', [lHost]));
    Exit;
  end;
  lTarget := RdcTailnetTarget(lHost, aSession.Settings.Port);

  // Bestaande forward van deze sessie (opnieuw verbinden): hergebruiken als netwerk en doel gelijk zijn.
  if FTunnels.TryGetValue(aSession, lTunnel) then
  begin
    if SameText(lTunnel.TailnetId, lDef.Id) and SameText(lTunnel.Target, lTarget) and (lTunnel.Port > 0) and FTailnets.IsRunning(lDef.Id) then
    begin
      if not FTailnets.CheckTarget(lDef.Id, lTarget, lError) then
      begin
        aSession.PrepareFailed(lError);
        Exit;
      end;
      aSession.SetEndpoint(lTunnel.LocalAddress, lTunnel.Port);
      TRdcLog.Write(Format('%s: via Tailscale "%s", bestaande forward %s:%d -> %s', [aServer.Caption, lDef.Name, lTunnel.LocalAddress, lTunnel.Port, lTarget]));
      aSession.Connect;
      Exit;
    end;
    ReleaseTunnel(aSession);
  end;

  if not RdcBuildTailnetConfig(lDef, FSecrets, '', lConfig, lError) then
  begin
    aSession.PrepareFailed(Format('Tailscale-netwerk "%s": %s', [lDef.Name, lError]));
    Exit;
  end;
  lTunnel := TRdcTunnel.Create;
  lTunnel.TailnetId := lDef.Id;
  lTunnel.TailnetName := lDef.Name;
  lTunnel.LocalAddress := RdcTailnetLocalAddress(lDef);
  lTunnel.Target := lTarget;
  lTunnel.Guard := RdcNewCallbackGuard;
  FTunnels.Add(aSession, lTunnel);
  lGuard := lTunnel.Guard;
  aSession.BeginPrepare(Format('Verbinden met Tailscale-netwerk "%s"...', [lDef.Name]));
  TRdcLog.Write(Format('%s: via Tailscale "%s" naar %s', [aServer.Caption, lDef.Name, lTarget]));
  // Acquire wist lConfig (geheimen); het resultaat komt via de message queue.
  FTailnets.Acquire(lConfig,
    procedure(aSuccess: Boolean; const aStartError: string)
    begin
      if lGuard.IsValid then
        TunnelReady(aSession, aSuccess, aStartError);
    end);
  FTunnelTimer.Enabled := True;
end;

procedure TRdcSessionManager.TunnelReady(aSession: TRdpSession; aSuccess: Boolean; const aError: string);
var
  lError: string;
  lTunnel: TRdcTunnel;
begin
  if not FTunnels.TryGetValue(aSession, lTunnel) then
    Exit;
  if not aSuccess then
  begin
    ReleaseTunnel(aSession);
    aSession.PrepareFailed(Format('Het Tailscale-netwerk "%s" kon niet worden gestart: %s', [lTunnel.TailnetName, aError]));
    Exit;
  end;
  // Doel offline of niet in het tailnet: nu een duidelijke melding, in plaats van straks een algemene RDP-fout.
  if not FTailnets.CheckTarget(lTunnel.TailnetId, lTunnel.Target, lError) then
  begin
    ReleaseTunnel(aSession);
    aSession.PrepareFailed(lError);
    Exit;
  end;
  try
    // Poort 0: het besturingssysteem kiest een vrije poort; de bridge geeft die terug.
    lTunnel.Port := FTailnets.AddForward(lTunnel.TailnetId, lTunnel.LocalAddress + ':0', lTunnel.Target);
  except
    on E: Exception do
    begin
      ReleaseTunnel(aSession);
      aSession.PrepareFailed(E.Message);
      Exit;
    end;
  end;
  TRdcLog.Write(Format('Tailscale-forward %s:%d -> %s', [lTunnel.LocalAddress, lTunnel.Port, lTunnel.Target]));
  // De control verbindt met de lokale forward; tab, boom en statusteksten houden de echte servernaam.
  aSession.SetEndpoint(lTunnel.LocalAddress, lTunnel.Port);
  aSession.Connect;
end;

procedure TRdcSessionManager.ReleaseTunnel(aSession: TRdpSession);
var
  lTunnel: TRdcTunnel;
begin
  if not FTunnels.TryGetValue(aSession, lTunnel) then
    Exit;
  lTunnel.Guard.Invalidate;
  if FTailnets <> nil then
  begin
    if lTunnel.Port > 0 then
      FTailnets.RemoveForward(lTunnel.TailnetId, lTunnel.Port);
    // Laatste gebruiker: het netwerk sluit (een lopende start wordt afgebroken).
    FTailnets.Release(lTunnel.TailnetId);
  end;
  FTunnels.Remove(aSession);
end;

procedure TRdcSessionManager.TunnelTimerFired(aSender: TObject);
var
  lPair: TPair<TRdpSession, TRdcTunnel>;
  lPending: Boolean;
  lStatus: TRdcTailnetStatus;
begin
  // Netwerken die nog starten: bij interactief inloggen de login-pagina één keer in de browser openen.
  lPending := False;
  for lPair in FTunnels do
    if (lPair.Value.Port = 0) and (FTailnets <> nil) then
    begin
      lPending := True;
      if FTailnets.TryStatus(lPair.Value.TailnetId, lStatus) and (lStatus.AuthUrl <> '') and (lStatus.AuthUrl <> lPair.Value.AuthUrlOpened) then
      begin
        lPair.Value.AuthUrlOpened := lStatus.AuthUrl;
        if not RdcOpenAuthUrl(lStatus.AuthUrl) then
          Continue;
        lPair.Key.Host.StatusText := Format('Inloggen bij Tailscale-netwerk "%s": de login-pagina is in de browser geopend.'#13#10#13#10'%s', [lPair.Value.TailnetName, lStatus.AuthUrl]);
      end;
    end;
  if not lPending then
    FTunnelTimer.Enabled := False;
end;

function TRdcSessionManager.Connect(aServer: TRdcServer): Boolean;
var
  lDomain: string;
  lError: string;
  lRouteError: string;
  lPassword: string;
  lSession: TRdpSession;
  lSettings: TRdpConnectionSettings;
  lUserName: string;
begin
  Result := False;
  lSession := Find(aServer);
  if (lSession <> nil) and (lSession.State <> rssDisconnected) then
    Exit(True);

  // Route niet bruikbaar (gateway niet gevonden): geen wachtwoord vragen; de fout komt in de tab (hieronder).
  if BuildSettings(aServer, lSettings, lError) then
    lRouteError := ''
  else
    lRouteError := lError;
  lUserName := lSettings.UserName;
  lDomain := lSettings.Domain;
  lPassword := '';
  if (lRouteError = '') and Assigned(FOnCredentialRequest) and not FOnCredentialRequest(aServer, lUserName, lDomain, lPassword) then
  begin
    WipeString(lSettings.GatewayPassword);
    Exit;
  end;
  lSettings.UserName := lUserName;
  lSettings.Domain := lDomain;
  lSettings.Password := lPassword;
  WipeString(lPassword);

  if lSession = nil then
  begin
    lSession := TRdpSession.Create(FContainer);
    lSession.Host.Visible := False;
    lSession.Host.OnActivated := HostActivated;
    if Assigned(FOnPlaceHost) then
      FOnPlaceHost(aServer, lSession.Host);
    lSession.Data := aServer;
    lSession.OnLog := SessionLog;
    lSession.OnStateChanged := SessionStateChanged;
    lSession.OnDisplayChanged := SessionDisplayChanged;
    FSessions.Add(aServer, lSession);
    TRdcLog.Write(Format('%s: RDP-control %s', [aServer.Caption, lSession.ControlClassName]));
  end;

  lSession.Settings := lSettings;
  WipeString(lSettings.Password);
  WipeString(lSettings.GatewayPassword);
  if lRouteError <> '' then
  begin
    lSession.BeginPrepare('');
    lSession.PrepareFailed(lRouteError);
  end
  else if aServer.EffectiveRoute.Kind = rkTailscale then
    ConnectViaTailnet(aServer, lSession)
  else
  begin
    // Geen (andere) Tailscale-route meer: een oude forward van deze sessie opruimen.
    ReleaseTunnel(lSession);
    lSession.Connect;
  end;
  Result := True;
end;

procedure TRdcSessionManager.Disconnect(aServer: TRdcServer);
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if lSession <> nil then
    lSession.Disconnect;
end;

procedure TRdcSessionManager.DisconnectAll;
var
  lSession: TRdpSession;
begin
  for lSession in FSessions.Values do
    lSession.Disconnect;
end;

function TRdcSessionManager.Find(aServer: TRdcServer): TRdpSession;
begin
  if (aServer = nil) or not FSessions.TryGetValue(aServer, Result) then
    Result := nil;
end;

function TRdcSessionManager.HasError(aServer: TRdcServer): Boolean;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  Result := (lSession <> nil) and (lSession.State = rssDisconnected) and (lSession.LastError <> '');
end;

function TRdcSessionManager.StateOf(aServer: TRdcServer): TRdpSessionState;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if lSession <> nil then
    Result := lSession.State
  else
    Result := rssDisconnected;
end;

function TRdcSessionManager.ActiveServers: TArray<TRdcServer>;
var
  lPair: TPair<TRdcServer, TRdpSession>;
begin
  Result := nil;
  for lPair in FSessions do
    if lPair.Value.State <> rssDisconnected then
      Result := Result + [lPair.Key];
end;

function TRdcSessionManager.ActiveCount: Integer;
var
  lSession: TRdpSession;
begin
  Result := 0;
  for lSession in FSessions.Values do
    if lSession.State <> rssDisconnected then
      Inc(Result);
  for lSession in FPendingFree do
    if lSession.State <> rssDisconnected then
      Inc(Result);
end;

procedure TRdcSessionManager.NotifyDpiChanged;
var
  lSession: TRdpSession;
begin
  for lSession in FSessions.Values do
    lSession.NotifyDpiChanged;
end;

procedure TRdcSessionManager.Release(aServer: TRdcServer);
var
  lSession: TRdpSession;
begin
  if IsDetached(aServer) then
    Reattach(aServer);
  lSession := Find(aServer);
  if lSession = nil then
    Exit;
  FSessions.Remove(aServer);
  ReleaseTunnel(lSession);
  lSession.Data := nil;
  lSession.OnDisplayChanged := nil;
  lSession.Host.OnActivated := nil;
  lSession.Host.Visible := False;
  FPendingFree.Add(lSession);
  lSession.OnStateChanged := PendingSessionStateChanged;
  if lSession.State = rssDisconnected then
    PostMessage(FMsgWnd, WM_RDCX_FREE_PENDING, 0, 0)
  else
    lSession.Disconnect;
end;

procedure TRdcSessionManager.ShowServers(const aServers: array of TRdcServer; const aRects: array of TRect);

  function IndexOfServer(aServer: TRdcServer): Integer;
  begin
    for Result := 0 to High(aServers) do
      if aServers[Result] = aServer then
        Exit;
    Result := -1;
  end;

var
  lIndex: Integer;
  lPair: TPair<TRdcServer, TRdpSession>;
begin
  // Eerst de zichtbare op hun plek zetten en tonen, dan de rest verbergen: voorkomt een flits van het lege paneel.
  for lPair in FSessions do
  begin
    lIndex := IndexOfServer(lPair.Key);
    if (lIndex < 0) or IsDetached(lPair.Key) then
      Continue;
    if lPair.Value.Host.BoundsRect <> aRects[lIndex] then
      lPair.Value.Host.BoundsRect := aRects[lIndex];
    lPair.Value.Host.Visible := True;
  end;
  for lPair in FSessions do
    if (IndexOfServer(lPair.Key) < 0) and not IsDetached(lPair.Key) then
      lPair.Value.Host.Visible := False;
end;

procedure TRdcSessionManager.Detach(aServer: TRdcServer; aParentWnd: HWND);
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if (lSession = nil) or (aParentWnd = 0) then
    Exit;
  Winapi.Windows.SetParent(lSession.Host.Handle, aParentWnd);
  if not FDetached.Contains(aServer) then
    FDetached.Add(aServer);
  lSession.Host.Visible := True;
end;

procedure TRdcSessionManager.Reattach(aServer: TRdcServer);
var
  lSession: TRdpSession;
begin
  FDetached.Remove(aServer);
  lSession := Find(aServer);
  if lSession = nil then
    Exit;
  lSession.Host.Visible := False;
  Winapi.Windows.SetParent(lSession.Host.Handle, FContainer.Handle);
end;

function TRdcSessionManager.IsDetached(aServer: TRdcServer): Boolean;
begin
  Result := FDetached.Contains(aServer);
end;

procedure TRdcSessionManager.PlaceDetached(aServer: TRdcServer; const aRect: TRect);
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if (lSession <> nil) and IsDetached(aServer) then
    lSession.Host.BoundsRect := aRect;
end;

procedure TRdcSessionManager.SetDesktopScale(aServer: TRdcServer; aPercent: Cardinal);
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if lSession <> nil then
    lSession.SetDesktopScale(aPercent);
end;



function TRdcSessionManager.LastDisconnectTextOf(aServer: TRdcServer): string;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if lSession <> nil then
    Result := lSession.LastDisconnectText
  else
    Result := '';
end;


function TRdcSessionManager.EndedNormally(aServer: TRdcServer): Boolean;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  Result := (lSession <> nil) and (lSession.State = rssDisconnected) and not lSession.ReconnectPending and (lSession.LastError = '');
end;

function TRdcSessionManager.LastDisconnectReasonOf(aServer: TRdcServer): Integer;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if lSession <> nil then
    Result := lSession.LastDisconnectReason
  else
    Result := 0;
end;

function TRdcSessionManager.DesktopScaleOf(aServer: TRdcServer): Integer;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if lSession <> nil then
    Result := Integer(lSession.Settings.DesktopScale)
  else
    Result := -1;
end;

function TRdcSessionManager.ControlHandle(aServer: TRdcServer): HWND;
var
  lSession: TRdpSession;
begin
  lSession := Find(aServer);
  if (lSession <> nil) and lSession.Host.HandleAllocated then
    Result := GetWindow(lSession.Host.Handle, GW_CHILD)
  else
    Result := 0;
end;

procedure TRdcSessionManager.HostActivated(aSender: TObject);
var
  lPair: TPair<TRdcServer, TRdpSession>;
begin
  for lPair in FSessions do
    if lPair.Value.Host = aSender then
    begin
      if Assigned(FOnActivated) then
        FOnActivated(Self, lPair.Key);
      Exit;
    end;
end;

procedure TRdcSessionManager.PendingSessionStateChanged(aSender: TObject);
begin
  if TRdpSession(aSender).State = rssDisconnected then
    PostMessage(FMsgWnd, WM_RDCX_FREE_PENDING, 0, 0);
end;

procedure TRdcSessionManager.FreePendingSessions;
var
  lIndex: Integer;
  lSession: TRdpSession;
begin
  for lIndex := FPendingFree.Count - 1 downto 0 do
  begin
    lSession := FPendingFree[lIndex];
    if lSession.State = rssDisconnected then
    begin
      FPendingFree.Delete(lIndex);
      lSession.OnStateChanged := nil;
      lSession.Free;
    end;
  end;
end;

procedure TRdcSessionManager.MsgWndProc(var aMessage: TMessage);
begin
  if aMessage.Msg = WM_RDCX_FREE_PENDING then
    FreePendingSessions
  else
    aMessage.Result := DefWindowProc(FMsgWnd, aMessage.Msg, aMessage.WParam, aMessage.LParam);
end;

procedure TRdcSessionManager.SessionStateChanged(aSender: TObject);
var
  lServer: TRdcServer;
begin
  lServer := TRdcServer(TRdpSession(aSender).Data);
  if lServer = nil then
    Exit;
  TRdcLog.Write(Format('%s: status %s', [lServer.Caption, cRdpSessionStateNames[TRdpSession(aSender).State]]));
  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self, lServer);
end;

procedure TRdcSessionManager.SessionDisplayChanged(aSender: TObject);
var
  lServer: TRdcServer;
begin
  lServer := TRdcServer(TRdpSession(aSender).Data);
  if (lServer <> nil) and Assigned(FOnDisplayChanged) then
    FOnDisplayChanged(Self, lServer);
end;

procedure TRdcSessionManager.SessionLog(aSender: TObject; const aMessage: string);
var
  lServer: TRdcServer;
begin
  lServer := TRdcServer(TRdpSession(aSender).Data);
  if lServer <> nil then
    TRdcLog.Write(lServer.Caption + ': ' + aMessage)
  else
    TRdcLog.Write(aMessage);
end;

end.
