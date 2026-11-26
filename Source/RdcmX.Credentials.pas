unit RdcmX.Credentials;

{
  Onthouden wachtwoorden: een kluis met hoofdwachtwoord, opgeslagen in Windows Referentiebeheer. Alleen actief als
  "Onthouden van wachtwoorden toestaan" in Opties aan staat.

  Twee lagen versleuteling:
  1. Kluis: uit het hoofdwachtwoord wordt met PBKDF2-HMAC-SHA256 (cVaultIterations rondes, willekeurige salt) een
     256-bits sleutel afgeleid. Elk wachtwoord wordt met AES-256-GCM versleuteld (unieke nonce; de doelnaam is
     "authenticated data", zodat een item niet ongemerkt naar een ander account/een andere server te verplaatsen is).
  2. Windows Referentiebeheer: Windows versleutelt de opgeslagen gegevens nog eens met DPAPI (Windows-account).
  Het hoofdwachtwoord wordt nergens opgeslagen; alleen een controlewaarde (een bekende tekst, versleuteld met de
  sleutel) waarmee een ingevoerd hoofdwachtwoord gecontroleerd wordt. Zonder hoofdwachtwoord zijn de items ook
  voor software onder hetzelfde Windows-account waardeloos. Wie het hoofdwachtwoord vergeet, kan de kluis alleen
  leegmaken (Reset).

  Zolang de kluis ontgrendeld is, staat de sleutel versleuteld in het geheugen (CryptProtectMemory) en wordt hij
  alleen kort ontsleuteld voor gebruik; Lock wist hem. Wachtwoorden en sleutels worden na gebruik overschreven.

  Opslag (IRdcBlobStore): TRdcWindowsBlobStore = Referentiebeheer (generic credentials, persist LOCAL_MACHINE);
  de tests gebruiken een geheugenopslag. Items:
  - 'RDCManagerX:vault': versie(1) + iteraties(4) + salt(16) + versleutelde controlewaarde.
  - 'RDCManagerX:account:<domein\gebruiker>' / 'RDCManagerX:server:<host>:<gebruiker>': versie(1) + versleuteld
    wachtwoord. Per account; lokale accounts per server (zie TargetFor).
    Account passwords are bound to approved hosts: the encrypted payload holds the password plus the list of host keys
    (DirectHostKey/TailnetHostKey/ViaGatewayHostKey) it may be sent to, so the list is confidential and bound to the
    target name (AAD). A file pointing the same account at another host does not get the password without asking
    (LoadApproved). Payload: #0 #2, then length-prefixed UTF-8 password, count, length-prefixed host keys. Items from
    before this (plain UTF-8 password) have an empty list: their first use per host asks too.
  - 'RDCManagerX:tailnet:<id>:authkey' / ':statekey' en 'RDCManagerX:gateway:<id>': zelfde formaat, voor de auth key
    en state-sleutel van een Tailscale-netwerk en het wachtwoord van een gateway. Vallen onder hetzelfde
    hoofdwachtwoord (opnieuw versleutelen, kluis legen).
}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  RdcmX.Model;

const
  cRdcVaultTarget = 'RDCManagerX:vault';
  cRdcMinMasterPasswordLength = 16;

