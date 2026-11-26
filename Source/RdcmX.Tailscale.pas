unit RdcmX.Tailscale;

{
  Tailscale-route: RDCManagerX wordt zelf een node in een tailnet via tsbridge.dll (Go, tailscale.com/tsnet, volledig
  in userspace; geen installatie, driver of beheerrechten). Per RDP-sessie een lokale TCP-forward
  (127.0.0.2:<poort>) naar het doel in het tailnet; de RDP-control verbindt met die forward.

  - TRdcTsBridge: laadt de DLL dynamisch bij het eerste gebruik en ontlaadt hem NOOIT (een Go-DLL kan niet veilig
    ontladen worden). De DLL zit gecomprimeerd (gzip) als resource TSBRIDGE in de exe (de launcher kopieert alleen de
    exe) en wordt uitgepakt naar %LOCALAPPDATA%\RDCManagerX\bin\tsbridge-<hash>.dll; laden vanuit geheugen kan niet
    betrouwbaar met een Go-DLL en lijkt op malware-gedrag. Zonder resource (testproject): naast de exe. In beide gevallen
    alleen met de vastgelegde controlesom. Ontbreekt de DLL, dan is Available False met een uitleg in LoadError.
  - TRdcTailnet: één node (handle in de DLL). Up blokkeert: alleen vanuit een achtergrondthread aanroepen.
  - TRdcTailnetManager: nodes per netwerk-id met reference counting. Acquire start de node (op de achtergrond) bij
    de eerste gebruiker; Release sluit hem na de laatste. Een Release tijdens het starten breekt het starten af.

  Geheimen (auth key, state-sleutel) gaan alleen als JSON naar TsNetCreate; die tekst wordt daarna overschreven.
  Ze komen nooit in de log (de DLL filtert ze ook uit zijn eigen debuglog).
}

interface

uses
  Winapi.Windows,
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  RdcmX.Credentials,
  RdcmX.Model;

const
  cTsBridgeDll = 'tsbridge.dll';
  cTsDefaultUpTimeoutMs = 120000; // ruim: interactieve login in de browser
  cTsDefaultLocalAddress = '127.0.0.2';

  // Returncodes van tsbridge.dll
  cTsOk = 0;
  cTsInvalidHandle = -1;
  cTsInvalidArgs = -2;
  cTsTimeout = -3;
  cTsClosed = -4;
  cTsFailed = -5;
  cTsNotFound = -6;
  cTsOffline = -7;

type
  /// <summary>Configuratie van één node, zoals TsNetCreate die verwacht. Bevat geheimen: na gebruik Wipe.</summary>
  TRdcTailnetConfig = record
    Id: string;
    HostName: string;
    AuthKey: string;
    Ephemeral: Boolean;
    ControlUrl: string;
    Dir: string;
    StateKey: string; // base64, 32 bytes; verplicht bij niet-ephemeral
    LogFile: string;
    function ToJson: string;
    procedure Wipe;
  end;

  TRdcTailnetStatus = record
    State: string; // NoState, Starting, NeedsLogin, NeedsMachineAuth, Running, Stopped, Closed
    IPs: TArray<string>;
    DnsName: string;
    AuthUrl: string;
    LastError: string;
    function IsRunning: Boolean;
    class function FromJson(const aJson: string): TRdcTailnetStatus; static;
  end;

  TRdcTsBridge = class
  private
    class var FLoaded: Boolean;
    class var FAvailable: Boolean;
    class var FLoadError: string;
    class var FLock: TObject;
    class procedure EnsureLoaded; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>True als tsbridge.dll geladen kon worden (laadt bij de eerste aanroep).</summary>
    class function Available: Boolean; static;
    /// <summary>Uitleg waarom de DLL niet beschikbaar is.</summary>
    class function LoadError: string; static;
    class function Version: string; static;
    /// <summary>Tekst bij een returncode van de DLL.</summary>
    class function CodeText(aCode: Integer): string; static;
  end;

  ETsBridge = class(Exception);

  /// <summary>Eén node in een tailnet. Thread-safe voor zover de DLL dat is (alle functies zijn thread-safe).</summary>
  TRdcTailnet = class
  private
    FHandle: Integer;
    function LastErrorText: string;
  public
    /// <summary>Maakt de node aan (nog niet verbonden). aConfig wordt niet gewist; doe dat zelf.</summary>
    constructor Create(const aConfig: TRdcTailnetConfig);
    destructor Destroy; override;
    /// <summary>Blokkeert tot de node in het tailnet zit, tot de time-out of tot Close. Alleen vanuit een
    /// achtergrondthread. Geeft een returncode (cTsOk bij succes); aError met uitleg.</summary>
    function Up(aTimeoutMs: Integer; out aError: string): Integer;
    function Status: TRdcTailnetStatus;
    /// <summary>Lokale forward naar aTarget (host:poort in het tailnet). Geeft de lokale poort.</summary>
    function AddForward(const aLocalAddress, aTarget: string): Integer;
    procedure RemoveForward(aLocalPort: Integer);
    /// <summary>Staat aTarget (host:poort) in het tailnet en is het apparaat online? False met uitleg (bijv.
    /// "thuis-pc is offline in het tailnet (laatst gezien ...)").</summary>
    function CheckTarget(const aTarget: string; out aError: string): Boolean;
    /// <summary>Sluit de node (breekt een lopende Up af). Mag vanuit elke thread.</summary>
    procedure Close;
    property Handle: Integer read FHandle;
  end;

  /// <summary>Resultaat van Acquire, op de hoofdthread.</summary>
  TRdcTailnetReadyProc = reference to procedure(aSuccess: Boolean; const aError: string);

  TRdcTailnetManager = class
  private type
    TEntryState = (esStarting, esRunning, esFailed);
    TEntry = class
      Net: TRdcTailnet;
      RefCount: Integer;
      State: TEntryState;
      Error: string;
      Orphaned: Boolean; // laatste Release tijdens het starten: StartFinished ruimt op
      Waiters: TList<TRdcTailnetReadyProc>;
      constructor Create;
      destructor Destroy; override;
    end;
    /// <summary>Gedeeld met de achtergrondthreads: na Destroy van de manager doen nagekomen resultaten niets.</summary>
    IAlive = interface
      function GetAlive: Boolean;
      procedure SetAlive(aValue: Boolean);
      property Alive: Boolean read GetAlive write SetAlive;
    end;
    TAlive = class(TInterfacedObject, IAlive)
    private
      FAlive: Integer;
      function GetAlive: Boolean;
      procedure SetAlive(aValue: Boolean);
    end;
  private
    FEntries: TDictionary<string, TEntry>;
    FAlive: IAlive;
    FUpTimeoutMs: Integer;
    procedure StartFinished(aEntry: TEntry; aCode: Integer; const aError: string);
    procedure CloseInBackground(aNet: TRdcTailnet);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Netwerk aConfig.Id in gebruik nemen (refcount + 1). Draait het nog niet, dan wordt het op de
    /// achtergrond gestart; aOnReady volgt via de message queue. Elke Acquire vraagt precies één Release, ook bij
    /// een fout. aConfig wordt na gebruik gewist.</summary>
    procedure Acquire(var aConfig: TRdcTailnetConfig; const aOnReady: TRdcTailnetReadyProc);
    /// <summary>Gebruik beëindigen; de laatste sluit het netwerk (ook als het nog aan het starten was).</summary>
    procedure Release(const aId: string);
    function IsRunning(const aId: string): Boolean;
    function RefCount(const aId: string): Integer;
    /// <summary>Status voor de voortgang (login-URL). False als het netwerk niet in gebruik is.</summary>
    function TryStatus(const aId: string; out aStatus: TRdcTailnetStatus): Boolean;
    /// <summary>Forward op een draaiend netwerk; raises ETsBridge bij een fout.</summary>
    function AddForward(const aId, aLocalAddress, aTarget: string): Integer;
    procedure RemoveForward(const aId: string; aLocalPort: Integer);
    /// <summary>Zie TRdcTailnet.CheckTarget; False ook als het netwerk niet draait.</summary>
    function CheckTarget(const aId, aTarget: string; out aError: string): Boolean;
    /// <summary>Alles sluiten (afsluiten van de app); blokkeert kort.</summary>
    procedure CloseAll;
    property UpTimeoutMs: Integer read FUpTimeoutMs write FUpTimeoutMs;
  end;

  /// <summary>Voor callbacks die later via de message queue binnenkomen: na Invalidate doen ze niets meer
  /// (bijv. als het scherm dat ze startte al gesloten is).</summary>
  IRdcCallbackGuard = interface
    ['{4C1D2B7E-8F3A-4E62-A1B9-0D5C6E7F8A92}']
    function IsValid: Boolean;
    procedure Invalidate;
  end;

