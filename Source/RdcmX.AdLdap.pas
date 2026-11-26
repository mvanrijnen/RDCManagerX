unit RdcmX.AdLdap;

{
  Reads the OUs and computers below an OU from Active Directory, for RdcmX.AdSync. Uses ADSI through the ADO
  provider ADsDSOObject (late bound, no type library), with the current Windows account. The bind is authenticated
  (ADS_SECURE_AUTHENTICATION: Kerberos/Negotiate, which signs and seals LDAP by default), first with explicit
  signing and sealing; when the provider refuses that combination ("property value is not valid"), once more with
  secure authentication only. ADS_SERVER_BIND with a server. Errors name the step that failed.
  Read only. Call from a background thread: it initialises COM for that thread itself.

  The OU and server come from the file. They are validated (no characters that change the query), and the caller
  asks the user once per server + OU before the first query (a foreign file could name an attacker's LDAP server,
  to which Windows might authenticate with NTLM).
}

interface

uses
  RdcmX.AdSync;

/// <summary>False with aError on an invalid OU/server or a failed query (message from ADSI).</summary>
function RdcAdQuery(const aServer, aOuDn: string; out aEntries: TArray<TRdcAdEntry>; out aError: string): Boolean;
type
  /// <summary>Where a query goes and what deserves a warning (ConfirmAdQuery).</summary>
  TRdcAdTarget = record
    /// <summary>The server Windows will authenticate to: the domain controller from the settings, or (empty) the
    /// domain of the DC= parts of the OU, which ADSI locates through DNS - not necessarily the domain of this PC.</summary>
    Target: string;
    ServerGiven: Boolean;
    IsIpAddress: Boolean;
    /// <summary>Target is not this PC's domain or below it (or this PC is in no domain).</summary>
    OutsidePcDomain: Boolean;
  end;

/// <summary>"OU=x,DC=contoso,DC=com" -> "contoso.com" (lower case; '' without DC= parts).</summary>
function RdcAdDomainOfDn(const aDn: string): string;
/// <summary>DNS domain of this PC ('' when not in a domain).</summary>
function RdcThisPcDomain: string;
function RdcAdTargetOf(const aServer, aOuDn, aPcDomain: string): TRdcAdTarget;

/// <summary>OU and server usable in an ADsPath (no &lt; &gt; ; or line breaks; server without / or spaces).</summary>
function RdcAdIsValidPath(const aServer, aOuDn: string; out aError: string): Boolean;

implementation

uses
  Winapi.ActiveX, Winapi.Windows,
  System.Generics.Collections, System.SysUtils, System.Variants, System.Win.ComObj,
  RdcmX.Lang;

const
  ADS_SECURE_AUTHENTICATION = $1;
  ADS_USE_SIGNING = $40;
  ADS_USE_SEALING = $80;
  ADS_SERVER_BIND = $200;
  ADS_UF_ACCOUNTDISABLE = $2;
  cPageSize = 1000;
  cSearchScopeSubtree = 2;
  /// <summary>More entries than this: refused with a message (narrow the OU or use the name filter).</summary>
  cMaxEntries = 5000;
  /// <summary>Seconds; a hanging server must not block the refresh of this group forever.</summary>
  cTimeoutSeconds = 60;

function RdcAdDomainOfDn(const aDn: string): string;
var
  lPart: string;
begin
  Result := '';
  for lPart in RdcAdNormalizeDn(aDn).Split([',']) do
    if lPart.StartsWith('dc=') then
    begin
      if Result <> '' then
        Result := Result + '.';
      Result := Result + Copy(lPart, 4, MaxInt);
    end;
end;

function RdcThisPcDomain: string;
var
  lBuffer: array[0..255] of Char;
  lSize: DWORD;
begin
  lSize := Length(lBuffer);
  if GetComputerNameEx(ComputerNameDnsDomain, lBuffer, lSize) then
    Result := LowerCase(string(lBuffer))
  else
    Result := '';
end;

function IsIpAddress(const aHost: string): Boolean;
var
  lChar: Char;
begin
  if aHost.Contains(':') then
    Exit(True); // IPv6
  Result := aHost <> '';
  for lChar in aHost do
    if not CharInSet(lChar, ['0'..'9', '.']) then
      Exit(False);
end;

function RdcAdTargetOf(const aServer, aOuDn, aPcDomain: string): TRdcAdTarget;
var
  lPcDomain: string;
begin
  Result := Default(TRdcAdTarget);
  Result.ServerGiven := Trim(aServer) <> '';
  if Result.ServerGiven then
    Result.Target := LowerCase(Trim(aServer))
  else
    Result.Target := RdcAdDomainOfDn(aOuDn);
  Result.IsIpAddress := IsIpAddress(Result.Target);
  lPcDomain := LowerCase(Trim(aPcDomain));
  Result.OutsidePcDomain := (lPcDomain = '') or Result.IsIpAddress or
    not (SameText(Result.Target, lPcDomain) or Result.Target.EndsWith('.' + lPcDomain));
end;

function RdcAdIsValidPath(const aServer, aOuDn: string; out aError: string): Boolean;
var
  lChar: Char;