type
  /// <summary>A host a remembered account password would be sent to. Key goes into the approval list,
  /// Display into the question to the user.</summary>
  TRdcHostRef = record
    Key: string;
    Display: string;
    class function Create(const aKey, aDisplay: string): TRdcHostRef; static;
  end;

  /// <summary>Asks whether the remembered password may be used for these not yet approved hosts (default: no).</summary>
  TRdcApproveHostsFunc = reference to function(const aMissing: TArray<TRdcHostRef>): Boolean;

  /// <summary>Outcome of ChangeMasterPassword. crStoreError: nothing changed (a read/write failed, or another instance
  /// is changing it). crInconsistent: copying and rolling back both failed; the vault is locked, the next start
  /// finishes the change (RecoverInterruptedChange).</summary>
  TRdcChangeResult = (crOk, crWrongPassword, crStoreError, crInconsistent);

  /// <summary>rlrNone: nothing stored, vault locked or unreadable; rlrDeclined: the user did not approve a host.</summary>
  TRdcLoadResult = (rlrNone, rlrDeclined, rlrLoaded);

  /// <summary>Opslag van binaire items op doelnaam (Windows Referentiebeheer, of in het geheugen voor tests).</summary>
  IRdcBlobStore = interface
    ['{6B8E0F55-3A3B-4C51-9C55-2E2C2E7E1A01}']
    function Read(const aTarget: string; out aData: TBytes): Boolean;
    function Write(const aTarget, aUserName: string; const aData: TBytes): Boolean;
    procedure Delete(const aTarget: string);
    /// <summary>Alle doelnamen die met aPrefix beginnen.</summary>
    function Targets(const aPrefix: string): TArray<string>;
  end;

  /// <summary>Toegang tot de kluis voor andere schermen (beheer van Tailscale-netwerken en gateways); het
  /// hoofdvenster implementeert dit en vraagt zo nodig het hoofdwachtwoord.</summary>
  IRdcSecretAccess = interface
    ['{0E7E6C3A-5B7D-4F44-9D3C-7A1E2B9C4D10}']
    /// <summary>True als geheimen bewaard kunnen worden ("Wachtwoorden onthouden" aan en een kluis aanwezig).</summary>
    function CanStoreSecrets: Boolean;
    function HasSecret(const aTarget: string): Boolean;
    /// <summary>Ontgrendelt zo nodig (aReason in de vraag om het hoofdwachtwoord). False als er niets is of bij annuleren.</summary>
    function LoadSecret(const aTarget, aReason: string; out aSecret: string): Boolean;
    function SaveSecret(const aTarget, aAccount, aSecret, aReason: string): Boolean;
    procedure DeleteSecret(const aTarget: string);
    /// <summary>Alle geheimen waarvan de doelnaam met aPrefix begint (bijv. alles van één netwerk).</summary>
    procedure DeleteSecretsWithPrefix(const aPrefix: string);
  end;

  TRdcWindowsBlobStore = class(TInterfacedObject, IRdcBlobStore)
  public
    function Read(const aTarget: string; out aData: TBytes): Boolean;
    function Write(const aTarget, aUserName: string; const aData: TBytes): Boolean;
    procedure Delete(const aTarget: string);
    function Targets(const aPrefix: string): TArray<string>;
  end;

  TRdcPasswordVault = class
  private
    FStore: IRdcBlobStore;
    FIterations: Cardinal;
    FKey: TBytes; // versleuteld in het geheugen (CryptProtectMemory) zolang ontgrendeld
    FLastUse: TDateTime;
    FLastChangeResult: TRdcChangeResult;
    class var FChangeMutexName: string;
    class constructor CreateClass;
    function DeriveAndCheck(const aMasterPassword: string; out aKey: TBytes): Boolean;
    function KeyMatchesStore(const aKey: TBytes): Boolean;
    function WriteItem(const aKey: TBytes; const aTarget, aAccount: string; const aData: TBytes): Boolean;
    function BuildVaultItem(const aKey: TBytes; const aSalt: TBytes; aIterations: Cardinal): TBytes;
    function WriteVaultItem(const aKey: TBytes; const aSalt: TBytes; aIterations: Cardinal): Boolean;
    function SealPassword(const aKey: TBytes; const aTarget, aPassword: string): TBytes;
    function SealBytes(const aKey: TBytes; const aTarget: string; const aPlain: TBytes): TBytes;
    function OpenBytes(const aKey: TBytes; const aTarget: string; const aData: TBytes; out aPlain: TBytes): Boolean;
    function OpenPassword(const aKey: TBytes; const aTarget: string; const aData: TBytes; out aPassword: string): Boolean;
    function OpenAccount(const aTarget: string; out aPassword: string; out aHostKeys: TArray<string>): Boolean;
    function SealAccount(const aTarget, aAccount, aPassword: string; const aHostKeys: TArray<string>): Boolean;
    function StagedTargets: TArray<string>;
    function CommitStaged: Boolean;
    procedure DeleteStaged;
    procedure RecoverInterruptedChange;
    procedure RecoverStaging;
    function DoChangeMasterPassword(const aOldMasterPassword, aNewMasterPassword: string): TRdcChangeResult;
    function PasswordTargets: TArray<string>;
    function UseKey: TBytes;
    procedure ReleaseKey(var aKey: TBytes);
    procedure SetKey(var aKey: TBytes);
  public
    /// <summary>aIterations: PBKDF2-rondes voor een NIEUWE kluis (tests gebruiken minder).
    /// Finishes or discards a master password change that was interrupted (see ChangeMasterPassword).</summary>
    constructor Create(const aStore: IRdcBlobStore; aIterations: Cardinal = 0);
    destructor Destroy; override;
    /// <summary>Doelnaam voor dit account op deze server: per account, lokale accounts per server.</summary>
    class function TargetFor(const aServerHost, aDomain, aUserName: string): string; static;
    /// <summary>Doelnamen voor de geheimen van Tailscale-netwerken en gateways. De definities staan in het bestand,
    /// de geheimen alleen hier, op id ÉN gebonden aan de server waarvoor ze gelden (control URL resp. gateway
    /// host:poort, als hash in de naam). Een (gemanipuleerd) bestand met hetzelfde id maar een andere server vindt
    /// het geheim dus niet en kan het niet naar een vreemde server laten sturen.</summary>
    class function TailnetAuthKeyTarget(const aTailnetId, aControlUrl: string): string; static;
    class function TailnetStateKeyTarget(const aTailnetId, aControlUrl: string): string; static;
    class function TailnetTargetPrefix(const aTailnetId: string): string; static;
    /// <summary>Key for client-side settings of a tailnet (id + hash of the control URL), as for its secrets: a file
    /// with the same id but another control server does not get them.</summary>
    class function TailnetBindingKey(const aTailnetId, aControlUrl: string): string; static;
    class function GatewayTarget(const aGatewayId, aGatewayAddress: string): string; static;
    class function GatewayTargetPrefix(const aGatewayId: string): string; static;
    /// <summary>Approval keys for the hosts an account password goes to: the RDP server on route Direct or Gateway,
    /// the device in a tailnet (its MagicDNS FQDN as resolved by the bridge, bound to the control server (hash of the
    /// normalized control URL) and the tailnet's MagicDNS suffix: another tailnet with the same names is another key,
    /// also on the same control server, and a Headscale server that claims the same suffix as well), and
    /// a server reached through an RD Gateway: the gateway sees the connection whatever credSharing says, so the
    /// combination gateway + server is a host of its own.</summary>
    class function DirectHostKey(const aHost: string): string; static;
    class function TailnetHostKey(const aControlUrl, aTailnetSuffix, aDeviceFqdn: string): string; static;
    class function ViaGatewayHostKey(const aGatewayAddress, aHost: string): string; static;
    /// <summary>AuthenticationLevel to use (0 = connect without warning, 1 = do not connect when server
    /// authentication fails, 2 = warn). With a password from the vault: route Direct or Gateway always 1, whatever the
    /// file says; route Tailscale at least 2 (the connection goes to 127.0.0.2, so the certificate name never
    /// matches; the target is already restricted to the tailnet device). A typed password keeps the file's level.</summary>
    class function AuthenticationLevelFor(aLevel: Cardinal; aFromVault: Boolean; aRoute: TRdcRouteKind): Cardinal; static;
    /// <summary>Control URL zoals die voor de binding telt (kleine letters, zonder / aan het eind; leeg = Tailscale).</summary>
    class function NormalizeControlUrl(const aControlUrl: string): string; static;
    /// <summary>Heeft het hoofdwachtwoord voldoende lengte?</summary>
    class function IsStrongEnough(const aMasterPassword: string): Boolean; static;
    /// <summary>Is aMasterPassword usable as master password? At least cRdcMinMasterPasswordLength characters, and
    /// not an obvious pattern: few different characters, a repeated block, a keyboard or alphabet run, or a common
    /// word with only digits and punctuation around it. No composition rules (they make passwords predictable, not
    /// stronger). aReason: why not (UI text).</summary>
    class function CheckMasterPassword(const aMasterPassword: string; out aReason: string): Boolean; static;
    function IsInitialized: Boolean;
    function IsUnlocked: Boolean;
    /// <summary>Nieuwe kluis met dit hoofdwachtwoord; bestaande items (ook van een oude kluis) worden gewist. Ontgrendelt.</summary>
    function Initialize(const aMasterPassword: string): Boolean;
    /// <summary>False bij een verkeerd hoofdwachtwoord.</summary>
    function Unlock(const aMasterPassword: string): Boolean;
    procedure Lock;
    /// <summary>Is er een wachtwoord voor deze doelnaam (zonder te ontsleutelen)?</summary>
    function HasPassword(const aTarget: string): Boolean;
    /// <summary>Vereist een ontgrendelde kluis. False als er niets is of het item niet te ontsleutelen is.</summary>
    function TryLoad(const aTarget: string; out aPassword: string): Boolean;
    /// <summary>Vereist een ontgrendelde kluis.</summary>
    function Save(const aTarget, aAccount, aPassword: string): Boolean;
    /// <summary>Saves an account password the user typed for these hosts: they are approved, together with the hosts
    /// approved before (if the existing item is readable). Requires an unlocked vault.</summary>
    function SaveAccount(const aTarget, aAccount, aPassword: string; const aHosts: TArray<TRdcHostRef>): Boolean;
    /// <summary>The hosts in aHosts that are not approved for this item yet (all of them for an old item).
    /// Requires an unlocked vault; empty when there is no readable item.</summary>
    function MissingHosts(const aTarget: string; const aHosts: TArray<TRdcHostRef>): TArray<TRdcHostRef>;
    /// <summary>Adds hosts to the approval list. Requires an unlocked vault.</summary>
    function ApproveHosts(const aTarget, aAccount: string; const aHosts: TArray<TRdcHostRef>): Boolean;
    /// <summary>The account password for these hosts. Hosts not approved yet are offered to aAsk once (all in one
    /// question); approved ones are added to the list, declined means rlrDeclined and no password.</summary>
    function LoadApproved(const aTarget, aAccount: string; const aHosts: TArray<TRdcHostRef>; const aAsk: TRdcApproveHostsFunc; out aPassword: string): TRdcLoadResult;
    procedure Delete(const aTarget: string);
    /// <summary>Alle items waarvan de doelnaam met aPrefix begint (nooit de kluis zelf).</summary>
    procedure DeleteByPrefix(const aPrefix: string);
    /// <summary>Aantal onthouden wachtwoorden.</summary>
    function Count: Integer;
    /// <summary>Kluis en alle wachtwoorden verwijderen; vergrendelt. Geeft het aantal verwijderde wachtwoorden.</summary>
    function Reset: Integer;
    /// <summary>Alle wachtwoorden opnieuw versleutelen met een nieuw hoofdwachtwoord. False bij een verkeerd oud
    /// hoofdwachtwoord, or when the store refuses a write: then nothing has changed.
    /// Two phases: every item is first re-encrypted under a staging name (any failure: staging removed, old vault
    /// untouched); then the new vault item is written (the commit point) and the staged items are copied over the
    /// real ones. A crash after the commit point is finished by RecoverInterruptedChange at the next start.</summary>
    function ChangeMasterPassword(const aOldMasterPassword, aNewMasterPassword: string): Boolean;
    /// <summary>Tijdstip van het laatste gebruik (voor automatisch vergrendelen).</summary>
    property LastUse: TDateTime read FLastUse;
    /// <summary>Why the last ChangeMasterPassword returned False.</summary>
    property LastChangeResult: TRdcChangeResult read FLastChangeResult;
    /// <summary>Named mutex held during a master password change (and taken by the recovery at startup, which is
    /// skipped while another instance holds it). Tests use their own name.</summary>
    class property ChangeMutexName: string read FChangeMutexName write FChangeMutexName;
  end;