/// <summary>Nieuwe guard (geldig tot Invalidate).</summary>
function RdcNewCallbackGuard: IRdcCallbackGuard;

/// <summary>Standaard node-hostname: rdpclient-&lt;computernaam&gt; (kleine letters).</summary>
function RdcDefaultTailnetHostName: string;

/// <summary>Werkmap van een netwerk: %LOCALAPPDATA%\RDCManagerX\tailscale\&lt;id&gt;.</summary>
function RdcTailnetDir(const aTailnetId: string): string;

/// <summary>Effectief lokaal adres voor forwards van dit netwerk (standaard 127.0.0.2).</summary>
function RdcTailnetLocalAddress(aDef: TRdcTailnetDef): string;

/// <summary>Configuratie voor TsNetCreate uit de definitie en de kluis. aAuthKey: net ingevoerde key (leeg = uit de
/// kluis, of geen: interactieve login). Niet-ephemeral: de state-sleutel komt uit de kluis en wordt de eerste keer
/// aangemaakt; zonder kluis False met uitleg in aError. aConfig bevat geheimen: na gebruik Wipe.</summary>
function RdcBuildTailnetConfig(aDef: TRdcTailnetDef; const aSecrets: IRdcSecretAccess; const aAuthKey: string; out aConfig: TRdcTailnetConfig; out aError: string): Boolean;

/// <summary>Doel host:poort; IPv6-adressen tussen haken.</summary>
function RdcTailnetTarget(const aHost: string; aPort: Integer): string;

/// <summary>Geldige naam in het tailnet: 1-63 tekens a-z, 0-9 en '-', niet beginnend of eindigend met '-'.</summary>
function RdcIsValidNodeHostName(const aName: string): Boolean;
/// <summary>Lokaal forward-adres: IPv4 in 127.0.0.0/8 (nooit 0.0.0.0 of een LAN-adres).</summary>
function RdcIsValidLoopbackAddress(const aAddress: string): Boolean;
/// <summary>Control URL: leeg (Tailscale), https://host..., of http:// alleen naar localhost/127.x (anders kan de
/// auth key onderweg worden onderschept).</summary>
function RdcIsValidControlUrl(const aUrl: string): Boolean;
/// <summary>Opent een login-URL van Tailscale in de browser, maar alleen een https-adres zonder vreemde tekens
/// (een kwaadaardige control server kan anders via ShellExecute een programma laten starten). False als geweigerd.</summary>
function RdcOpenAuthUrl(const aUrl: string): Boolean;

implementation

uses
  Winapi.ShellAPI,
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.NetEncoding,
  System.StrUtils,
  System.ZLib,
  RdcmX.Crypto,
  RdcmX.Lang,
  RdcmX.Log;

// cTsBridgeSha256: controlesom van de tsbridge.dll die bij deze build hoort (Tools\build-tsbridge.cmd schrijft dit).
{$I 'RdcmX.TsBridgeHash.inc'}

function RdcIsValidNodeHostName(const aName: string): Boolean;
var
  lChar: Char;
begin
  Result := (Length(aName) >= 1) and (Length(aName) <= 63) and (aName[1] <> '-') and (aName[Length(aName)] <> '-');
  if Result then
    for lChar in aName do
      if not CharInSet(lChar, ['a'..'z', '0'..'9', '-']) then
        Exit(False);
end;

