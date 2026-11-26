unit RdcmX.Ping;

{
  Bereikbaarheid van servers op de achtergrond (instelling "ping" op de tab Route; erft per bestand/groep).

  - Controle per server: eerst ICMP echo (IcmpSendEcho, geen beheerrechten nodig). Geen antwoord: een korte
    TCP-verbinding met de RDP-poort, omdat Windows ICMP vaak standaard blokkeert terwijl RDP wel bereikbaar is.
    Online = een van beide lukt.
  - Alleen IPv4 (de hostnaam wordt via getaddrinfo opgelost; het eerste IPv4-adres).
  - Identiteit: is een server op naam bereikbaar, dan wordt via NetBIOS (node status, UDP 137, zoals "nbtstat -A")
    gevraagd welke computer er echt op dat adres zit. Een andere naam = verouderd DNS-record (adres via DHCP
    inmiddels aan een ander apparaat gegeven): Mismatch, met de echte naam. Geen NetBIOS-antwoord = niet te
    controleren (geen mismatch). Servers die op IP-adres zijn ingevoerd worden niet gecontroleerd.
  - TRdcPinger: een thread die elke IntervalMs alle doelen controleert (parallel, via de threadpool) en de resultaten
    in één keer via de message queue teruggeeft (OnResults, op de hoofdthread). Doelen kunnen altijd worden vervangen
    (SetTargets). Bij Free worden nog niet afgeleverde resultaten weggegooid.
}

interface

uses
  Winapi.Windows,
  System.Classes, System.Generics.Collections, System.SyncObjs, System.SysUtils;

type
  TRdcPingState = (psUnknown, psOnline, psOffline, psWrongHost);

  TRdcPingTarget = record
    Host: string;
    Port: Integer;
    /// <summary>Verwachte computernaam (NetBIOS: eerste deel van de hostnaam, hoofdletters, max. 15 tekens); leeg
    /// bij een IP-adres (dan geen identiteitscontrole).</summary>
    function ExpectedName: string;
    /// <summary>Sleutel voor resultaten: host (kleine letters) + ':' + poort.</summary>
    function Key: string;
    class function Create(const aHost: string; aPort: Integer): TRdcPingTarget; static;
  end;

  TRdcPingResult = record
    Key: string;
    Online: Boolean;
    /// <summary>Antwoordtijd in ms (ICMP of TCP-verbinding); -1 als offline.</summary>
    RoundTripMs: Integer;
    /// <summary>Opgelost IPv4-adres (tekst), als de naam kon worden opgelost.</summary>
    Address: string;
    /// <summary>Er antwoordt een andere computer dan verwacht (ActualName via NetBIOS).</summary>
    Mismatch: Boolean;
    ActualName: string;
  end;

  TRdcPingResultsEvent = procedure(const aResults: TArray<TRdcPingResult>) of object;

  TRdcPinger = class(TThread)
  private
    FLock: TCriticalSection;
    FWake: TEvent;
    FTargets: TArray<TRdcPingTarget>;
    FIntervalMs: Integer;
    FOnResults: TRdcPingResultsEvent;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(const aOnResults: TRdcPingResultsEvent);
    destructor Destroy; override;
    /// <summary>Nieuwe lijst doelen (vervangt de vorige); start meteen een nieuwe ronde.</summary>
    procedure SetTargets(const aTargets: TArray<TRdcPingTarget>);
    /// <summary>Wachttijd tussen twee rondes; een wijziging geldt meteen (de huidige wachttijd wordt afgebroken).</summary>
    procedure SetInterval(aIntervalMs: Integer);
    property IntervalMs: Integer read FIntervalMs;
  end;

