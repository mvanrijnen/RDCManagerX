unit RdcmX.WakeOnLan;

{
  Wake-on-LAN: stuurt een "magic packet" (6x $FF + 16x het MAC-adres, 102 bytes) als UDP-broadcast.

  Beperkingen (netwerk, niet te verhelpen in de client):
  - Een broadcast komt niet voorbij een router. Voor een ander subnet: het directed-broadcastadres van dat
    subnet invullen (bijv. 192.168.10.255) en de router moet directed broadcasts doorlaten.
  - Met 255.255.255.255 kiest Windows de netwerkkaart via de routetabel; bij meerdere netwerkkaarten (VPN!)
    gaat het pakket mogelijk over de verkeerde kaart. Dan ook het subnet-broadcastadres gebruiken.
  - WOL moet in BIOS/UEFI en op de netwerkkaart aan staan; of de machine wakker wordt is niet te controleren.
}

interface

uses
  System.SysUtils;

type
  TRdcMacAddress = array[0..5] of Byte;

  TRdcWakeOnLan = class abstract
  public
    /// <summary>Accepteert 00-11-22-33-44-55, 00:11:22:33:44:55, 0011.2233.4455 en 001122334455.</summary>
    class function TryParseMac(const aText: string; out aMac: TRdcMacAddress): Boolean; static;
    class function FormatMac(const aMac: TRdcMacAddress): string; static;
    class function BuildMagicPacket(const aMac: TRdcMacAddress): TBytes; static;
    /// <summary>Verstuurt het magic packet; exception bij een ongeldig adres of socketfout.</summary>
    class procedure Send(const aMacText, aBroadcast: string; aPort: Integer); static;
  end;

implementation

uses
  Winapi.Winsock2;

class function TRdcWakeOnLan.TryParseMac(const aText: string; out aMac: TRdcMacAddress): Boolean;
var
  lChar: Char;
  lHex: string;
  lIndex: Integer;
begin
  lHex := '';
  for lChar in aText do
    if CharInSet(lChar, ['0'..'9', 'a'..'f', 'A'..'F']) then
      lHex := lHex + lChar
    else if not CharInSet(lChar, ['-', ':', '.', ' ']) then
      Exit(False);
  Result := Length(lHex) = 12;
  if Result then
    for lIndex := 0 to 5 do
      aMac[lIndex] := StrToInt('$' + Copy(lHex, lIndex * 2 + 1, 2));
end;

class function TRdcWakeOnLan.FormatMac(const aMac: TRdcMacAddress): string;
begin
  Result := Format('%.2X-%.2X-%.2X-%.2X-%.2X-%.2X', [aMac[0], aMac[1], aMac[2], aMac[3], aMac[4], aMac[5]]);
end;

class function TRdcWakeOnLan.BuildMagicPacket(const aMac: TRdcMacAddress): TBytes;
var
  lIndex: Integer;
begin
  SetLength(Result, 6 + 16 * 6);
  for lIndex := 0 to 5 do
    Result[lIndex] := $FF;
  for lIndex := 0 to 15 do
    Move(aMac[0], Result[6 + lIndex * 6], 6);
end;

class procedure TRdcWakeOnLan.Send(const aMacText, aBroadcast: string; aPort: Integer);
var
  lAddr: TSockAddrIn;
  lBroadcast: AnsiString;
  lEnable: Integer;
  lMac: TRdcMacAddress;
  lPacket: TBytes;
  lSocket: TSocket;
  lWsaData: TWSAData;
begin
  if not TryParseMac(aMacText, lMac) then
    raise EArgumentException.CreateFmt('Ongeldig MAC-adres "%s".', [aMacText]);
  if (aPort < 1) or (aPort > 65535) then
    raise EArgumentException.CreateFmt('Ongeldige WOL-poort %d.', [aPort]);
  lBroadcast := AnsiString(Trim(aBroadcast));
  FillChar(lAddr, SizeOf(lAddr), 0);
  lAddr.sin_family := AF_INET;
  lAddr.sin_port := htons(Word(aPort));
  lAddr.sin_addr.S_addr := inet_addr(PAnsiChar(lBroadcast));
  if (lAddr.sin_addr.S_addr = INADDR_NONE) and (lBroadcast <> '255.255.255.255') then
    raise EArgumentException.CreateFmt('Ongeldig broadcastadres "%s" (verwacht een IPv4-adres).', [aBroadcast]);

  lPacket := BuildMagicPacket(lMac);
  if WSAStartup($0202, lWsaData) <> 0 then
    RaiseLastOSError;
  try
    lSocket := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if lSocket = INVALID_SOCKET then
      RaiseLastOSError(WSAGetLastError);
    try
      lEnable := 1;
      if setsockopt(lSocket, SOL_SOCKET, SO_BROADCAST, PAnsiChar(@lEnable), SizeOf(lEnable)) = SOCKET_ERROR then
        RaiseLastOSError(WSAGetLastError);
      if sendto(lSocket, lPacket[0], Length(lPacket), 0, PSockAddr(@lAddr), SizeOf(lAddr)) = SOCKET_ERROR then
        RaiseLastOSError(WSAGetLastError);
    finally
      closesocket(lSocket);
    end;
  finally
    WSACleanup;
  end;
end;

end.