/// <summary>Inhoud van een string (bijv. een wachtwoord) overschrijven en de string leegmaken.</summary>
procedure WipeString(var aValue: string);

implementation

uses
  System.Hash,
  RdcmX.Crypto, RdcmX.Lang;

const
  CRED_TYPE_GENERIC = 1;
  CRED_PERSIST_LOCAL_MACHINE = 2;
  cTargetPrefix = 'RDCManagerX:';
  cComment = 'RDCManagerX (versleuteld met hoofdwachtwoord)';
  cFormatVersion = 1;
  cVaultIterations = 600000; // PBKDF2-HMAC-SHA256, OWASP-advies
  cVaultCheckText = 'RDCManagerX-kluis-v1';
  // Staging area of ChangeMasterPassword: never counted as a password, never loaded.
  cStagingPrefix = cTargetPrefix + '~staging:';
  cStagedVaultTarget = cStagingPrefix + 'vault';

type
  // CREDENTIALW uit wincred.h (natuurlijke uitlijning).
  TCredentialW = record
    Flags: DWORD;
    CredType: DWORD;
    TargetName: PWideChar;
    Comment: PWideChar;
    LastWritten: TFileTime;
    CredentialBlobSize: DWORD;
    CredentialBlob: PByte;
    Persist: DWORD;
    AttributeCount: DWORD;
    Attributes: Pointer;
    TargetAlias: PWideChar;
    UserName: PWideChar;
  end;
  PCredentialW = ^TCredentialW;
  TCredentialArray = array[0..(MaxInt div SizeOf(PCredentialW)) - 1] of PCredentialW;
  PCredentialArray = ^TCredentialArray;

function CredWriteW(aCredential: PCredentialW; aFlags: DWORD): BOOL; stdcall; external advapi32 name 'CredWriteW';
function CredReadW(aTargetName: PWideChar; aType: DWORD; aFlags: DWORD; out aCredential: PCredentialW): BOOL; stdcall; external advapi32 name 'CredReadW';
function CredDeleteW(aTargetName: PWideChar; aType: DWORD; aFlags: DWORD): BOOL; stdcall; external advapi32 name 'CredDeleteW';
function CredEnumerateW(aFilter: PWideChar; aFlags: DWORD; out aCount: DWORD; out aCredentials: PCredentialArray): BOOL; stdcall; external advapi32 name 'CredEnumerateW';
procedure CredFree(aBuffer: Pointer); stdcall; external advapi32 name 'CredFree';

procedure WipeString(var aValue: string);
begin
  if aValue = '' then
    Exit;
  UniqueString(aValue);
  FillChar(PChar(aValue)^, Length(aValue) * SizeOf(Char), 0);
  aValue := '';
end;

function ShortHostName(const aHost: string): string;
var
  lDot: Integer;
begin
  Result := Trim(aHost);
  lDot := Pos('.', Result);
  if lDot > 0 then
    Result := Copy(Result, 1, lDot - 1);
end;