/// <summary>Is aHost bereikbaar? ICMP, anders TCP naar aPort. Blokkerend (max. ongeveer 2 x aTimeoutMs).
/// aAddress: het opgeloste IPv4-adres (0 als de naam niet kon worden opgelost).</summary>
function RdcCheckHost(const aHost: string; aPort, aTimeoutMs: Integer; out aRoundTripMs: Integer): Boolean; overload;
function RdcCheckHost(const aHost: string; aPort, aTimeoutMs: Integer; out aRoundTripMs: Integer; out aAddress: Cardinal): Boolean; overload;
/// <summary>Computernaam op aAddress via NetBIOS (node status); leeg als er geen antwoord komt.</summary>
function RdcNetBiosName(aAddress: Cardinal; aTimeoutMs: Integer): string;
/// <summary>IPv4-adres als tekst (a.b.c.d).</summary>
function RdcAddressText(aAddress: Cardinal): string;
/// <summary>Is aName een IPv4-adres?</summary>
function RdcIsIPv4(const aName: string): Boolean;

implementation

uses
  Winapi.Winsock2,
  System.Threading;

type
  TIpOptionInformation = record
    Ttl: Byte;
    Tos: Byte;
    Flags: Byte;
    OptionsSize: Byte;
    OptionsData: Pointer;
  end;

  TIcmpEchoReply = record
    Address: Cardinal;
    Status: Cardinal;
    RoundTripTime: Cardinal;
    DataSize: Word;
    Reserved: Word;
    Data: Pointer;
    Options: TIpOptionInformation;
  end;
  PIcmpEchoReply = ^TIcmpEchoReply;

// "delayed": resolved at first use, after RdcmX.DllSearch restricted DLL loading to System32 (DLL planting).
{$WARN SYMBOL_PLATFORM OFF}
function IcmpCreateFile: THandle; stdcall; external 'iphlpapi.dll' name 'IcmpCreateFile' delayed;
function IcmpCloseHandle(aIcmpHandle: THandle): BOOL; stdcall; external 'iphlpapi.dll' name 'IcmpCloseHandle' delayed;
function IcmpSendEcho(aIcmpHandle: THandle; aDestinationAddress: Cardinal; aRequestData: Pointer; aRequestSize: Word; aRequestOptions: Pointer; aReplyBuffer: Pointer; aReplySize: DWORD; aTimeout: DWORD): DWORD; stdcall; external 'iphlpapi.dll' name 'IcmpSendEcho' delayed;
{$WARN SYMBOL_PLATFORM ON}

var
  GWinsockReady: Boolean;

{ TRdcPingTarget }

class function TRdcPingTarget.Create(const aHost: string; aPort: Integer): TRdcPingTarget;
begin
  Result.Host := Trim(aHost);
  Result.Port := aPort;
end;

function TRdcPingTarget.Key: string;
begin
  Result := LowerCase(Host) + ':' + IntToStr(Port);
end;

function TRdcPingTarget.ExpectedName: string;
begin
  if (Host = '') or RdcIsIPv4(Host) or (Pos(':', Host) > 0) then
    Exit('');
  Result := UpperCase(Host);
  if Pos('.', Result) > 0 then
    Result := Copy(Result, 1, Pos('.', Result) - 1);
  Result := Copy(Result, 1, 15); // NetBIOS-namen zijn maximaal 15 tekens
end;

function RdcIsIPv4(const aName: string): Boolean;
var
  lPart: string;
  lParts: TArray<string>;
  lValue: Integer;
begin
  lParts := aName.Split(['.']);
  Result := Length(lParts) = 4;
  if Result then
    for lPart in lParts do
      if not TryStrToInt(lPart, lValue) or (lValue < 0) or (lValue > 255) then
        Exit(False);
end;

function RdcAddressText(aAddress: Cardinal): string;
begin
  // In het geheugen staat het adres in netwerkvolgorde: eerste byte = eerste getal.
  Result := Format('%d.%d.%d.%d', [aAddress and $FF, (aAddress shr 8) and $FF, (aAddress shr 16) and $FF, (aAddress shr 24) and $FF]);
end;

{ Controle }

