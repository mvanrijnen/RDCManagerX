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
  - 'RDCManagerX:tailnet:<id>:authkey' / ':statekey' en 'RDCManagerX:gateway:<id>': zelfde formaat, voor de auth key
    en state-sleutel van een Tailscale-netwerk en het wachtwoord van een gateway. Vallen onder hetzelfde
    hoofdwachtwoord (opnieuw versleutelen, kluis legen).
}

interface

uses
  Winapi.Windows,
  System.SysUtils;

const
  cRdcVaultTarget = 'RDCManagerX:vault';
  cRdcMinMasterPasswordLength = 10;

type
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
    function DeriveAndCheck(const aMasterPassword: string; out aKey: TBytes): Boolean;
    function WriteVaultItem(const aKey: TBytes; const aSalt: TBytes; aIterations: Cardinal): Boolean;
    function SealPassword(const aKey: TBytes; const aTarget, aPassword: string): TBytes;
    function OpenPassword(const aKey: TBytes; const aTarget: string; const aData: TBytes; out aPassword: string): Boolean;
    function PasswordTargets: TArray<string>;
    function UseKey: TBytes;
    procedure ReleaseKey(var aKey: TBytes);
    procedure SetKey(var aKey: TBytes);
  public
    /// <summary>aIterations: PBKDF2-rondes voor een NIEUWE kluis (tests gebruiken minder).</summary>
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
    class function GatewayTarget(const aGatewayId, aGatewayAddress: string): string; static;
    class function GatewayTargetPrefix(const aGatewayId: string): string; static;
    /// <summary>Control URL zoals die voor de binding telt (kleine letters, zonder / aan het eind; leeg = Tailscale).</summary>
    class function NormalizeControlUrl(const aControlUrl: string): string; static;
    /// <summary>Heeft het hoofdwachtwoord voldoende lengte?</summary>
    class function IsStrongEnough(const aMasterPassword: string): Boolean; static;
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
    procedure Delete(const aTarget: string);
    /// <summary>Alle items waarvan de doelnaam met aPrefix begint (nooit de kluis zelf).</summary>
    procedure DeleteByPrefix(const aPrefix: string);
    /// <summary>Aantal onthouden wachtwoorden.</summary>
    function Count: Integer;
    /// <summary>Kluis en alle wachtwoorden verwijderen; vergrendelt. Geeft het aantal verwijderde wachtwoorden.</summary>
    function Reset: Integer;
    /// <summary>Alle wachtwoorden opnieuw versleutelen met een nieuw hoofdwachtwoord. False bij een verkeerd oud hoofdwachtwoord.</summary>
    function ChangeMasterPassword(const aOldMasterPassword, aNewMasterPassword: string): Boolean;
    /// <summary>Tijdstip van het laatste gebruik (voor automatisch vergrendelen).</summary>
    property LastUse: TDateTime read FLastUse;
  end;

/// <summary>Inhoud van een string (bijv. een wachtwoord) overschrijven en de string leegmaken.</summary>
procedure WipeString(var aValue: string);

implementation

uses
  System.Hash,
  RdcmX.Crypto;

const
  CRED_TYPE_GENERIC = 1;
  CRED_PERSIST_LOCAL_MACHINE = 2;
  cTargetPrefix = 'RDCManagerX:';
  cComment = 'RDCManagerX (versleuteld met hoofdwachtwoord)';
  cFormatVersion = 1;
  cVaultIterations = 600000; // PBKDF2-HMAC-SHA256, OWASP-advies
  cVaultCheckText = 'RDCManagerX-kluis-v1';

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

constructor TRdcPasswordVault.Create(const aStore: IRdcBlobStore; aIterations: Cardinal);
begin
  inherited Create;
  FStore := aStore;
  if aIterations = 0 then
    FIterations := cVaultIterations
  else
    FIterations := aIterations;
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

class function TRdcPasswordVault.IsStrongEnough(const aMasterPassword: string): Boolean;
begin
  Result := Length(aMasterPassword) >= cRdcMinMasterPasswordLength;
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

function TRdcPasswordVault.WriteVaultItem(const aKey: TBytes; const aSalt: TBytes; aIterations: Cardinal): Boolean;
var
  lData: TBytes;
  lSealed: TBytes;