function RdcIsValidLoopbackAddress(const aAddress: string): Boolean;
var
  lPart: string;
  lParts: TArray<string>;
  lValue: Integer;
begin
  lParts := aAddress.Split(['.']);
  Result := (Length(lParts) = 4) and (lParts[0] = '127');
  if Result then
    for lPart in lParts do
      if not TryStrToInt(lPart, lValue) or (lValue < 0) or (lValue > 255) or (lPart <> IntToStr(lValue)) then
        Exit(False);
end;

function UrlHost(const aRest: string): string;
var
  lEnd: Integer;
begin
  // aRest = alles na "scheme://"; host tot de eerste / ? # of : (geen IPv6-notatie nodig hier).
  lEnd := Length(aRest) + 1;
  for var lChar in ['/', '?', '#', ':', '@'] do
    if (Pos(lChar, aRest) > 0) and (Pos(lChar, aRest) < lEnd) then
      lEnd := Pos(lChar, aRest);
  Result := LowerCase(Copy(aRest, 1, lEnd - 1));
end;

function HasUnsafeChars(const aText: string): Boolean;
var
  lChar: Char;
begin
  for lChar in aText do
    if (Ord(lChar) <= 32) or CharInSet(lChar, ['"', '<', '>', '^', '`', '{', '|', '}', '\']) then
      Exit(True);
  Result := False;
end;

function RdcIsValidControlUrl(const aUrl: string): Boolean;
var
  lHost: string;
  lUrl: string;
begin
  lUrl := Trim(aUrl);
  if lUrl = '' then
    Exit(True);
  if HasUnsafeChars(lUrl) or (Pos('@', lUrl) > 0) then
    Exit(False);
  if lUrl.StartsWith('https://', True) then
    Exit(UrlHost(Copy(lUrl, 9, MaxInt)) <> '');
  if lUrl.StartsWith('http://', True) then
  begin
    lHost := UrlHost(Copy(lUrl, 8, MaxInt));
    Exit((lHost = 'localhost') or RdcIsValidLoopbackAddress(lHost));
  end;
  Result := False;
end;

function RdcOpenAuthUrl(const aUrl: string): Boolean;
begin
  Result := aUrl.StartsWith('https://', True) and (UrlHost(Copy(aUrl, 9, MaxInt)) <> '') and not HasUnsafeChars(aUrl);
  if Result then
    ShellExecute(0, 'open', PChar(aUrl), nil, nil, SW_SHOWNORMAL)
  else
    TRdcLog.Write('Login-URL van Tailscale geweigerd (geen https-adres).');
end;

type
  TRdcCallbackGuard = class(TInterfacedObject, IRdcCallbackGuard)
  private
    FValid: Integer;
  public
    constructor Create;
    function IsValid: Boolean;
    procedure Invalidate;
  end;

constructor TRdcCallbackGuard.Create;
begin
  inherited Create;
  FValid := 1;
end;

function TRdcCallbackGuard.IsValid: Boolean;
begin
  Result := AtomicCmpExchange(FValid, 1, 1) = 1;
end;

procedure TRdcCallbackGuard.Invalidate;
begin
  AtomicExchange(FValid, 0);
end;

function RdcNewCallbackGuard: IRdcCallbackGuard;
begin
  Result := TRdcCallbackGuard.Create;
end;

function RdcTailnetDir(const aTailnetId: string): string;
var
  lId: string;
  lIndex: Integer;
begin
  // Alleen veilige tekens in de mapnaam (id is normaal een GUID).
  lId := LowerCase(aTailnetId);
  for lIndex := 1 to Length(lId) do
    if not CharInSet(lId[lIndex], ['a'..'z', '0'..'9', '-']) then
      lId[lIndex] := '_';
  Result := TPath.Combine(TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RDCManagerX'), 'tailscale'), lId);
end;

function RdcTailnetLocalAddress(aDef: TRdcTailnetDef): string;
begin
  // Het bestand kan gemanipuleerd zijn: alleen een loopback-adres, anders zou de tunnel voor het hele netwerk
  // openstaan. (De bridge controleert dit ook.)
  Result := Trim(aDef.LocalAddress);
  if (Result <> '') and not RdcIsValidLoopbackAddress(Result) then
  begin
    TRdcLog.Write(Format('Tailscale-netwerk "%s": lokaal adres "%s" is geen loopback-adres; %s gebruikt', [aDef.Name, Result, cTsDefaultLocalAddress]));
    Result := '';
  end;
  if Result = '' then
    Result := cTsDefaultLocalAddress;
end;

function RdcBuildTailnetConfig(aDef: TRdcTailnetDef; const aSecrets: IRdcSecretAccess; const aAuthKey: string; out aConfig: TRdcTailnetConfig; out aError: string): Boolean;
var
  lKey: TBytes;
  lReason: string;
  lStateKey: string;
  lTarget: string;
begin
  aConfig := Default(TRdcTailnetConfig);
  aError := '';
  aConfig.Id := aDef.Id;
  // Waarden uit het bestand niet blind vertrouwen (het kan gemanipuleerd zijn).
  aConfig.HostName := Trim(aDef.NodeHostName);
  if not RdcIsValidNodeHostName(aConfig.HostName) then
    aConfig.HostName := RdcDefaultTailnetHostName;
  aConfig.Ephemeral := aDef.Ephemeral;
  aConfig.ControlUrl := Trim(aDef.ControlUrl);
  if not RdcIsValidControlUrl(aConfig.ControlUrl) then
  begin
    aError := Format(_('De control URL "%s" is niet toegestaan: gebruik https:// (http:// alleen naar localhost).'), [aConfig.ControlUrl]);
    Exit(False);
  end;
  aConfig.Dir := RdcTailnetDir(aDef.Id);
  if TRdcLog.Enabled then
    aConfig.LogFile := TPath.Combine(ExtractFilePath(TRdcLog.FileName), Format('tsbridge-%s.log', [ExtractFileName(aConfig.Dir)]));
  lReason := Format(_('Tailscale-netwerk "%s" gebruikt geheimen uit de wachtwoordkluis.'), [aDef.Name]);

  if aAuthKey <> '' then
    aConfig.AuthKey := aAuthKey
  else if aSecrets.HasSecret(TRdcPasswordVault.TailnetAuthKeyTarget(aDef.Id, aDef.ControlUrl)) then
  begin
    if not aSecrets.LoadSecret(TRdcPasswordVault.TailnetAuthKeyTarget(aDef.Id, aDef.ControlUrl), lReason, aConfig.AuthKey) then
    begin
      aError := _('De auth key in de wachtwoordkluis kon niet worden gelezen: het hoofdwachtwoord is niet ingevoerd, of "Wachtwoorden onthouden" staat uit (Bestand > Opties).');
      Exit(False);
    end;
  end;

  if not aDef.Ephemeral then
  begin
    // De node-sleutels worden op schijf versleuteld met een sleutel die alleen in de kluis staat.
    lTarget := TRdcPasswordVault.TailnetStateKeyTarget(aDef.Id, aDef.ControlUrl);
    if aSecrets.HasSecret(lTarget) then
    begin
      if not aSecrets.LoadSecret(lTarget, lReason, lStateKey) then
      begin
        aConfig.Wipe;
        aError := _('De sleutel van dit netwerk staat in de wachtwoordkluis, maar kon niet worden gelezen: het hoofdwachtwoord is niet ingevoerd, of "Wachtwoorden onthouden" staat uit (Bestand > Opties).');
        Exit(False);
      end;
    end
    else
    begin
      if not aSecrets.CanStoreSecrets then
      begin
        aConfig.Wipe;
        aError := _('Een niet-ephemeral netwerk bewaart zijn sleutels versleuteld met een sleutel uit de wachtwoordkluis. Zet "Wachtwoorden onthouden" aan in Opties, of maak het netwerk ephemeral.');
        Exit(False);
      end;
      // Nieuwe sleutel: een oude state (sleutel uit een geleegde kluis) is onleesbaar geworden; weg ermee, anders
      // weigert de bridge te starten. De node logt daarna opnieuw in.
      try
        if TDirectory.Exists(TPath.Combine(aConfig.Dir, 'state')) then
          TDirectory.Delete(TPath.Combine(aConfig.Dir, 'state'), True);
      except
        on E: Exception do
        begin
          aConfig.Wipe;
          aError := Format(_('De oude (onleesbare) state van dit netwerk kon niet worden verwijderd: %s'), [E.Message]);
          Exit(False);
        end;
      end;
      lKey := TRdcCrypto.RandomBytes(32);
      lStateKey := TNetEncoding.Base64String.EncodeBytesToString(lKey);
      WipeBytes(lKey);
      if not aSecrets.SaveSecret(lTarget, 'Tailscale ' + aDef.Name, lStateKey, lReason) then
      begin
        WipeString(lStateKey);
        aConfig.Wipe;
        aError := _('De sleutel van dit netwerk kon niet in de wachtwoordkluis worden opgeslagen.');
        Exit(False);
      end;
    end;
    aConfig.StateKey := lStateKey;
    WipeString(lStateKey);
  end;
  Result := True;
end;

type
  TTsBridgeVersion = function(aBuf: PAnsiChar; aBufLen: Integer): Integer; cdecl;
  TTsNetCreate = function(aConfigJson: PAnsiChar): Integer; cdecl;
  TTsNetUp = function(aHandle, aTimeoutMs: Integer): Integer; cdecl;
  TTsNetGetStatus = function(aHandle: Integer; aBuf: PAnsiChar; aBufLen: Integer): Integer; cdecl;
  TTsNetAddForward = function(aHandle: Integer; aLocalAddr, aTarget: PAnsiChar): Integer; cdecl;
  TTsNetRemoveForward = function(aHandle, aLocalPort: Integer): Integer; cdecl;
  TTsNetCheckTarget = function(aHandle: Integer; aTarget: PAnsiChar): Integer; cdecl;
  TTsNetClose = function(aHandle: Integer): Integer; cdecl;
  TTsLastError = function(aHandle: Integer; aBuf: PAnsiChar; aBufLen: Integer): Integer; cdecl;

var
  GTsBridgeVersion: TTsBridgeVersion;
  GTsNetCreate: TTsNetCreate;
  GTsNetUp: TTsNetUp;
  GTsNetGetStatus: TTsNetGetStatus;
  GTsNetAddForward: TTsNetAddForward;
  GTsNetRemoveForward: TTsNetRemoveForward;
  GTsNetCheckTarget: TTsNetCheckTarget;
  GTsNetClose: TTsNetClose;
  GTsLastError: TTsLastError;

type
  TTsTextFunc = reference to function(aBuf: PAnsiChar; aBufLen: Integer): Integer;

function ReadText(const aFunc: TTsTextFunc): string;
var
  lBuffer: TBytes;
  lNeeded: Integer;
begin
  // De DLL geeft het aantal benodigde bytes; bij afkappen opnieuw met een grotere buffer.
  SetLength(lBuffer, 1024);
  lNeeded := aFunc(PAnsiChar(@lBuffer[0]), Length(lBuffer));
  if lNeeded < 0 then
    Exit('');
  if lNeeded >= Length(lBuffer) then
  begin
    SetLength(lBuffer, lNeeded + 1);
    lNeeded := aFunc(PAnsiChar(@lBuffer[0]), Length(lBuffer));
    if (lNeeded < 0) or (lNeeded >= Length(lBuffer)) then
      Exit('');
  end;
  Result := TEncoding.UTF8.GetString(lBuffer, 0, lNeeded);
end;

function RdcDefaultTailnetHostName: string;
var
  lBuffer: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  lSize: DWORD;
begin
  lSize := Length(lBuffer);
  if GetComputerName(lBuffer, lSize) then
    Result := 'rdpclient-' + LowerCase(string(lBuffer))
  else
    Result := 'rdpclient';
end;

function RdcTailnetTarget(const aHost: string; aPort: Integer): string;
begin
  if (Pos(':', aHost) > 0) and not aHost.StartsWith('[') then
    Result := Format('[%s]:%d', [aHost, aPort])
  else
    Result := Format('%s:%d', [aHost, aPort]);
end;

{ TRdcTailnetConfig }

function TRdcTailnetConfig.ToJson: string;
var
  lObject: TJSONObject;
begin
  lObject := TJSONObject.Create;
  try
    lObject.AddPair('hostname', HostName);
    lObject.AddPair('authKey', AuthKey);
    lObject.AddPair('ephemeral', TJSONBool.Create(Ephemeral));
    lObject.AddPair('controlUrl', ControlUrl);
    lObject.AddPair('dir', Dir);
    lObject.AddPair('stateKey', StateKey);
    lObject.AddPair('logFile', LogFile);
    Result := lObject.ToJSON;
  finally
    lObject.Free;
  end;
end;

procedure TRdcTailnetConfig.Wipe;
begin
  WipeString(AuthKey);
  WipeString(StateKey);
end;

{ TRdcTailnetStatus }

function TRdcTailnetStatus.IsRunning: Boolean;
begin
  Result := SameText(State, 'Running');
end;

class function TRdcTailnetStatus.FromJson(const aJson: string): TRdcTailnetStatus;
var
  lArray: TJSONArray;
  lIndex: Integer;
  lValue: TJSONValue;
begin
  Result := Default(TRdcTailnetStatus);
  lValue := TJSONObject.ParseJSONValue(aJson);
  try
    if not (lValue is TJSONObject) then
      Exit;
    Result.State := lValue.GetValue<string>('state', '');
    Result.DnsName := lValue.GetValue<string>('dnsName', '');
    Result.AuthUrl := lValue.GetValue<string>('authUrl', '');
    Result.LastError := lValue.GetValue<string>('lastError', '');
    if TJSONObject(lValue).TryGetValue<TJSONArray>('ips', lArray) then
      for lIndex := 0 to lArray.Count - 1 do
        Result.IPs := Result.IPs + [lArray.Items[lIndex].Value];
  finally
    lValue.Free;
  end;
end;

{ TRdcTsBridge }

class constructor TRdcTsBridge.Create;
begin
  FLock := TObject.Create;
end;

class destructor TRdcTsBridge.Destroy;
begin
  // De DLL zelf blijft geladen (geen FreeLibrary).
  FreeAndNil(FLock);
end;

function FileSha256(aHandle: THandle): string;
var
  lStream: THandleStream;
begin
  lStream := THandleStream.Create(aHandle);
  try
    lStream.Position := 0;
    Result := LowerCase(THashSHA2.GetHashString(lStream, THashSHA2.TSHA2Version.SHA256));
  finally
    lStream.Free;
  end;
end;

const
  cTsBridgeResource = 'TSBRIDGE';
  // LoadLibraryEx flag (Windows 8+, not in Winapi.Windows of Delphi 12): resolve the module's imports from System32 only.
  LOAD_LIBRARY_SEARCH_SYSTEM32 = $00000800;

function HasEmbeddedBridge: Boolean;
begin
  Result := FindResource(HInstance, cTsBridgeResource, RT_RCDATA) <> 0;
end;

function EmbeddedBridgePath: string;
begin
  // Per versie (hash) een eigen bestand: meerdere RDCManagerX-versies naast elkaar storen elkaar niet.
  Result := TPath.Combine(TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RDCManagerX'), 'bin'), Format('tsbridge-%s.dll', [Copy(cTsBridgeSha256, 1, 16)]));
end;

function FileHasBridgeHash(const aPath: string): Boolean;
var
  lStream: TFileStream;
begin
  Result := False;
  if not TFile.Exists(aPath) then
    Exit;
  try
    lStream := TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
    try
      Result := SameText(LowerCase(THashSHA2.GetHashString(lStream, THashSHA2.TSHA2Version.SHA256)), cTsBridgeSha256);
    finally
      lStream.Free;
    end;
  except
    Result := False;
  end;
end;

procedure CleanupOldBridges(const aKeep: string);
var
  lFile: string;
begin
  // Uitgepakte DLL's van eerdere versies: weg (lukt niet als een andere RDCManagerX hem gebruikt; dan later).
  for lFile in TDirectory.GetFiles(ExtractFilePath(aKeep), 'tsbridge-*') do
    if not SameText(lFile, aKeep) then
      try
        TFile.Delete(lFile);
      except
        // in gebruik
      end;
end;

function ExtractEmbeddedBridge(const aPath: string; out aError: string): Boolean;
var
  lBuffer: TBytes;
  lCount: Integer;
  lInput: TZDecompressionStream;
  lOutput: TFileStream;
  lResource: TResourceStream;
  lTemp: string;
begin
  aError := '';
  Result := FileHasBridgeHash(aPath);
  if Result then
    Exit;
  try
    TDirectory.CreateDirectory(ExtractFilePath(aPath));
    lTemp := aPath + '.' + TGUID.NewGuid.ToString + '.tmp';
    lResource := TResourceStream.Create(HInstance, cTsBridgeResource, RT_RCDATA);
    try
      lInput := TZDecompressionStream.Create(lResource, 15 + 16); // gzip
      try
        lOutput := TFileStream.Create(lTemp, fmCreate or fmShareExclusive);
        try
          SetLength(lBuffer, 1024 * 1024);
          repeat
            lCount := lInput.Read(lBuffer[0], Length(lBuffer));
            if lCount > 0 then
              lOutput.WriteBuffer(lBuffer[0], lCount);
          until lCount <= 0;
        finally
          lOutput.Free;
        end;
      finally
        lInput.Free;
      end;
    finally
      lResource.Free;
    end;
    if not MoveFileEx(PChar(lTemp), PChar(aPath), MOVEFILE_REPLACE_EXISTING) then
    begin
      aError := SysErrorMessage(GetLastError);
      DeleteFile(lTemp);
      // Een andere RDCManagerX kan hem net hebben uitgepakt (en geladen): dan is dat bestand goed.
      Exit(FileHasBridgeHash(aPath));
    end;
    CleanupOldBridges(aPath);
    Result := True;
  except
    on E: Exception do
    begin
      aError := E.Message;
      if (lTemp <> '') and TFile.Exists(lTemp) then
        DeleteFile(lTemp);
      Result := False;
    end;
  end;
end;

class procedure TRdcTsBridge.EnsureLoaded;
var
  lEmbedded: Boolean;
  lError: string;
  lFile: THandle;
  lHash: string;
  lModule: HMODULE;
  lPath: string;

  function Bind(const aName: string): Pointer;
  begin
    Result := GetProcAddress(lModule, PChar(aName));
    if Result = nil then
      raise ETsBridge.CreateFmt(_('%s mist de functie %s (verkeerde versie?).'), [cTsBridgeDll, aName]);
  end;

begin
  TMonitor.Enter(FLock);
  try
    if FLoaded then
      Exit;
    FLoaded := True;
    lEmbedded := HasEmbeddedBridge;
    if lEmbedded then
    begin
      // Ingebouwd in de exe: uitpakken naar het profiel (alleen als het daar nog niet goed staat).
      lPath := EmbeddedBridgePath;
      if not ExtractEmbeddedBridge(lPath, lError) then
      begin
        FLoadError := Format(_('De ingebouwde %s kon niet worden uitgepakt naar %s: %s'), [cTsBridgeDll, ExtractFilePath(lPath), lError]);
        Exit;
      end;
    end
    else
    begin
      // Zonder resource (testproject): alleen naast de exe zoeken (geen DLL uit de zoekvolgorde laden).
      lPath := ExtractFilePath(ParamStr(0)) + cTsBridgeDll;
      if not FileExists(lPath) then
      begin
        FLoadError := Format(_('%s staat niet naast RDCManagerX.exe; verbinden via Tailscale is niet beschikbaar.'), [cTsBridgeDll]);
        Exit;
      end;
    end;
    // Integriteit: alleen de DLL die bij deze build hoort (controlesom in de exe). Het bestand blijft geopend zonder
    // schrijf-/verwijderdeling tot hij geladen is, zodat hij tussen controle en laden niet vervangen kan worden.
    lFile := CreateFile(PChar(lPath), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if lFile = INVALID_HANDLE_VALUE then
    begin
      FLoadError := Format(_('%s kon niet worden geopend: %s'), [cTsBridgeDll, SysErrorMessage(GetLastError)]);
      Exit;
    end;
    try
      lHash := FileSha256(lFile);
      if (cTsBridgeSha256 = '') or not SameText(lHash, cTsBridgeSha256) then
      begin
        if lEmbedded then
          FLoadError := Format(_('De uitgepakte %s is tussentijds gewijzigd (controlesom klopt niet); verbinden via Tailscale is uitgeschakeld. Start RDCManagerX opnieuw.'), [cTsBridgeDll])
        else
          FLoadError := Format(_('%s hoort niet bij deze versie van RDCManagerX (controlesom klopt niet); verbinden via Tailscale is uitgeschakeld. Zet de tsbridge.dll van dezelfde build ernaast.'), [cTsBridgeDll]);
        TRdcLog.Write(Format('tsbridge.dll geweigerd: SHA-256 %s, verwacht %s', [lHash, cTsBridgeSha256]));
        Exit;
      end;
      // The DLL itself by full path (hash-pinned above); its imports (kernel32 and the UCRT API sets) from System32
      // only. LOAD_WITH_ALTERED_SEARCH_PATH would look in the DLL's own folder first, which the user can write to,
      // so a planted dependency there would load outside the hash pin.
      lModule := LoadLibraryEx(PChar(lPath), 0, LOAD_LIBRARY_SEARCH_SYSTEM32);
    finally
      CloseHandle(lFile);
    end;
    if lModule = 0 then
    begin
      FLoadError := Format(_('%s kon niet worden geladen: %s'), [cTsBridgeDll, SysErrorMessage(GetLastError)]);
      Exit;
    end;
    try
      @GTsBridgeVersion := Bind('TsBridgeVersion');
      @GTsNetCreate := Bind('TsNetCreate');
      @GTsNetUp := Bind('TsNetUp');
      @GTsNetGetStatus := Bind('TsNetGetStatus');
      @GTsNetAddForward := Bind('TsNetAddForward');
      @GTsNetRemoveForward := Bind('TsNetRemoveForward');
      @GTsNetCheckTarget := Bind('TsNetCheckTarget');
      @GTsNetClose := Bind('TsNetClose');
      @GTsLastError := Bind('TsLastError');
      FAvailable := True;
      TRdcLog.Write('tsbridge.dll geladen, versie ' + Version);
    except
      on E: ETsBridge do
        FLoadError := E.Message;
    end;
    // Nooit FreeLibrary: de Go-runtime kan niet veilig ontladen worden.
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TRdcTsBridge.Available: Boolean;
begin
  EnsureLoaded;
  Result := FAvailable;
end;

class function TRdcTsBridge.LoadError: string;
begin
  EnsureLoaded;
  Result := FLoadError;
end;

class function TRdcTsBridge.Version: string;
begin
  if not FAvailable then
    Exit('');
  Result := ReadText(
    function(aBuf: PAnsiChar; aBufLen: Integer): Integer
    begin
      Result := GTsBridgeVersion(aBuf, aBufLen);
    end);
end;

class function TRdcTsBridge.CodeText(aCode: Integer): string;
begin
  case aCode of
    cTsOk: Result := _('gelukt');
    cTsInvalidHandle: Result := _('onbekend netwerk');
    cTsInvalidArgs: Result := _('ongeldige instellingen');
    cTsTimeout: Result := _('time-out');
    cTsClosed: Result := _('geannuleerd of gesloten');
    cTsNotFound: Result := _('niet gevonden');
    cTsOffline: Result := _('apparaat is offline');
  else
    Result := Format(_('fout %d'), [aCode]);
  end;
end;

{ TRdcTailnet }

constructor TRdcTailnet.Create(const aConfig: TRdcTailnetConfig);
var
  lJson: string;
  lUtf8: TBytes;
  lError: string;
begin
  inherited Create;
  if not TRdcTsBridge.Available then
    raise ETsBridge.Create(TRdcTsBridge.LoadError);
  lJson := aConfig.ToJson;
  lUtf8 := TEncoding.UTF8.GetBytes(lJson + #0);
  try
    FHandle := GTsNetCreate(PAnsiChar(@lUtf8[0]));
  finally
    // De JSON bevat de auth key en state-sleutel: overschrijven.
    WipeString(lJson);
    FillChar(lUtf8[0], Length(lUtf8), 0);
  end;
  if FHandle <= 0 then
  begin
    lError := ReadText(
      function(aBuf: PAnsiChar; aBufLen: Integer): Integer
      begin
        Result := GTsLastError(0, aBuf, aBufLen);
      end);
    FHandle := 0;
    raise ETsBridge.CreateFmt(_('Tailscale-netwerk kon niet worden aangemaakt: %s'), [lError]);
  end;
end;

destructor TRdcTailnet.Destroy;
begin
  Close;
  inherited;
end;

function TRdcTailnet.LastErrorText: string;
var
  lHandle: Integer;
begin
  lHandle := FHandle;
  if lHandle <= 0 then
    Exit('');
  Result := ReadText(
    function(aBuf: PAnsiChar; aBufLen: Integer): Integer
    begin
      Result := GTsLastError(lHandle, aBuf, aBufLen);
    end);
end;

function TRdcTailnet.Up(aTimeoutMs: Integer; out aError: string): Integer;
begin
  aError := '';
  if FHandle <= 0 then
    Exit(cTsInvalidHandle);
  Result := GTsNetUp(FHandle, aTimeoutMs);
  if Result <> cTsOk then
  begin
    aError := LastErrorText;
    if aError = '' then
      aError := TRdcTsBridge.CodeText(Result);
  end;
end;

function TRdcTailnet.Status: TRdcTailnetStatus;
var
  lHandle: Integer;
begin
  lHandle := FHandle;
  if lHandle <= 0 then
  begin
    Result := Default(TRdcTailnetStatus);
    Result.State := 'Closed';
    Exit;
  end;
  Result := TRdcTailnetStatus.FromJson(ReadText(
    function(aBuf: PAnsiChar; aBufLen: Integer): Integer
    begin
      Result := GTsNetGetStatus(lHandle, aBuf, aBufLen);
    end));
end;

function TRdcTailnet.AddForward(const aLocalAddress, aTarget: string): Integer;
var
  lLocal: UTF8String;
  lTarget: UTF8String;
begin
  if FHandle <= 0 then
    raise ETsBridge.Create(_('Tailscale-netwerk is gesloten.'));
  lLocal := UTF8String(aLocalAddress);
  lTarget := UTF8String(aTarget);
  Result := GTsNetAddForward(FHandle, PAnsiChar(lLocal), PAnsiChar(lTarget));
  if Result <= 0 then
    raise ETsBridge.CreateFmt(_('Doorsturen naar %s via Tailscale is mislukt: %s'), [aTarget, IfThen(LastErrorText <> '', LastErrorText, TRdcTsBridge.CodeText(Result))]);
end;

procedure TRdcTailnet.RemoveForward(aLocalPort: Integer);
begin
  if FHandle > 0 then
    GTsNetRemoveForward(FHandle, aLocalPort);
end;

function TRdcTailnet.CheckTarget(const aTarget: string; out aError: string): Boolean;
var
  lCode: Integer;
  lTarget: UTF8String;
begin
  aError := '';
  if FHandle <= 0 then
  begin
    aError := _('Tailscale-netwerk is gesloten.');
    Exit(False);
  end;
  lTarget := UTF8String(aTarget);
  lCode := GTsNetCheckTarget(FHandle, PAnsiChar(lTarget));
  Result := lCode = cTsOk;
  if not Result then
  begin
    aError := LastErrorText;
    if aError = '' then
      aError := TRdcTsBridge.CodeText(lCode);
  end;
end;

procedure TRdcTailnet.Close;
var
  lHandle: Integer;
begin
  lHandle := AtomicExchange(FHandle, 0);
  if lHandle > 0 then
    GTsNetClose(lHandle);
end;

{ TRdcTailnetManager.TEntry }

constructor TRdcTailnetManager.TEntry.Create;
begin
  inherited Create;
  Waiters := TList<TRdcTailnetReadyProc>.Create;
end;

destructor TRdcTailnetManager.TEntry.Destroy;
begin
  Waiters.Free;
  inherited;
end;

{ TRdcTailnetManager.TAlive }

function TRdcTailnetManager.TAlive.GetAlive: Boolean;
begin
  Result := AtomicCmpExchange(FAlive, 0, 0) <> 0;
end;

procedure TRdcTailnetManager.TAlive.SetAlive(aValue: Boolean);
begin
  AtomicExchange(FAlive, Ord(aValue));
end;

{ TRdcTailnetManager }

constructor TRdcTailnetManager.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FUpTimeoutMs := cTsDefaultUpTimeoutMs;
end;

destructor TRdcTailnetManager.Destroy;
begin
  CloseAll;
  FAlive.Alive := False;
  FEntries.Free;
  inherited;
end;

procedure TRdcTailnetManager.Acquire(var aConfig: TRdcTailnetConfig; const aOnReady: TRdcTailnetReadyProc);
var
  lEntry: TEntry;
  lAlive: IAlive;
  lError: string;
  lNet: TRdcTailnet;
  lTimeout: Integer;
begin
  try
    if FEntries.TryGetValue(aConfig.Id, lEntry) then
    begin
      Inc(lEntry.RefCount);
      case lEntry.State of
        esStarting:
          lEntry.Waiters.Add(aOnReady);
        esRunning:
          TThread.ForceQueue(nil,
            procedure
            begin
              aOnReady(True, '');
            end);
        esFailed:
          begin
            lError := lEntry.Error;
            TThread.ForceQueue(nil,
              procedure
              begin
                aOnReady(False, lError);
              end);
          end;
      end;
      Exit;
    end;

    lEntry := TEntry.Create;
    lEntry.RefCount := 1;
    FEntries.Add(aConfig.Id, lEntry);
    lAlive := FAlive;
    try
      lNet := TRdcTailnet.Create(aConfig);
    except
      on E: Exception do
      begin
        lEntry.State := esFailed;
        lEntry.Error := E.Message;
        lError := E.Message;
        TThread.ForceQueue(nil,
          procedure
          begin
            aOnReady(False, lError);
          end);
        Exit;
      end;
    end;
    lEntry.Net := lNet;
    lEntry.State := esStarting;
    lEntry.Waiters.Add(aOnReady);
    TRdcLog.Write(Format('Tailscale-netwerk %s starten', [aConfig.Id]));
    lTimeout := FUpTimeoutMs;
    // Up blokkeert (tot de time-out, of tot Close bij annuleren): op de achtergrond.
    TThread.CreateAnonymousThread(
      procedure
      var
        lCode: Integer;
        lUpError: string;
      begin
        lCode := lNet.Up(lTimeout, lUpError);
        TThread.Queue(nil,
          procedure
          begin
            if lAlive.Alive then
              StartFinished(lEntry, lCode, lUpError);
          end);
      end).Start;
  finally
    aConfig.Wipe;
  end;
end;

procedure TRdcTailnetManager.StartFinished(aEntry: TEntry; aCode: Integer; const aError: string);
var
  lId: string;
  lPair: TPair<string, TEntry>;
  lWaiter: TRdcTailnetReadyProc;
  lWaiters: TArray<TRdcTailnetReadyProc>;
begin
  // Laatste Release kwam tijdens het starten: de Up-thread is nu klaar, dus nu pas vrijgeven.
  if aEntry.Orphaned then
  begin
    if aEntry.Net <> nil then
      CloseInBackground(aEntry.Net);
    aEntry.Free;
    Exit;
  end;
  lId := '';
  for lPair in FEntries do
    if lPair.Value = aEntry then
      lId := lPair.Key;
  if aCode = cTsOk then
    aEntry.State := esRunning
  else
  begin
    aEntry.State := esFailed;
    aEntry.Error := aError;
  end;
  TRdcLog.Write(Format('Tailscale-netwerk %s: %s', [lId, IfThen(aCode = cTsOk, 'verbonden', 'starten mislukt: ' + aError)]));
  lWaiters := aEntry.Waiters.ToArray;
  aEntry.Waiters.Clear;
  for lWaiter in lWaiters do
    lWaiter(aCode = cTsOk, aError);
end;

procedure TRdcTailnetManager.CloseInBackground(aNet: TRdcTailnet);
begin
  // Close kan even duren (afmelden bij de control server bij ephemeral): niet op de hoofdthread.
  TThread.CreateAnonymousThread(
    procedure
    begin
      aNet.Free;
    end).Start;
end;

procedure TRdcTailnetManager.Release(const aId: string);
var
  lEntry: TEntry;
  lNet: TRdcTailnet;
begin
  if not FEntries.TryGetValue(aId, lEntry) then
    Exit;
  Dec(lEntry.RefCount);
  if lEntry.RefCount > 0 then
    Exit;
  TRdcLog.Write(Format('Tailscale-netwerk %s sluiten', [aId]));
  FEntries.Remove(aId);
  if lEntry.State = esStarting then
  begin
    // De Up-thread gebruikt Net nog: alleen de handle sluiten (breekt Up af); StartFinished ruimt op.
    lEntry.Orphaned := True;
    lEntry.Net.Close;
    Exit;
  end;
  lNet := lEntry.Net;
  lEntry.Net := nil;
  lEntry.Free;
  if lNet <> nil then
    CloseInBackground(lNet);
end;

function TRdcTailnetManager.IsRunning(const aId: string): Boolean;
var
  lEntry: TEntry;
begin
  Result := FEntries.TryGetValue(aId, lEntry) and (lEntry.State = esRunning);
end;

function TRdcTailnetManager.RefCount(const aId: string): Integer;
var
  lEntry: TEntry;
begin
  if FEntries.TryGetValue(aId, lEntry) then
    Result := lEntry.RefCount
  else
    Result := 0;
end;

function TRdcTailnetManager.TryStatus(const aId: string; out aStatus: TRdcTailnetStatus): Boolean;
var
  lEntry: TEntry;
begin
  Result := FEntries.TryGetValue(aId, lEntry) and (lEntry.Net <> nil);
  if Result then
    aStatus := lEntry.Net.Status
  else
    aStatus := Default(TRdcTailnetStatus);
end;

function TRdcTailnetManager.AddForward(const aId, aLocalAddress, aTarget: string): Integer;
var
  lEntry: TEntry;
begin
  if not FEntries.TryGetValue(aId, lEntry) or (lEntry.State <> esRunning) or (lEntry.Net = nil) then
    raise ETsBridge.Create(_('Tailscale-netwerk is niet verbonden.'));
  Result := lEntry.Net.AddForward(aLocalAddress, aTarget);
end;

procedure TRdcTailnetManager.RemoveForward(const aId: string; aLocalPort: Integer);
var
  lEntry: TEntry;
begin
  if FEntries.TryGetValue(aId, lEntry) and (lEntry.Net <> nil) then
    lEntry.Net.RemoveForward(aLocalPort);
end;

function TRdcTailnetManager.CheckTarget(const aId, aTarget: string; out aError: string): Boolean;
var
  lEntry: TEntry;
begin
  if not FEntries.TryGetValue(aId, lEntry) or (lEntry.State <> esRunning) or (lEntry.Net = nil) then
  begin
    aError := _('Tailscale-netwerk is niet verbonden.');
    Exit(False);
  end;
  Result := lEntry.Net.CheckTarget(aTarget, aError);
end;

procedure TRdcTailnetManager.CloseAll;
var
  lEntry: TEntry;
begin
  // Bij afsluiten: synchroon sluiten (ephemeral nodes melden zich dan netjes af). Een node die nog aan het
  // starten is wordt alleen gesloten (Up breekt af); het object blijft dan achter, want de Up-thread gebruikt het nog.
  for lEntry in FEntries.Values do
    if lEntry.State = esStarting then
    begin
      lEntry.Orphaned := True;
      lEntry.Net.Close;
    end
    else
    begin
      lEntry.Net.Free;
      lEntry.Free;
    end;
  FEntries.Clear;
end;

end.