function ResolveIPv4(const aHost: string; out aAddress: Cardinal): Boolean;
var
  lHints: addrinfoW;
  lInfo: PaddrinfoW;
begin
  Result := False;
  aAddress := 0;
  if not GWinsockReady then
    Exit;
  FillChar(lHints, SizeOf(lHints), 0);
  lHints.ai_family := AF_INET;
  lHints.ai_socktype := SOCK_STREAM;
  if GetAddrInfoW(PChar(aHost), nil, lHints, lInfo) <> 0 then
    Exit;
  try
    if (lInfo <> nil) and (lInfo.ai_addr <> nil) then
    begin
      aAddress := PSockAddrIn(lInfo.ai_addr).sin_addr.S_addr;
      Result := True;
    end;
  finally
    FreeAddrInfoW(lInfo^);
  end;
end;

function IcmpEcho(aAddress: Cardinal; aTimeoutMs: Integer; out aRoundTripMs: Integer): Boolean;
var
  lData: array[0..31] of Byte;
  lHandle: THandle;
  lReply: array[0..SizeOf(TIcmpEchoReply) + 64 - 1] of Byte;
begin
  Result := False;
  aRoundTripMs := -1;
  lHandle := IcmpCreateFile;
  if lHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    FillChar(lData, SizeOf(lData), Ord('R'));
    if IcmpSendEcho(lHandle, aAddress, @lData, SizeOf(lData), nil, @lReply, SizeOf(lReply), DWORD(aTimeoutMs)) > 0 then
    begin
      Result := PIcmpEchoReply(@lReply).Status = 0; // IP_SUCCESS
      if Result then
        aRoundTripMs := Integer(PIcmpEchoReply(@lReply).RoundTripTime);
    end;
  finally
    IcmpCloseHandle(lHandle);
  end;
end;

function TcpConnect(aAddress: Cardinal; aPort, aTimeoutMs: Integer; out aRoundTripMs: Integer): Boolean;
var
  lAddr: TSockAddrIn;
  lError: TFDSet;
  lMode: u_long;
  lSocket: TSocket;
  lStart: UInt64;
  lTimeout: TTimeVal;
  lWrite: TFDSet;
begin
  Result := False;
  aRoundTripMs := -1;
  if (aPort <= 0) or (aPort > 65535) then
    Exit;
  lSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if lSocket = INVALID_SOCKET then
    Exit;
  try
    lMode := 1;
    ioctlsocket(lSocket, Longint(FIONBIO), lMode); // niet-blokkerend: verbinden met time-out via select
    FillChar(lAddr, SizeOf(lAddr), 0);
    lAddr.sin_family := AF_INET;
    lAddr.sin_port := htons(aPort);
    lAddr.sin_addr.S_addr := aAddress;
    lStart := GetTickCount64;
    if connect(lSocket, PSockAddr(@lAddr)^, SizeOf(lAddr)) = 0 then
      Result := True
    else if WSAGetLastError = WSAEWOULDBLOCK then
    begin
      lWrite.fd_count := 1;
      lWrite.fd_array[0] := lSocket;
      lError.fd_count := 1;
      lError.fd_array[0] := lSocket;
      lTimeout.tv_sec := aTimeoutMs div 1000;
      lTimeout.tv_usec := (aTimeoutMs mod 1000) * 1000;
      // Gelukt = schrijfbaar en niet in de foutset.
      Result := (select(0, nil, @lWrite, @lError, @lTimeout) > 0) and (lWrite.fd_count = 1) and (lError.fd_count = 0);
    end;
    if Result then
      aRoundTripMs := Integer(GetTickCount64 - lStart);
  finally
    closesocket(lSocket);
  end;
end;

