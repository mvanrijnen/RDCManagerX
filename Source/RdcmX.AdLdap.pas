unit RdcmX.AdLdap;

{
  Reads the OUs and computers below an OU from Active Directory, for RdcmX.AdSync. Uses ADSI through the ADO
  provider ADsDSOObject (late bound, no type library), with the current Windows account; the bind is authenticated,
  signed and sealed (ADS_SECURE_AUTHENTICATION | ADS_USE_SIGNING | ADS_USE_SEALING; ADS_SERVER_BIND with a server).
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
/// <summary>OU and server usable in an ADsPath (no &lt; &gt; ; or line breaks; server without / or spaces).</summary>
function RdcAdIsValidPath(const aServer, aOuDn: string; out aError: string): Boolean;

implementation

uses
  Winapi.ActiveX,
  System.SysUtils, System.Variants, System.Win.ComObj,
  RdcmX.Lang;

const
  ADS_SECURE_AUTHENTICATION = $1;
  ADS_USE_SIGNING = $40;
  ADS_USE_SEALING = $80;
  ADS_SERVER_BIND = $200;
  ADS_UF_ACCOUNTDISABLE = $2;
  cPageSize = 1000;
  cSearchScopeSubtree = 2;

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

function RdcAdQuery(const aServer, aOuDn: string; out aEntries: TArray<TRdcAdEntry>; out aError: string): Boolean;
var
  lBase: string;
  lCommand: OleVariant;
  lConnection: OleVariant;
  lFlags: Integer;
  lRecords: OleVariant;
  lUac: Integer;

  procedure Run(const aFilter, aAttributes: string);
  begin
    lCommand.CommandText := Format('<%s>;%s;%s;subtree', [lBase, aFilter, aAttributes]);
    lRecords := lCommand.Execute;
  end;

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
  lFlags := ADS_SECURE_AUTHENTICATION or ADS_USE_SIGNING or ADS_USE_SEALING;
  if aServer <> '' then
    lFlags := lFlags or ADS_SERVER_BIND;

  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    try
      lConnection := CreateOleObject('ADODB.Connection');
      lConnection.Provider := 'ADsDSOObject';
      lConnection.Properties['ADSI Flag'].Value := lFlags;
      lConnection.Open('Active Directory Provider');
      try
        lCommand := CreateOleObject('ADODB.Command');
        lCommand.ActiveConnection := lConnection;
        lCommand.Properties['Page Size'].Value := cPageSize;
        lCommand.Properties['Searchscope'].Value := cSearchScopeSubtree;

        Run('(objectCategory=organizationalUnit)', 'distinguishedName,name');
        while not lRecords.EOF do
        begin
          aEntries := aEntries + [TRdcAdEntry.Ou(FieldText(lRecords, 'distinguishedName'), FieldText(lRecords, 'name'))];
          lRecords.MoveNext;
        end;
        lRecords.Close;

        Run('(objectCategory=computer)', 'distinguishedName,name,dNSHostName,userAccountControl');
        while not lRecords.EOF do
        begin
          lUac := StrToIntDef(FieldText(lRecords, 'userAccountControl'), 0);
          aEntries := aEntries + [TRdcAdEntry.Computer(FieldText(lRecords, 'distinguishedName'), FieldText(lRecords, 'name'), FieldText(lRecords, 'dNSHostName'), (lUac and ADS_UF_ACCOUNTDISABLE) <> 0)];
          lRecords.MoveNext;
        end;
        lRecords.Close;
      finally
        lConnection.Close;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        aError := E.Message;
        aEntries := [];
        Result := False;
      end;
    end;
  finally
    lRecords := Unassigned;
    lCommand := Unassigned;
    lConnection := Unassigned;
    CoUninitialize;
  end;
end;

end.
