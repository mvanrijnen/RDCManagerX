unit RdcmX.Tests.Vault;

{
  Tests voor RdcmX.Crypto (PBKDF2, AES-256-GCM) en de wachtwoordkluis (TRdcPasswordVault) met een opslag in het
  geheugen, zodat Windows Referentiebeheer niet geraakt wordt.
}

interface

uses
  System.Generics.Collections, System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Credentials, RdcmX.Crypto;

type
  TMemoryBlobStore = class(TInterfacedObject, IRdcBlobStore)
  private
    FItems: TDictionary<string, TBytes>;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(const aTarget: string; out aData: TBytes): Boolean;
    function Write(const aTarget, aUserName: string; const aData: TBytes): Boolean;
    procedure Delete(const aTarget: string);
    function Targets(const aPrefix: string): TArray<string>;
    function Contains(const aText: string): Boolean;
  end;

  [TestFixture]
  TVaultTests = class
  private
    FStore: TMemoryBlobStore;
    FStoreRef: IRdcBlobStore;
    FVault: TRdcPasswordVault;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Pbkdf2MatchesKnownVector;
    [Test]
    procedure GcmRoundTrip;
    [Test]
    procedure GcmDetectsTampering;
    [Test]
    procedure GcmChecksAssociatedData;
    [Test]
    procedure SaveAndLoadAfterUnlock;
    [Test]
    procedure WrongMasterPasswordIsRejected;
    [Test]
    procedure LockedVaultGivesNothing;
    [Test]
    procedure PasswordIsNotStoredInPlainText;
    [Test]
    procedure SwappedItemIsRejected;
    [Test]
    procedure ChangeMasterPasswordReencrypts;
    [Test]
    procedure ResetRemovesEverything;
    [Test]
    procedure WeakMasterPasswordIsRefused;
  end;

implementation

const
  cIterations = 1000; // snel in tests; de app gebruikt de standaard (600000)
  cMaster = 'Correct-Paard-Batterij';
  cTargetA = 'RDCManagerX:account:corp\beheer';
  cTargetB = 'RDCManagerX:server:srv01:admin';

function HexOf(const aBytes: TBytes): string;
var
  lByte: Byte;
begin
  Result := '';
  for lByte in aBytes do
    Result := Result + IntToHex(lByte, 2);
  Result := LowerCase(Result);
end;

{ TMemoryBlobStore }

constructor TMemoryBlobStore.Create;
begin
  inherited Create;
  FItems := TDictionary<string, TBytes>.Create;
end;

destructor TMemoryBlobStore.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TMemoryBlobStore.Read(const aTarget: string; out aData: TBytes): Boolean;
begin
  Result := FItems.TryGetValue(LowerCase(aTarget), aData);
  if Result then
    aData := Copy(aData);
end;

function TMemoryBlobStore.Write(const aTarget, aUserName: string; const aData: TBytes): Boolean;
begin
  FItems.AddOrSetValue(LowerCase(aTarget), Copy(aData));
  Result := True;
end;

procedure TMemoryBlobStore.Delete(const aTarget: string);
begin
  FItems.Remove(LowerCase(aTarget));
end;

function TMemoryBlobStore.Targets(const aPrefix: string): TArray<string>;
var
  lKey: string;
begin
  Result := nil;
  for lKey in FItems.Keys do
    if lKey.StartsWith(LowerCase(aPrefix)) then
      Result := Result + [lKey];
end;

function TMemoryBlobStore.Contains(const aText: string): Boolean;
var
  lData: TBytes;
  lHex: string;
begin
  Result := False;
  for lData in FItems.Values do
  begin
    lHex := HexOf(lData);
    Result := Result or lHex.Contains(HexOf(TEncoding.UTF8.GetBytes(aText))) or lHex.Contains(HexOf(TEncoding.Unicode.GetBytes(aText)));
  end;
end;

{ TVaultTests }

procedure TVaultTests.Setup;
begin
  FStore := TMemoryBlobStore.Create;
  FStoreRef := FStore;
  FVault := TRdcPasswordVault.Create(FStoreRef, cIterations);
end;