function RdcCheckHost(const aHost: string; aPort, aTimeoutMs: Integer; out aRoundTripMs: Integer; out aAddress: Cardinal): Boolean;
begin
  aRoundTripMs := -1;
  aAddress := 0;
  if (aHost = '') or not ResolveIPv4(aHost, aAddress) then
    Exit(False);
  Result := IcmpEcho(aAddress, aTimeoutMs, aRoundTripMs) or TcpConnect(aAddress, aPort, aTimeoutMs, aRoundTripMs);
end;

function RdcCheckHost(const aHost: string; aPort, aTimeoutMs: Integer; out aRoundTripMs: Integer): Boolean;
var
  lAddress: Cardinal;
begin
  Result := RdcCheckHost(aHost, aPort, aTimeoutMs, aRoundTripMs, lAddress);
end;

function RdcNetBiosName(aAddress: Cardinal; aTimeoutMs: Integer): string;
const
  cNbStat = $21;
var
  lAddr: TSockAddrIn;
  lCount: Integer;
  lEntry: Integer;
  lFlags: Word;
  lFrom: TSockAddrIn;
  lFromLen: Integer;
  lIndex: Integer;
  lMode: u_long;
  lName: string;
  lNameCount: Integer;
  lOffset: Integer;
  lRead: TFDSet;
  lReply: array[0..1023] of Byte;
  lRequest: array[0..49] of Byte;
  lSocket: TSocket;
  lTimeout: TTimeVal;
begin
  // NetBIOS node status request (RFC 1002, 4.2.17) naar UDP 137: naam "*" (gecodeerd als CK + 30 x A).
  Result := '';
  if not GWinsockReady then
    Exit;
  FillChar(lRequest, SizeOf(lRequest), 0);
  lRequest[0] := $52;  // transactie-id
  lRequest[1] := $44;
  lRequest[5] := 1;    // QDCOUNT = 1
  lRequest[12] := 32;  // lengte van de gecodeerde naam
  lRequest[13] := Ord('C');
  lRequest[14] := Ord('K');
  for lIndex := 15 to 44 do
    lRequest[lIndex] := Ord('A');
  // lRequest[45] = 0 (einde naam)
  lRequest[47] := cNbStat; // QTYPE = NBSTAT
  lRequest[49] := 1;       // QCLASS = IN
  lSocket := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if lSocket = INVALID_SOCKET then
    Exit;
  try
    lMode := 1;
    ioctlsocket(lSocket, Longint(FIONBIO), lMode);
    FillChar(lAddr, SizeOf(lAddr), 0);
    lAddr.sin_family := AF_INET;
    lAddr.sin_port := htons(137);
    lAddr.sin_addr.S_addr := aAddress;
    if sendto(lSocket, lRequest, SizeOf(lRequest), 0, PSockAddr(@lAddr), SizeOf(lAddr)) <> SizeOf(lRequest) then
      Exit;
    lRead.fd_count := 1;
    lRead.fd_array[0] := lSocket;
    lTimeout.tv_sec := aTimeoutMs div 1000;
    lTimeout.tv_usec := (aTimeoutMs mod 1000) * 1000;
    if select(0, @lRead, nil, nil, @lTimeout) <= 0 then
      Exit;
    lFromLen := SizeOf(lFrom);
    lCount := recvfrom(lSocket, lReply, SizeOf(lReply), 0, PSockAddr(@lFrom)^, lFromLen);
    if lCount < 57 then
      Exit;
    // Antwoord: header (12), naam (lengte + 32 + 0), type (2), class (2), TTL (4), RDLENGTH (2), aantal namen (1),
    // per naam 18 bytes: 15 tekens + achtervoegsel + vlaggen (bit $8000 = groepsnaam).
    lOffset := 12;
    if lReply[lOffset] <> 32 then
      Exit;
    Inc(lOffset, 1 + 32 + 1 + 2 + 2 + 4 + 2);
    lNameCount := lReply[lOffset];
    Inc(lOffset);
    for lEntry := 0 to lNameCount - 1 do
    begin
      if lOffset + 18 > lCount then
        Break;
      lFlags := (Word(lReply[lOffset + 16]) shl 8) or lReply[lOffset + 17];
      // Achtervoegsel $00, unieke naam = de computernaam (de werkstationservice).
      if (lReply[lOffset + 15] = 0) and (lFlags and $8000 = 0) then
      begin
        SetString(lName, nil, 15);
        for lIndex := 0 to 14 do
          lName[lIndex + 1] := Char(lReply[lOffset + lIndex]);
        Exit(Trim(lName));
      end;
      Inc(lOffset, 18);
    end;
  finally
    closesocket(lSocket);
  end;