function Utf8(const aText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(aText);
end;

const
  cAccountPayloadMarker = 0;
  cAccountPayloadVersion = 2;

procedure AppendBytes(var aBuffer: TBytes; const aData: TBytes);
var
  lLength: Cardinal;
  lOffset: Integer;
begin
  lLength := Length(aData);
  lOffset := Length(aBuffer);
  SetLength(aBuffer, lOffset + SizeOf(Cardinal) + Integer(lLength));
  Move(lLength, aBuffer[lOffset], SizeOf(Cardinal));
  if lLength > 0 then
    Move(aData[0], aBuffer[lOffset + SizeOf(Cardinal)], lLength);
end;

function ReadBytes(const aBuffer: TBytes; var aOffset: Integer; out aData: TBytes): Boolean;
var
  lLength: Cardinal;
begin
  aData := nil;
  Result := aOffset + SizeOf(Cardinal) <= Length(aBuffer);
  if not Result then
    Exit;
  Move(aBuffer[aOffset], lLength, SizeOf(Cardinal));
  Inc(aOffset, SizeOf(Cardinal));
  Result := Int64(aOffset) + lLength <= Length(aBuffer);
  if Result then
  begin
    aData := Copy(aBuffer, aOffset, lLength);
    Inc(aOffset, lLength);
  end;
end;

function EncodeAccountPayload(const aPassword: string; const aHostKeys: TArray<string>): TBytes;
var
  lCount: Cardinal;
  lKey: string;
  lPassword: TBytes;
begin
  Result := TBytes.Create(cAccountPayloadMarker, cAccountPayloadVersion);
  lPassword := TEncoding.UTF8.GetBytes(aPassword);
  try
    AppendBytes(Result, lPassword);
  finally
    WipeBytes(lPassword);
  end;
  lCount := Length(aHostKeys);
  SetLength(Result, Length(Result) + SizeOf(Cardinal));
  Move(lCount, Result[Length(Result) - SizeOf(Cardinal)], SizeOf(Cardinal));
  for lKey in aHostKeys do
    AppendBytes(Result, TEncoding.UTF8.GetBytes(lKey));
end;

function DecodeAccountPayload(const aPlain: TBytes; out aPassword: string; out aHostKeys: TArray<string>): Boolean;
var
  lCount: Cardinal;
  lData: TBytes;
  lIndex: Cardinal;
  lOffset: Integer;
begin
  aPassword := '';
  aHostKeys := [];
  Result := False;
  try
    if (Length(aPlain) < 2) or (aPlain[0] <> cAccountPayloadMarker) then
    begin
      // Old item: the whole payload is the password, nothing approved yet.
      aPassword := TEncoding.UTF8.GetString(aPlain);
      Exit(aPassword <> '');
    end;
    if aPlain[1] <> cAccountPayloadVersion then
      Exit;
    lOffset := 2;
    if not ReadBytes(aPlain, lOffset, lData) then
      Exit;
    aPassword := TEncoding.UTF8.GetString(lData);
    WipeBytes(lData);
    if lOffset + SizeOf(Cardinal) > Length(aPlain) then
      Exit;
    Move(aPlain[lOffset], lCount, SizeOf(Cardinal));
    Inc(lOffset, SizeOf(Cardinal));
    if lCount > 10000 then
      Exit;
    for lIndex := 1 to lCount do
    begin
      if not ReadBytes(aPlain, lOffset, lData) then
        Exit;
      aHostKeys := aHostKeys + [TEncoding.UTF8.GetString(lData)];
    end;
    Result := aPassword <> '';
  finally
    // A payload that breaks off halfway must not leave the password behind.
    if not Result then
    begin
      WipeString(aPassword);
      aHostKeys := [];
    end;
  end;
end;

function ContainsKey(const aKeys: TArray<string>; const aKey: string): Boolean;
var
  lKey: string;
begin
  for lKey in aKeys do
    if SameText(lKey, aKey) then
      Exit(True);
  Result := False;
end;

{ TRdcHostRef }

class function TRdcHostRef.Create(const aKey, aDisplay: string): TRdcHostRef;
begin
  Result.Key := aKey;
  Result.Display := aDisplay;
end;

function TargetAad(const aTarget: string): TBytes;
begin
  // Referentiebeheer vergelijkt doelnamen zonder hoofdlettergevoeligheid (en Enumerate kan een andere schrijfwijze
  // teruggeven): de AAD is daarom de doelnaam in kleine letters.
  Result := Utf8(LowerCase(aTarget));
end;

{ TRdcWindowsBlobStore }

function TRdcWindowsBlobStore.Read(const aTarget: string; out aData: TBytes): Boolean;
var
  lCredential: PCredentialW;
begin
  aData := nil;
  Result := CredReadW(PWideChar(aTarget), CRED_TYPE_GENERIC, 0, lCredential);
  if not Result then
    Exit;
  try
    SetLength(aData, lCredential.CredentialBlobSize);
    if lCredential.CredentialBlobSize > 0 then
    begin
      Move(lCredential.CredentialBlob^, aData[0], lCredential.CredentialBlobSize);
      FillChar(lCredential.CredentialBlob^, lCredential.CredentialBlobSize, 0);
    end;
  finally
    CredFree(lCredential);
  end;
end;

function TRdcWindowsBlobStore.Write(const aTarget, aUserName: string; const aData: TBytes): Boolean;
var
  lCredential: TCredentialW;
begin
  FillChar(lCredential, SizeOf(lCredential), 0);
  lCredential.CredType := CRED_TYPE_GENERIC;
  lCredential.TargetName := PWideChar(aTarget);
  lCredential.Comment := PWideChar(cComment);
  lCredential.CredentialBlobSize := Length(aData);
  if Length(aData) > 0 then
    lCredential.CredentialBlob := @aData[0];
  lCredential.Persist := CRED_PERSIST_LOCAL_MACHINE;
  lCredential.UserName := PWideChar(aUserName);
  Result := CredWriteW(@lCredential, 0);
end;

procedure TRdcWindowsBlobStore.Delete(const aTarget: string);
begin
  CredDeleteW(PWideChar(aTarget), CRED_TYPE_GENERIC, 0);
end;

function TRdcWindowsBlobStore.Targets(const aPrefix: string): TArray<string>;
var
  lCount: DWORD;
  lCredentials: PCredentialArray;
  lIndex: Integer;
begin
  Result := [];
  if not CredEnumerateW(PWideChar(aPrefix + '*'), 0, lCount, lCredentials) then
    Exit;
  try
    for lIndex := 0 to Integer(lCount) - 1 do
      Result := Result + [string(lCredentials[lIndex].TargetName)];
  finally
    CredFree(lCredentials);
  end;
end;

{ TRdcPasswordVault }

function ConvertSidToStringSidW(aSid: PSID; out aStringSid: PWideChar): BOOL; stdcall; external advapi32 name 'ConvertSidToStringSidW';

function CurrentUserSid: string;
var
  lBuffer: TBytes;
  lSize: DWORD;
  lText: PWideChar;
  lToken: THandle;
begin
  Result := '';
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, lToken) then
    Exit;
  try
    lSize := 0;
    GetTokenInformation(lToken, TokenUser, nil, 0, lSize);
    if lSize = 0 then
      Exit;
    SetLength(lBuffer, lSize);
    if not GetTokenInformation(lToken, TokenUser, @lBuffer[0], lSize, lSize) then
      Exit;
    if ConvertSidToStringSidW(PTokenUser(@lBuffer[0]).User.Sid, lText) then
    begin
      Result := lText;
      LocalFree(HLOCAL(lText));
    end;
  finally
    CloseHandle(lToken);
  end;
end;

class constructor TRdcPasswordVault.CreateClass;
var
  lSid: string;
begin
  // Global and per user: the same user on the console and over RDP (two logon sessions) shares one Credential
  // Manager, so a Local\ mutex would not keep them apart (third security review).
  lSid := CurrentUserSid;
  if lSid <> '' then
    FChangeMutexName := 'Global\RDCManagerX.VaultChange.' + lSid
  else
    FChangeMutexName := 'Local\RDCManagerX.VaultChange';
end;

constructor TRdcPasswordVault.Create(const aStore: IRdcBlobStore; aIterations: Cardinal);
begin
  inherited Create;
  FStore := aStore;
  if aIterations = 0 then
    FIterations := cVaultIterations
  else
    FIterations := aIterations;
  RecoverInterruptedChange;
end;

destructor TRdcPasswordVault.Destroy;
begin
  Lock;
  inherited Destroy;
end;

class function TRdcPasswordVault.TargetFor(const aServerHost, aDomain, aUserName: string): string;
var
  lDomain: string;
  lUser: string;