procedure TVaultTests.TearDown;
begin
  FreeAndNil(FVault);
  FStoreRef := nil;
  FStore := nil;
end;

procedure TVaultTests.Pbkdf2MatchesKnownVector;
begin
  // Bekende PBKDF2-HMAC-SHA256-vectoren: P="password", S="salt", dkLen=32, c=1 en c=4096.
  Assert.AreEqual('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b', HexOf(TRdcCrypto.DeriveKey('password', TEncoding.ASCII.GetBytes('salt'), 1, 32)));
  Assert.AreEqual('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a', HexOf(TRdcCrypto.DeriveKey('password', TEncoding.ASCII.GetBytes('salt'), 4096, 32)));
end;

procedure TVaultTests.GcmRoundTrip;
var
  lKey: TBytes;
  lPlain: TBytes;
  lSealed: TBytes;
begin
  lKey := TRdcCrypto.RandomBytes(cRdcKeySize);
  lSealed := TRdcCrypto.Encrypt(lKey, TEncoding.UTF8.GetBytes('geheim'), TEncoding.UTF8.GetBytes('aad'));
  Assert.AreEqual(Integer(cRdcNonceSize + cRdcTagSize + 6), Integer(Length(lSealed)));
  Assert.IsTrue(TRdcCrypto.TryDecrypt(lKey, lSealed, TEncoding.UTF8.GetBytes('aad'), lPlain));
  Assert.AreEqual('geheim', TEncoding.UTF8.GetString(lPlain));
  // Zelfde invoer, andere nonce: andere uitvoer.
  Assert.AreNotEqual(HexOf(lSealed), HexOf(TRdcCrypto.Encrypt(lKey, TEncoding.UTF8.GetBytes('geheim'), TEncoding.UTF8.GetBytes('aad'))));
end;

procedure TVaultTests.GcmDetectsTampering;
var
  lIndex: Integer;
  lKey: TBytes;
  lPlain: TBytes;
  lSealed: TBytes;
  lTampered: TBytes;
begin
  lKey := TRdcCrypto.RandomBytes(cRdcKeySize);
  lSealed := TRdcCrypto.Encrypt(lKey, TEncoding.UTF8.GetBytes('geheim'), nil);
  // Elke byte (nonce, tag of cijfertekst) omklappen moet de controle laten falen.
  for lIndex := 0 to High(lSealed) do
  begin
    lTampered := Copy(lSealed);
    lTampered[lIndex] := lTampered[lIndex] xor $01;
    Assert.IsFalse(TRdcCrypto.TryDecrypt(lKey, lTampered, nil, lPlain), Format('byte %d', [lIndex]));
  end;
  Assert.IsFalse(TRdcCrypto.TryDecrypt(TRdcCrypto.RandomBytes(cRdcKeySize), lSealed, nil, lPlain), 'andere sleutel');
  Assert.IsFalse(TRdcCrypto.TryDecrypt(lKey, Copy(lSealed, 0, 10), nil, lPlain), 'te kort');
end;

procedure TVaultTests.GcmChecksAssociatedData;
var
  lKey: TBytes;
  lPlain: TBytes;
  lSealed: TBytes;
begin
  lKey := TRdcCrypto.RandomBytes(cRdcKeySize);
  lSealed := TRdcCrypto.Encrypt(lKey, TEncoding.UTF8.GetBytes('geheim'), TEncoding.UTF8.GetBytes('doel-a'));
  Assert.IsFalse(TRdcCrypto.TryDecrypt(lKey, lSealed, TEncoding.UTF8.GetBytes('doel-b'), lPlain));
end;

procedure TVaultTests.SaveAndLoadAfterUnlock;
var
  lPassword: string;
  lVault: TRdcPasswordVault;