end;

{ TRdcPinger }

constructor TRdcPinger.Create(const aOnResults: TRdcPingResultsEvent);
begin
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FIntervalMs := 30000;
  FOnResults := aOnResults;
  inherited Create(False);
end;

destructor TRdcPinger.Destroy;
begin
  Terminate;
  WaitFor;
  // Nog niet afgeleverde resultaten niet meer afleveren (het hoofdvenster kan al weg zijn).
  TThread.RemoveQueuedEvents(Self);
  FWake.Free;
  FLock.Free;
  inherited;
end;

procedure TRdcPinger.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TRdcPinger.SetTargets(const aTargets: TArray<TRdcPingTarget>);
begin
  FLock.Enter;
  try
    FTargets := Copy(aTargets);
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

procedure TRdcPinger.SetInterval(aIntervalMs: Integer);
begin
  if aIntervalMs = FIntervalMs then
    Exit;
  AtomicExchange(FIntervalMs, aIntervalMs);
  FWake.SetEvent;
end;

procedure TRdcPinger.Execute;
var
  lResults: TArray<TRdcPingResult>;
  lTargets: TArray<TRdcPingTarget>;
begin
  NameThreadForDebugging('RdcmX.Ping');
  while not Terminated do
  begin
    FLock.Enter;
    try
      lTargets := Copy(FTargets);
    finally
      FLock.Leave;
    end;
    if Length(lTargets) > 0 then
    begin
      lResults := nil; // nieuwe array: de vorige is mogelijk nog onderweg naar de hoofdthread
      SetLength(lResults, Length(lTargets));
      // Parallel: een offline server kost tot ~2 s; achter elkaar zou een ronde met veel servers te lang duren.
      TParallel.For(0, High(lTargets),
        procedure(aIndex: Integer)
        var
          lAddress: Cardinal;
          lActual: string;
          lExpected: string;
          lRoundTrip: Integer;
        begin
          if Terminated then
            Exit;
          lResults[aIndex].Key := lTargets[aIndex].Key;
          lResults[aIndex].Online := RdcCheckHost(lTargets[aIndex].Host, lTargets[aIndex].Port, 1000, lRoundTrip, lAddress);
          lResults[aIndex].RoundTripMs := lRoundTrip;
          if lAddress <> 0 then
            lResults[aIndex].Address := RdcAddressText(lAddress);
          // Bereikbaar op naam: is het ook echt die computer? (verouderd DNS-record)
          lExpected := lTargets[aIndex].ExpectedName;
          if lResults[aIndex].Online and (lExpected <> '') then
          begin
            lActual := RdcNetBiosName(lAddress, 1000);
            if (lActual <> '') and not SameText(lActual, lExpected) then
            begin
              lResults[aIndex].Mismatch := True;
              lResults[aIndex].ActualName := lActual;
            end;
          end;
        end);
      if not Terminated and Assigned(FOnResults) then
      begin
        var lDeliver := lResults;
        TThread.Queue(Self,
          procedure
          begin
            FOnResults(lDeliver);
          end);
      end;
    end;
    FWake.WaitFor(Cardinal(FIntervalMs));
  end;
end;

var
  GWsaData: TWSAData;

initialization
  GWinsockReady := WSAStartup($0202, GWsaData) = 0;

finalization
  if GWinsockReady then
    WSACleanup;

end.