begin
  lSealed := TRdcCrypto.Encrypt(aKey, Utf8(cVaultCheckText), Utf8(cRdcVaultTarget));
  SetLength(lData, 1 + SizeOf(Cardinal) + cRdcSaltSize + Length(lSealed));
  lData[0] := cFormatVersion;
  Move(aIterations, lData[1], SizeOf(Cardinal));
  Move(aSalt[0], lData[1 + SizeOf(Cardinal)], cRdcSaltSize);
  Move(lSealed[0], lData[1 + SizeOf(Cardinal) + cRdcSaltSize], Length(lSealed));
  Result := FStore.Write(cRdcVaultTarget, 'RDCManagerX', lData);
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

function TRdcPasswordVault.SealPassword(const aKey: TBytes; const aTarget, aPassword: string): TBytes;
var
  lPlain: TBytes;
  lSealed: TBytes;
begin
  lPlain := Utf8(aPassword);
  try
    lSealed := TRdcCrypto.Encrypt(aKey, lPlain, TargetAad(aTarget));
  finally
    WipeBytes(lPlain);
  end;
  SetLength(Result, 1 + Length(lSealed));
  Result[0] := cFormatVersion;
  Move(lSealed[0], Result[1], Length(lSealed));
end;

function TRdcPasswordVault.OpenPassword(const aKey: TBytes; const aTarget: string; const aData: TBytes; out aPassword: string): Boolean;
var
  lPlain: TBytes;
begin
  aPassword := '';
  Result := (Length(aData) > 1) and (aData[0] = cFormatVersion) and TRdcCrypto.TryDecrypt(aKey, Copy(aData, 1, MaxInt), TargetAad(aTarget), lPlain);
  if Result then
  begin
    aPassword := TEncoding.UTF8.GetString(lPlain);
    WipeBytes(lPlain);
    Result := aPassword <> '';
  end;
end;

function TRdcPasswordVault.PasswordTargets: TArray<string>;
var
  lTarget: string;
begin
  Result := [];
  for lTarget in FStore.Targets(cTargetPrefix) do
    if not SameText(lTarget, cRdcVaultTarget) then
      Result := Result + [lTarget];
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
    Result := FStore.Write(aTarget, aAccount, SealPassword(lKey, aTarget, aPassword));
  finally
    ReleaseKey(lKey);
  end;
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
end;

function TRdcPasswordVault.ChangeMasterPassword(const aOldMasterPassword, aNewMasterPassword: string): Boolean;
var
  lData: TBytes;
  lNewKey: TBytes;
  lOldKey: TBytes;
  lPassword: string;
  lSalt: TBytes;
  lTarget: string;
  lTargets: TArray<string>;
  lPasswords: TArray<string>;
  lIndex: Integer;
begin
  if not IsStrongEnough(aNewMasterPassword) or not DeriveAndCheck(aOldMasterPassword, lOldKey) then
    Exit(False);
  try
    // Eerst alles ontsleutelen (niets wijzigen als dat niet lukt), dan met de nieuwe sleutel terugschrijven.
    lTargets := PasswordTargets;
    SetLength(lPasswords, Length(lTargets));
    for lIndex := 0 to High(lTargets) do
    begin
      lTarget := lTargets[lIndex];
      if FStore.Read(lTarget, lData) and OpenPassword(lOldKey, lTarget, lData, lPassword) then
        lPasswords[lIndex] := lPassword
      else
        lPasswords[lIndex] := ''; // onleesbaar item: vervalt
      WipeString(lPassword);
      WipeBytes(lData);
    end;
    lSalt := TRdcCrypto.RandomBytes(cRdcSaltSize);
    lNewKey := TRdcCrypto.DeriveKey(aNewMasterPassword, lSalt, FIterations);
    Result := WriteVaultItem(lNewKey, lSalt, FIterations);
    if Result then
    begin
      for lIndex := 0 to High(lTargets) do
        if lPasswords[lIndex] <> '' then
          FStore.Write(lTargets[lIndex], 'RDCManagerX', SealPassword(lNewKey, lTargets[lIndex], lPasswords[lIndex]))
        else
          FStore.Delete(lTargets[lIndex]);
      SetKey(lNewKey);
    end;
  finally
    for lIndex := 0 to High(lPasswords) do
      WipeString(lPasswords[lIndex]);
    WipeBytes(lOldKey);
    WipeBytes(lNewKey);
  end;
end;

end.