begin
  Assert.IsFalse(FVault.IsInitialized);
  Assert.IsTrue(FVault.Initialize(cMaster));
  Assert.IsTrue(FVault.IsUnlocked);
  Assert.IsTrue(FVault.Save(cTargetA, 'corp\beheer', 'S3cret!'));
  Assert.IsTrue(FVault.HasPassword(cTargetA));
  Assert.IsFalse(FVault.HasPassword(cTargetB));
  Assert.AreEqual(Integer(1), FVault.Count);
  // Nieuwe instantie (nieuwe app-start): eerst ontgrendelen.
  lVault := TRdcPasswordVault.Create(FStoreRef, cIterations);
  try
    Assert.IsTrue(lVault.IsInitialized);
    Assert.IsFalse(lVault.IsUnlocked);
    Assert.IsTrue(lVault.Unlock(cMaster));
    Assert.IsTrue(lVault.TryLoad(cTargetA, lPassword));
    Assert.AreEqual('S3cret!', lPassword);
  finally
    lVault.Free;
  end;
end;

procedure TVaultTests.WrongMasterPasswordIsRejected;
begin
  FVault.Initialize(cMaster);
  FVault.Lock;
  Assert.IsFalse(FVault.Unlock('Verkeerd-wachtwoord'));
  Assert.IsFalse(FVault.IsUnlocked);
  Assert.IsTrue(FVault.Unlock(cMaster));
end;

procedure TVaultTests.LockedVaultGivesNothing;
var
  lPassword: string;
begin
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  FVault.Lock;
  Assert.IsFalse(FVault.TryLoad(cTargetA, lPassword));
  Assert.AreEqual('', lPassword);
  Assert.IsFalse(FVault.Save(cTargetB, 'admin', 'x'));
  Assert.IsTrue(FVault.HasPassword(cTargetA), 'bestaan is zonder ontgrendelen te zien');
end;

procedure TVaultTests.PasswordIsNotStoredInPlainText;
begin
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'Herkenbaar-Wachtwoord-123');
  Assert.IsFalse(FStore.Contains('Herkenbaar-Wachtwoord-123'));
  Assert.IsFalse(FStore.Contains(cMaster));
end;

procedure TVaultTests.SwappedItemIsRejected;
var
  lData: TBytes;
  lPassword: string;
begin
  // Item van account A onder de naam van B zetten: de doelnaam zit als AAD in de versleuteling.
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  FStore.Read(cTargetA, lData);
  FStore.Write(cTargetB, 'admin', lData);
  Assert.IsFalse(FVault.TryLoad(cTargetB, lPassword));
  Assert.IsTrue(FVault.TryLoad(cTargetA, lPassword));
end;

procedure TVaultTests.ChangeMasterPasswordReencrypts;
var
  lPassword: string;
  lVault: TRdcPasswordVault;
begin
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  FVault.Save(cTargetB, 'admin', 'Ander!');
  Assert.IsFalse(FVault.ChangeMasterPassword('Verkeerd-wachtwoord', 'Nieuw-Hoofdwachtwoord'));
  Assert.IsTrue(FVault.ChangeMasterPassword(cMaster, 'Nieuw-Hoofdwachtwoord'));
  lVault := TRdcPasswordVault.Create(FStoreRef, cIterations);
  try
    Assert.IsFalse(lVault.Unlock(cMaster));
    Assert.IsTrue(lVault.Unlock('Nieuw-Hoofdwachtwoord'));
    Assert.IsTrue(lVault.TryLoad(cTargetA, lPassword));
    Assert.AreEqual('S3cret!', lPassword);
    Assert.IsTrue(lVault.TryLoad(cTargetB, lPassword));
    Assert.AreEqual('Ander!', lPassword);
  finally
    lVault.Free;
  end;
end;

procedure TVaultTests.ResetRemovesEverything;
begin
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  FVault.Save(cTargetB, 'admin', 'Ander!');
  Assert.AreEqual(Integer(2), FVault.Reset);
  Assert.IsFalse(FVault.IsInitialized);
  Assert.IsFalse(FVault.IsUnlocked);
  Assert.AreEqual(0, Integer(Length(FStore.Targets(''))));
end;

procedure TVaultTests.WeakMasterPasswordIsRefused;
begin
  Assert.IsFalse(TRdcPasswordVault.IsStrongEnough('kort'));
  Assert.IsFalse(FVault.Initialize('kort'));
  Assert.IsFalse(FVault.IsInitialized);
end;

initialization
  TDUnitX.RegisterTestFixture(TVaultTests);

end.