begin
  aError := '';
  Result := False;
  if Trim(aOuDn) = '' then
  begin
    aError := _('Geen OU opgegeven.');
    Exit;
  end;
  for lChar in aOuDn do
    if CharInSet(lChar, ['<', '>', ';', #10, #13]) then
    begin
      aError := Format(_('De OU "%s" bevat een ongeldig teken.'), [aOuDn]);
      Exit;
    end;
  if not aOuDn.Contains('=') then
  begin
    aError := Format(_('"%s" is geen distinguished name (bijv. OU=Computers,DC=contoso,DC=com).'), [aOuDn]);
    Exit;
  end;
  for lChar in aServer do
    if CharInSet(lChar, ['<', '>', ';', '/', '\', ' ', #10, #13]) then
    begin
      aError := Format(_('De domeincontroller "%s" bevat een ongeldig teken.'), [aServer]);
      Exit;
    end;
  Result := True;
end;

function FieldText(const aRecordSet: OleVariant; const aName: string): string;
var
  lValue: OleVariant;
begin
  lValue := aRecordSet.Fields[aName].Value;
  if VarIsNull(lValue) or VarIsEmpty(lValue) then
    Result := ''
  else if VarIsArray(lValue) then
    Result := VarToStr(lValue[VarArrayLowBound(lValue, 1)])
  else
    Result := VarToStr(lValue);
end;

function QueryWithFlags(const aBase: string; aFlags: Integer; out aEntries: TArray<TRdcAdEntry>; out aError: string): Boolean;
var
  lCommand: OleVariant;
  lConnection: OleVariant;
  lList: TList<TRdcAdEntry>;
  lRecords: OleVariant;
  lStep: string;
  lUac: Integer;

  procedure AddEntry(const aEntry: TRdcAdEntry);
  begin
    if lList.Count >= cMaxEntries then
      raise Exception.CreateFmt(_('Meer dan %d objecten in deze OU; kies een kleinere OU of gebruik het naamfilter.'), [cMaxEntries]);
    lList.Add(aEntry);
  end;

  procedure Run(const aFilter, aAttributes: string);
  begin
    lCommand.CommandText := Format('<%s>;%s;%s;subtree', [aBase, aFilter, aAttributes]);
    lRecords := lCommand.Execute;
  end;

begin
  aEntries := [];
  aError := '';
  lList := TList<TRdcAdEntry>.Create;
  try
    lList.Capacity := cPageSize;
    lStep := 'connect';
    lConnection := CreateOleObject('ADODB.Connection');
    lConnection.Provider := 'ADsDSOObject';
    // A variable goes by reference (VT_BYREF) in a late-bound call, which ADO refuses for Property.Value ("the
    // property value is not valid"): pass a value.
    lConnection.Properties.Item['ADSI Flag'].Value := VarAsType(aFlags, varInteger);
    lConnection.Open('Active Directory Provider');
    try
      lCommand := CreateOleObject('ADODB.Command');
      lCommand.ActiveConnection := lConnection;
      lCommand.Properties.Item['Page Size'].Value := cPageSize;
      lCommand.Properties.Item['Searchscope'].Value := cSearchScopeSubtree;
      // Server-side time limit and client-side timeout (seconds).
      lCommand.Properties.Item['Time Limit'].Value := cTimeoutSeconds;
      lCommand.Properties.Item['Timeout'].Value := cTimeoutSeconds;
      lCommand.CommandTimeout := cTimeoutSeconds;

      lStep := 'OUs';
      Run('(objectCategory=organizationalUnit)', 'distinguishedName,name');
      while not lRecords.EOF do
      begin
        AddEntry(TRdcAdEntry.Ou(FieldText(lRecords, 'distinguishedName'), FieldText(lRecords, 'name')));
        lRecords.MoveNext;
      end;
      lRecords.Close;

      lStep := 'computers';
      Run('(objectCategory=computer)', 'distinguishedName,name,dNSHostName,userAccountControl');
      while not lRecords.EOF do
      begin
        lUac := StrToIntDef(FieldText(lRecords, 'userAccountControl'), 0);
        AddEntry(TRdcAdEntry.Computer(FieldText(lRecords, 'distinguishedName'), FieldText(lRecords, 'name'), FieldText(lRecords, 'dNSHostName'), (lUac and ADS_UF_ACCOUNTDISABLE) <> 0));
        lRecords.MoveNext;
      end;
      lRecords.Close;
    finally
      lConnection.Close;
    end;
    aEntries := lList.ToArray;
    Result := True;
  except
    on E: Exception do
    begin
      aError := Format('%s (%s, ADSI flags $%x)', [E.Message, lStep, aFlags]);
      aEntries := [];
      Result := False;
    end;
  end;
  lList.Free;
  lRecords := Unassigned;
  lCommand := Unassigned;
  lConnection := Unassigned;
end;

function RdcAdQuery(const aServer, aOuDn: string; out aEntries: TArray<TRdcAdEntry>; out aError: string): Boolean;
var
  lBase: string;
  lFirstError: string;
  lFlags: Integer;
begin
  aEntries := [];
  aError := '';
  if not RdcAdIsValidPath(aServer, aOuDn, aError) then
    Exit(False);
  // ADsPath: LDAP://[server/]DN; a '/' inside the DN must be escaped.
  lBase := 'LDAP://';
  if aServer <> '' then
    lBase := lBase + aServer + '/';
  lBase := lBase + StringReplace(Trim(aOuDn), '/', '\/', [rfReplaceAll]);
  lFlags := ADS_SECURE_AUTHENTICATION;
  if aServer <> '' then
    lFlags := lFlags or ADS_SERVER_BIND;

  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    Result := QueryWithFlags(lBase, lFlags or ADS_USE_SIGNING or ADS_USE_SEALING, aEntries, lFirstError);
    if not Result then
    begin
      Result := QueryWithFlags(lBase, lFlags, aEntries, aError);
      if not Result then
        aError := lFirstError + sLineBreak + aError;
    end;
  finally
    CoUninitialize;
  end;
end;

end.