begin
  lDomain := Trim(aDomain);
  lUser := Trim(aUserName);
  if Pos('@', lUser) > 0 then
    Result := cTargetPrefix + 'account:' + LowerCase(lUser)
  else if (lDomain = '') or (lDomain = '.') or SameText(lDomain, ShortHostName(aServerHost)) or SameText(lDomain, Trim(aServerHost)) then
    Result := cTargetPrefix + 'server:' + LowerCase(Trim(aServerHost)) + ':' + LowerCase(lUser)
  else
    Result := cTargetPrefix + 'account:' + LowerCase(lDomain + '\' + lUser);
end;

function BindingHash(const aValue: string): string;
begin
  // Eerste 16 hex-tekens van SHA-256: genoeg om servers te onderscheiden, kort genoeg voor een doelnaam.
  Result := Copy(THashSHA2.GetHashString(aValue, THashSHA2.TSHA2Version.SHA256), 1, 16);
end;

class function TRdcPasswordVault.NormalizeControlUrl(const aControlUrl: string): string;
begin
  Result := LowerCase(Trim(aControlUrl));
  while Result.EndsWith('/') do
    Result := Copy(Result, 1, Length(Result) - 1);
end;

class function TRdcPasswordVault.TailnetTargetPrefix(const aTailnetId: string): string;
begin
  Result := cTargetPrefix + 'tailnet:' + LowerCase(Trim(aTailnetId)) + ':';
end;

class function TRdcPasswordVault.TailnetBindingKey(const aTailnetId, aControlUrl: string): string;
begin
  Result := LowerCase(Trim(aTailnetId)) + ':' + BindingHash(NormalizeControlUrl(aControlUrl));
end;

class function TRdcPasswordVault.TailnetAuthKeyTarget(const aTailnetId, aControlUrl: string): string;
begin
  Result := TailnetTargetPrefix(aTailnetId) + BindingHash(NormalizeControlUrl(aControlUrl)) + ':authkey';
end;

class function TRdcPasswordVault.TailnetStateKeyTarget(const aTailnetId, aControlUrl: string): string;
begin
  Result := TailnetTargetPrefix(aTailnetId) + BindingHash(NormalizeControlUrl(aControlUrl)) + ':statekey';
end;

class function TRdcPasswordVault.GatewayTargetPrefix(const aGatewayId: string): string;
begin
  Result := cTargetPrefix + 'gateway:' + LowerCase(Trim(aGatewayId)) + ':';
end;

class function TRdcPasswordVault.GatewayTarget(const aGatewayId, aGatewayAddress: string): string;
begin
  Result := GatewayTargetPrefix(aGatewayId) + BindingHash(LowerCase(Trim(aGatewayAddress)));
end;

class function TRdcPasswordVault.DirectHostKey(const aHost: string): string;
begin
  Result := 'host:' + LowerCase(Trim(aHost));
end;

class function TRdcPasswordVault.TailnetHostKey(const aControlUrl, aTailnetSuffix, aDeviceFqdn: string): string;
begin
  // 'ts3:' so approvals of older keys are asked once again. The control URL hash is in it because a foreign file can
  // point to its own Headscale server, which can claim any MagicDNS suffix and device name (third security review).
  Result := 'ts3:' + BindingHash(NormalizeControlUrl(aControlUrl)) + ':' + LowerCase(Trim(aTailnetSuffix).Trim(['.'])) + ':' + LowerCase(Trim(aDeviceFqdn).Trim(['.']));
end;

class function TRdcPasswordVault.ViaGatewayHostKey(const aGatewayAddress, aHost: string): string;
begin
  Result := 'via:' + LowerCase(Trim(aGatewayAddress)) + '|' + LowerCase(Trim(aHost));
end;

class function TRdcPasswordVault.AuthenticationLevelFor(aLevel: Cardinal; aFromVault: Boolean; aRoute: TRdcRouteKind): Cardinal;
begin
  Result := aLevel;
  if not aFromVault then
    Exit;
  if aRoute = rkTailscale then
  begin
    if Result = 0 then
      Result := 2;
  end
  else
    Result := 1;
end;

class function TRdcPasswordVault.IsStrongEnough(const aMasterPassword: string): Boolean;
var
  lReason: string;
begin
  Result := CheckMasterPassword(aMasterPassword, lReason);
end;

function DistinctChars(const aText: string): Integer;
var
  lChar: Char;
  lSeen: string;
begin
  lSeen := '';
  for lChar in aText do
    if Pos(lChar, lSeen) = 0 then
      lSeen := lSeen + lChar;
  Result := Length(lSeen);
end;

function IsRepeatedBlock(const aText: string): Boolean;
var
  lBlock: Integer;
  lIndex: Integer;
  lSame: Boolean;
begin
  // "Welkom01Welkom01", "abcabcabcabc": the text is one shorter block over and over.
  for lBlock := 1 to Length(aText) div 2 do
    if Length(aText) mod lBlock = 0 then
    begin
      lSame := True;
      for lIndex := lBlock + 1 to Length(aText) do
        if aText[lIndex] <> aText[lIndex - lBlock] then
        begin
          lSame := False;
          Break;
        end;
      if lSame then
        Exit(True);
    end;
  Result := False;
end;

function IsMostlyRun(const aText: string): Boolean;
const
  cRuns: array[0..3] of string = ('abcdefghijklmnopqrstuvwxyz', '01234567890', 'qwertyuiopasdfghjklzxcvbnm', 'azertyuiopqsdfghjklmwxcvbn');
var
  lAlnum: string;
  lChar: Char;
  lIndex: Integer;
  lNext: Integer;
  lRun: string;
  lSteps: Integer;
begin
  // "1234567890123456", "qwertyuiopasdfgh", "zyxwvuts...": most neighbouring characters are next to each other in
  // the alphabet, the digits or a keyboard row (both directions).
  lAlnum := '';
  for lChar in LowerCase(aText) do
    if CharInSet(lChar, ['a'..'z', '0'..'9']) then
      lAlnum := lAlnum + lChar;
  if Length(lAlnum) < 2 then
    Exit(False);
  lSteps := 0;
  for lIndex := 1 to Length(lAlnum) - 1 do
    for lRun in cRuns do
    begin
      lNext := Pos(lAlnum[lIndex], lRun);
      if (lNext > 0) and (((lNext < Length(lRun)) and (lRun[lNext + 1] = lAlnum[lIndex + 1])) or ((lNext > 1) and (lRun[lNext - 1] = lAlnum[lIndex + 1]))) then
      begin
        Inc(lSteps);
        Break;
      end;
    end;
  Result := lSteps * 10 >= (Length(lAlnum) - 1) * 7;
end;

function IsCommonWordWithPadding(const aText: string): Boolean;
const
  cWords: array[0..13] of string = ('wachtwoord', 'hoofdwachtwoord', 'password', 'masterpassword', 'welkom', 'welcome',
    'geheim', 'secret', 'rdcmanagerx', 'rdcmanager', 'administrator', 'admin', 'letmein', 'qwerty');
var
  lChar: Char;
  lLetters: string;
  lWord: string;
begin
  // "Wachtwoord2026!!!", "P@ssword12345678" after removing digits and punctuation (and the usual @/$/0 for a/s/o).
  lLetters := '';
  for lChar in LowerCase(aText) do
    case lChar of
      'a'..'z': lLetters := lLetters + lChar;
      '@': lLetters := lLetters + 'a';
      '$': lLetters := lLetters + 's';
    end;
  for lWord in cWords do
    if lLetters = lWord then
      Exit(True);
  Result := False;
end;

class function TRdcPasswordVault.CheckMasterPassword(const aMasterPassword: string; out aReason: string): Boolean;
begin
  aReason := '';
  if Length(aMasterPassword) < cRdcMinMasterPasswordLength then
    aReason := Format(_('Het hoofdwachtwoord moet minimaal %d tekens lang zijn.'), [cRdcMinMasterPasswordLength])
  else if (DistinctChars(aMasterPassword) < 6) or IsRepeatedBlock(aMasterPassword) then
    aReason := _('Het hoofdwachtwoord herhaalt steeds dezelfde tekens. Kies iets minder voorspelbaars, bijvoorbeeld een zin van een paar woorden.')
  else if IsMostlyRun(aMasterPassword) then
    aReason := _('Het hoofdwachtwoord is een reeks van het toetsenbord of het alfabet. Kies iets minder voorspelbaars, bijvoorbeeld een zin van een paar woorden.')
  else if IsCommonWordWithPadding(aMasterPassword) then
    aReason := _('Het hoofdwachtwoord is een veelgebruikt woord met cijfers of tekens erbij. Kies iets minder voorspelbaars, bijvoorbeeld een zin van een paar woorden.');
  Result := aReason = '';
end;

function TRdcPasswordVault.IsInitialized: Boolean;
var
  lData: TBytes;
begin
  Result := FStore.Read(cRdcVaultTarget, lData) and (Length(lData) > 5) and (lData[0] = cFormatVersion);
end;

function TRdcPasswordVault.IsUnlocked: Boolean;
begin
  Result := Length(FKey) = cRdcKeySize;
end;

procedure TRdcPasswordVault.SetKey(var aKey: TBytes);
begin
  Lock;
  FKey := Copy(aKey);
  WipeBytes(aKey);
  TRdcCrypto.ProtectMemory(FKey);
  FLastUse := Now;
end;

function TRdcPasswordVault.UseKey: TBytes;
begin
  // Kort ontsleutelde kopie; altijd met ReleaseKey opruimen.
  Result := Copy(FKey);
  TRdcCrypto.UnprotectMemory(Result);
  FLastUse := Now;
end;

procedure TRdcPasswordVault.ReleaseKey(var aKey: TBytes);
begin
  WipeBytes(aKey);
end;

procedure TRdcPasswordVault.Lock;
begin
  WipeBytes(FKey);
end;

function TRdcPasswordVault.BuildVaultItem(const aKey: TBytes; const aSalt: TBytes; aIterations: Cardinal): TBytes;
var
  lSealed: TBytes;
begin
  lSealed := TRdcCrypto.Encrypt(aKey, Utf8(cVaultCheckText), Utf8(cRdcVaultTarget));
  SetLength(Result, 1 + SizeOf(Cardinal) + cRdcSaltSize + Length(lSealed));
  Result[0] := cFormatVersion;
  Move(aIterations, Result[1], SizeOf(Cardinal));
  Move(aSalt[0], Result[1 + SizeOf(Cardinal)], cRdcSaltSize);
  Move(lSealed[0], Result[1 + SizeOf(Cardinal) + cRdcSaltSize], Length(lSealed));
end;

function TRdcPasswordVault.WriteVaultItem(const aKey: TBytes; const aSalt: TBytes; aIterations: Cardinal): Boolean;
begin
  Result := FStore.Write(cRdcVaultTarget, 'RDCManagerX', BuildVaultItem(aKey, aSalt, aIterations));
end;

function TRdcPasswordVault.KeyMatchesStore(const aKey: TBytes): Boolean;
var
  lCheck: TBytes;
  lData: TBytes;
begin
  // Cheap check (no PBKDF2): does the vault item in the store still belong to this key?
  Result := FStore.Read(cRdcVaultTarget, lData) and (Length(lData) >= 1 + SizeOf(Cardinal) + cRdcSaltSize + cRdcNonceSize + cRdcTagSize) and (lData[0] = cFormatVersion)
    and TRdcCrypto.TryDecrypt(aKey, Copy(lData, 1 + SizeOf(Cardinal) + cRdcSaltSize, MaxInt), Utf8(cRdcVaultTarget), lCheck)
    and (TEncoding.UTF8.GetString(lCheck) = cVaultCheckText);
end;

function TRdcPasswordVault.DeriveAndCheck(const aMasterPassword: string; out aKey: TBytes): Boolean;
var
  lCheck: TBytes;
  lData: TBytes;
  lIterations: Cardinal;
  lSalt: TBytes;
  lSealed: TBytes;
begin
  aKey := nil;
  Result := False;
  if not FStore.Read(cRdcVaultTarget, lData) or (Length(lData) < 1 + SizeOf(Cardinal) + cRdcSaltSize + cRdcNonceSize + cRdcTagSize) or (lData[0] <> cFormatVersion) then
    Exit;
  Move(lData[1], lIterations, SizeOf(Cardinal));
  lSalt := Copy(lData, 1 + SizeOf(Cardinal), cRdcSaltSize);
  lSealed := Copy(lData, 1 + SizeOf(Cardinal) + cRdcSaltSize, MaxInt);
  aKey := TRdcCrypto.DeriveKey(aMasterPassword, lSalt, lIterations);
  Result := TRdcCrypto.TryDecrypt(aKey, lSealed, Utf8(cRdcVaultTarget), lCheck) and (TEncoding.UTF8.GetString(lCheck) = cVaultCheckText);
  if not Result then
    WipeBytes(aKey);
end;

function TRdcPasswordVault.SealBytes(const aKey: TBytes; const aTarget: string; const aPlain: TBytes): TBytes;
var
  lSealed: TBytes;
begin
  lSealed := TRdcCrypto.Encrypt(aKey, aPlain, TargetAad(aTarget));
  SetLength(Result, 1 + Length(lSealed));
  Result[0] := cFormatVersion;
  Move(lSealed[0], Result[1], Length(lSealed));
end;

function TRdcPasswordVault.OpenBytes(const aKey: TBytes; const aTarget: string; const aData: TBytes; out aPlain: TBytes): Boolean;
begin
  aPlain := nil;
  Result := (Length(aData) > 1) and (aData[0] = cFormatVersion) and TRdcCrypto.TryDecrypt(aKey, Copy(aData, 1, MaxInt), TargetAad(aTarget), aPlain);
end;

function TRdcPasswordVault.SealPassword(const aKey: TBytes; const aTarget, aPassword: string): TBytes;
var
  lPlain: TBytes;
begin
  lPlain := Utf8(aPassword);
  try
    Result := SealBytes(aKey, aTarget, lPlain);
  finally
    WipeBytes(lPlain);
  end;
end;

function TRdcPasswordVault.OpenPassword(const aKey: TBytes; const aTarget: string; const aData: TBytes; out aPassword: string): Boolean;
var
  lHostKeys: TArray<string>;
  lPlain: TBytes;
begin
  aPassword := '';
  Result := OpenBytes(aKey, aTarget, aData, lPlain);
  if Result then
  begin
    Result := DecodeAccountPayload(lPlain, aPassword, lHostKeys);
    WipeBytes(lPlain);
  end;
end;

function TRdcPasswordVault.PasswordTargets: TArray<string>;
var
  lTarget: string;
begin
  Result := [];
  for lTarget in FStore.Targets(cTargetPrefix) do
    if not SameText(lTarget, cRdcVaultTarget) and not lTarget.StartsWith(cStagingPrefix, True) then
      Result := Result + [lTarget];
end;

function TRdcPasswordVault.StagedTargets: TArray<string>;
var
  lTarget: string;
begin
  Result := [];
  for lTarget in FStore.Targets(cStagingPrefix) do
    if lTarget.StartsWith(cStagingPrefix, True) and not SameText(lTarget, cStagedVaultTarget) then
      Result := Result + [lTarget];
end;

procedure TRdcPasswordVault.DeleteStaged;
var
  lTarget: string;
begin
  for lTarget in StagedTargets do
    FStore.Delete(lTarget);
  FStore.Delete(cStagedVaultTarget);
end;

function TRdcPasswordVault.CommitStaged: Boolean;
var
  lData: TBytes;
  lTarget: string;
begin
  // Copy every staged item over its real target (staging name = cStagingPrefix + real target). The staging area is
  // only removed when all copies succeeded, so a failed copy is retried at the next start.
  Result := True;
  for lTarget in StagedTargets do
    if FStore.Read(lTarget, lData) then
      Result := FStore.Write(Copy(lTarget, Length(cStagingPrefix) + 1, MaxInt), 'RDCManagerX', lData) and Result
    else
      Result := False;
  if Result then
    DeleteStaged;
end;

function OpenChangeMutex: THandle;
begin
  Result := CreateMutex(nil, False, PChar(TRdcPasswordVault.ChangeMutexName));
end;

function TRdcPasswordVault.WriteItem(const aKey: TBytes; const aTarget, aAccount: string; const aData: TBytes): Boolean;
const
  cWaitMs = 10000;
var
  lMutex: THandle;
  lWait: DWORD;
begin
  // Under the change mutex, and only while the store still uses our key: another instance (also in another logon
  // session of this user) may have changed the master password, and an item sealed with the old key would be lost.
  Result := False;
  lMutex := OpenChangeMutex;
  if lMutex = 0 then
    Exit;
  try
    lWait := WaitForSingleObject(lMutex, cWaitMs);
    if not (lWait in [WAIT_OBJECT_0, WAIT_ABANDONED]) then
      Exit;
    try
      if KeyMatchesStore(aKey) then
        Result := FStore.Write(aTarget, aAccount, aData)
      else
        Lock; // the master password was changed elsewhere: unlock again with the new one
    finally
      ReleaseMutex(lMutex);
    end;
  finally
    CloseHandle(lMutex);
  end;
end;

procedure TRdcPasswordVault.RecoverInterruptedChange;
var
  lMutex: THandle;
  lWait: DWORD;
begin
  // Another instance in the middle of a change (phase 1 has staged items but no staged vault item yet): leave its
  // staging area alone.
  lMutex := OpenChangeMutex;
  if lMutex = 0 then
    Exit;
  try
    lWait := WaitForSingleObject(lMutex, 0);
    if not (lWait in [WAIT_OBJECT_0, WAIT_ABANDONED]) then
      Exit;
    try
      RecoverStaging;
    finally
      ReleaseMutex(lMutex);
    end;
  finally
    CloseHandle(lMutex);
  end;
end;

procedure TRdcPasswordVault.RecoverStaging;
var
  lCurrent: TBytes;
  lStaged: TBytes;
begin
  if not FStore.Read(cStagedVaultTarget, lStaged) then
  begin
    // Leftovers without a staged vault item: an aborted first phase.
    if Length(StagedTargets) > 0 then
      DeleteStaged;
    Exit;
  end;
  // Committed (the vault item already is the new one): finish copying. Not committed: the old items are intact.
  if FStore.Read(cRdcVaultTarget, lCurrent) and (Length(lCurrent) = Length(lStaged)) and (Length(lStaged) > 0) and CompareMem(@lCurrent[0], @lStaged[0], Length(lStaged)) then
    CommitStaged
  else
    DeleteStaged;
end;

function TRdcPasswordVault.Initialize(const aMasterPassword: string): Boolean;
var
  lKey: TBytes;
  lSalt: TBytes;
begin
  if not IsStrongEnough(aMasterPassword) then
    Exit(False);
  // Oude items (ook van een eerdere kluis) zijn met de nieuwe sleutel toch niet te openen.
  Reset;
  lSalt := TRdcCrypto.RandomBytes(cRdcSaltSize);
  lKey := TRdcCrypto.DeriveKey(aMasterPassword, lSalt, FIterations);
  try
    Result := WriteVaultItem(lKey, lSalt, FIterations);
    if Result then
      SetKey(lKey);
  finally
    WipeBytes(lKey);
  end;
end;

function TRdcPasswordVault.Unlock(const aMasterPassword: string): Boolean;
var
  lKey: TBytes;
begin
  Result := DeriveAndCheck(aMasterPassword, lKey);
  if Result then
    SetKey(lKey);
end;

function TRdcPasswordVault.HasPassword(const aTarget: string): Boolean;
var
  lData: TBytes;
begin
  Result := FStore.Read(aTarget, lData) and (Length(lData) > 1) and (lData[0] = cFormatVersion);
  WipeBytes(lData);
end;

function TRdcPasswordVault.TryLoad(const aTarget: string; out aPassword: string): Boolean;
var
  lData: TBytes;
  lKey: TBytes;
begin
  aPassword := '';
  if not IsUnlocked or not FStore.Read(aTarget, lData) then
    Exit(False);
  lKey := UseKey;
  try
    Result := OpenPassword(lKey, aTarget, lData, aPassword);
  finally
    ReleaseKey(lKey);
    WipeBytes(lData);
  end;
end;

function TRdcPasswordVault.Save(const aTarget, aAccount, aPassword: string): Boolean;
var
  lKey: TBytes;
begin
  if not IsUnlocked or (aPassword = '') then
    Exit(False);
  lKey := UseKey;
  try
    Result := WriteItem(lKey, aTarget, aAccount, SealPassword(lKey, aTarget, aPassword));
  finally
    ReleaseKey(lKey);
  end;
end;

function TRdcPasswordVault.OpenAccount(const aTarget: string; out aPassword: string; out aHostKeys: TArray<string>): Boolean;
var
  lData: TBytes;
  lKey: TBytes;
  lPlain: TBytes;
begin
  aPassword := '';
  aHostKeys := [];
  if not IsUnlocked or not FStore.Read(aTarget, lData) then
    Exit(False);
  lKey := UseKey;
  try
    Result := OpenBytes(lKey, aTarget, lData, lPlain) and DecodeAccountPayload(lPlain, aPassword, aHostKeys);
  finally
    WipeBytes(lPlain);
    ReleaseKey(lKey);
  end;
end;

function TRdcPasswordVault.SealAccount(const aTarget, aAccount, aPassword: string; const aHostKeys: TArray<string>): Boolean;
var
  lKey: TBytes;
  lPlain: TBytes;
begin
  if not IsUnlocked or (aPassword = '') then
    Exit(False);
  lKey := UseKey;
  lPlain := EncodeAccountPayload(aPassword, aHostKeys);
  try
    Result := WriteItem(lKey, aTarget, aAccount, SealBytes(lKey, aTarget, lPlain));
  finally
    WipeBytes(lPlain);
    ReleaseKey(lKey);
  end;
end;

function TRdcPasswordVault.SaveAccount(const aTarget, aAccount, aPassword: string; const aHosts: TArray<TRdcHostRef>): Boolean;
var
  lHost: TRdcHostRef;
  lKeys: TArray<string>;
  lOldPassword: string;
begin
  if not IsUnlocked or (aPassword = '') then
    Exit(False);
  if not OpenAccount(aTarget, lOldPassword, lKeys) then
    lKeys := [];
  WipeString(lOldPassword);
  for lHost in aHosts do
    if not ContainsKey(lKeys, lHost.Key) then
      lKeys := lKeys + [LowerCase(lHost.Key)];
  Result := SealAccount(aTarget, aAccount, aPassword, lKeys);
end;

function TRdcPasswordVault.MissingHosts(const aTarget: string; const aHosts: TArray<TRdcHostRef>): TArray<TRdcHostRef>;
var
  lHost: TRdcHostRef;
  lKeys: TArray<string>;
  lPassword: string;
begin
  Result := [];
  if not OpenAccount(aTarget, lPassword, lKeys) then
    Exit;
  WipeString(lPassword);
  for lHost in aHosts do
    if not ContainsKey(lKeys, lHost.Key) then
      Result := Result + [lHost];
end;

function TRdcPasswordVault.ApproveHosts(const aTarget, aAccount: string; const aHosts: TArray<TRdcHostRef>): Boolean;
var
  lHost: TRdcHostRef;
  lKeys: TArray<string>;
  lPassword: string;
begin
  if not OpenAccount(aTarget, lPassword, lKeys) then
    Exit(False);
  try
    for lHost in aHosts do
      if not ContainsKey(lKeys, lHost.Key) then
        lKeys := lKeys + [LowerCase(lHost.Key)];
    Result := SealAccount(aTarget, aAccount, lPassword, lKeys);
  finally
    WipeString(lPassword);
  end;
end;

function TRdcPasswordVault.LoadApproved(const aTarget, aAccount: string; const aHosts: TArray<TRdcHostRef>; const aAsk: TRdcApproveHostsFunc; out aPassword: string): TRdcLoadResult;
var
  lHost: TRdcHostRef;
  lKeys: TArray<string>;
  lMissing: TArray<TRdcHostRef>;
begin
  if not OpenAccount(aTarget, aPassword, lKeys) then
    Exit(rlrNone);
  // No host to bind to (e.g. a tailnet device without MagicDNS name): never released, the user types it.
  if Length(aHosts) = 0 then
  begin
    WipeString(aPassword);
    Exit(rlrDeclined);
  end;
  lMissing := [];
  for lHost in aHosts do
    if not ContainsKey(lKeys, lHost.Key) then
      lMissing := lMissing + [lHost];
  if Length(lMissing) = 0 then
    Exit(rlrLoaded);
  // Never without a question: a file can name any host for this account.
  if not Assigned(aAsk) or not aAsk(lMissing) then
  begin
    WipeString(aPassword);
    Exit(rlrDeclined);
  end;
  for lHost in lMissing do
    lKeys := lKeys + [LowerCase(lHost.Key)];
  SealAccount(aTarget, aAccount, aPassword, lKeys);
  Result := rlrLoaded;
end;

procedure TRdcPasswordVault.Delete(const aTarget: string);
begin
  FStore.Delete(aTarget);
end;

procedure TRdcPasswordVault.DeleteByPrefix(const aPrefix: string);
var
  lTarget: string;
begin
  // Alleen eigen items, en nooit de kluis zelf.
  if not aPrefix.StartsWith(cTargetPrefix, True) or (Length(aPrefix) <= Length(cTargetPrefix)) then
    Exit;
  for lTarget in FStore.Targets(aPrefix) do
    if lTarget.StartsWith(aPrefix, True) and not SameText(lTarget, cRdcVaultTarget) then
      FStore.Delete(lTarget);
end;

function TRdcPasswordVault.Count: Integer;
begin
  Result := Length(PasswordTargets);
end;

function TRdcPasswordVault.Reset: Integer;
var
  lTarget: string;
begin
  Lock;
  Result := 0;
  for lTarget in PasswordTargets do
  begin
    FStore.Delete(lTarget);
    Inc(Result);
  end;
  FStore.Delete(cRdcVaultTarget);
  DeleteStaged;
end;

function TRdcPasswordVault.ChangeMasterPassword(const aOldMasterPassword, aNewMasterPassword: string): Boolean;
const
  cWaitMs = 10000;
var
  lMutex: THandle;
  lWait: DWORD;
begin
  // One change at a time, and no recovery by another instance while it runs.
  FLastChangeResult := crStoreError;
  lMutex := OpenChangeMutex;
  if lMutex = 0 then
    Exit(False);
  try
    lWait := WaitForSingleObject(lMutex, cWaitMs);
    if not (lWait in [WAIT_OBJECT_0, WAIT_ABANDONED]) then
      Exit(False);
    try
      FLastChangeResult := DoChangeMasterPassword(aOldMasterPassword, aNewMasterPassword);
    finally
      ReleaseMutex(lMutex);
    end;
  finally
    CloseHandle(lMutex);
  end;
  Result := FLastChangeResult = crOk;
end;

function TRdcPasswordVault.DoChangeMasterPassword(const aOldMasterPassword, aNewMasterPassword: string): TRdcChangeResult;
var
  lCommitted: Boolean;
  lData: TBytes;
  lIndex: Integer;
  lNewKey: TBytes;
  lNewVault: TBytes;
  lOk: Boolean;
  lOldData: TArray<TBytes>;
  lOldKey: TBytes;
  lOldVault: TBytes;
  lPlain: TArray<TBytes>;
  lSalt: TBytes;
  lTargets: TArray<string>;
begin
  if not IsStrongEnough(aNewMasterPassword) or not DeriveAndCheck(aOldMasterPassword, lOldKey) then
    Exit(crWrongPassword);
  Result := crStoreError;
  lCommitted := False;
  try
    // Nothing is changed until everything is read and decrypted. An item that cannot be READ aborts (a store error
    // is not a reason to throw a password away); an item that cannot be DECRYPTED under the old key is worthless
    // and dropped after the commit.
    DeleteStaged;
    if not FStore.Read(cRdcVaultTarget, lOldVault) then
      Exit;
    lTargets := PasswordTargets;
    SetLength(lPlain, Length(lTargets));
    SetLength(lOldData, Length(lTargets));
    for lIndex := 0 to High(lTargets) do
    begin
      if not FStore.Read(lTargets[lIndex], lData) then
        Exit;
      lOldData[lIndex] := lData;
      if not OpenBytes(lOldKey, lTargets[lIndex], lData, lPlain[lIndex]) then
        lPlain[lIndex] := nil;
    end;
    lSalt := TRdcCrypto.RandomBytes(cRdcSaltSize);
    lNewKey := TRdcCrypto.DeriveKey(aNewMasterPassword, lSalt, FIterations);
    lNewVault := BuildVaultItem(lNewKey, lSalt, FIterations);

    // Phase 1: stage everything; any failed write leaves the vault as it was.
    lOk := True;
    for lIndex := 0 to High(lTargets) do
      if lOk and (lPlain[lIndex] <> nil) then
        lOk := FStore.Write(cStagingPrefix + lTargets[lIndex], 'RDCManagerX', SealBytes(lNewKey, lTargets[lIndex], lPlain[lIndex]));
    lOk := lOk and FStore.Write(cStagedVaultTarget, 'RDCManagerX', lNewVault);
    if not lOk then
      Exit;

    // Phase 2: the vault item switches to the new key (commit point), then the staged items replace the old ones.
    if not FStore.Write(cRdcVaultTarget, 'RDCManagerX', lNewVault) then
      Exit;
    lCommitted := True;
    if not CommitStaged then
    begin
      // Roll back: old items first, the old vault item last. If that fails too, the staging area stays and the next
      // start finishes the change (RecoverInterruptedChange), so the items always match one vault key.
      lOk := True;
      for lIndex := 0 to High(lTargets) do
        if lOldData[lIndex] <> nil then
          lOk := FStore.Write(lTargets[lIndex], 'RDCManagerX', lOldData[lIndex]) and lOk;
      if lOk and FStore.Write(cRdcVaultTarget, 'RDCManagerX', lOldVault) then
      begin
        DeleteStaged;
        Exit(crStoreError); // back as it was; the key in memory still matches
      end;
      // Store and memory no longer agree on the key: do not keep working with the old key.
      Lock;
      Exit(crInconsistent);
    end;
    for lIndex := 0 to High(lTargets) do
      if lPlain[lIndex] = nil then
        FStore.Delete(lTargets[lIndex]); // undecryptable under the old key: worthless
    SetKey(lNewKey);
    Result := crOk;
  finally
    if not lCommitted then
      DeleteStaged;
    for lIndex := 0 to High(lPlain) do
      WipeBytes(lPlain[lIndex]);
    WipeBytes(lOldKey);
    WipeBytes(lNewKey);
  end;
end;

end.
