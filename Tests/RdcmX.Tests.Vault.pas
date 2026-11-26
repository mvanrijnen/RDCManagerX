unit RdcmX.Tests.Vault;

{
  Tests voor RdcmX.Crypto (PBKDF2, AES-256-GCM) en de wachtwoordkluis (TRdcPasswordVault) met een opslag in het
  geheugen, zodat Windows Referentiebeheer niet geraakt wordt.
}

interface

uses
  Winapi.Windows,
  System.Classes, System.Generics.Collections, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Credentials, RdcmX.Crypto, RdcmX.Model;

type
  TMemoryBlobStore = class(TInterfacedObject, IRdcBlobStore)
  private
    FItems: TDictionary<string, TBytes>;
    FWriteCount: Integer;
  public
    /// <summary>Write number FailAt (1-based, 0 = never) fails: returns False, or raises when FailRaises
    /// (simulates a crash halfway).</summary>
    FailAt: Integer;
    FailRaises: Boolean;
    /// <summary>Further write numbers that fail (returns False).</summary>
    FailAlso: TArray<Integer>;
    /// <summary>Reads of this target fail (lower case).</summary>
    FailReadTarget: string;
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
    procedure ChangeMasterPasswordFailedWriteChangesNothing;
    [Test]
    procedure ChangeMasterPasswordCrashIsRecovered;
    [Test]
    procedure NewHostAsksAndDeclineGivesNothing;
    [Test]
    procedure ApprovedHostDoesNotAsk;
    [Test]
    procedure OldItemAsksPerHost;
    [Test]
    procedure OnlyMissingHostsAreAsked;
    [Test]
    procedure HostKeysAreBoundToRouteAndTailnet;
    [Test]
    procedure ApprovalsSurviveMasterPasswordChange;
    [Test]
    procedure AuthenticationLevelIsForcedForVaultPasswords;
    [Test]
    procedure ReadErrorAbortsChange;
    [Test]
    procedure FailedRollbackLocksVault;
    [Test]
    procedure RecoveryWaitsForRunningChange;
    [Test]
    procedure SameHostViaUnknownGatewayAsks;
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
  if (FailReadTarget <> '') and SameText(aTarget, FailReadTarget) then
  begin
    aData := nil;
    Exit(False);
  end;
  Result := FItems.TryGetValue(LowerCase(aTarget), aData);
  if Result then
    aData := Copy(aData);
end;

function TMemoryBlobStore.Write(const aTarget, aUserName: string; const aData: TBytes): Boolean;
begin
  Inc(FWriteCount);
  if (FailAt > 0) and (FWriteCount = FailAt) then
  begin
    if FailRaises then
      raise EAbort.Create('simulated crash');
    Exit(False);
  end;
  for var lFail in FailAlso do
    if lFail = FWriteCount then
      Exit(False);
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

function MasterThatOpensAll(const aStore: IRdcBlobStore): string;
var
  lA: string;
  lB: string;
  lMaster: string;
  lVault: TRdcPasswordVault;
begin
  // Which master password opens the vault AND both items? '' = none (items and vault key out of step).
  Result := '';
  lVault := TRdcPasswordVault.Create(aStore, cIterations); // also runs the recovery of an interrupted change
  try
    for lMaster in [cMaster, 'Nieuw-Hoofdwachtwoord'] do
      if lVault.Unlock(lMaster) and lVault.TryLoad(cTargetA, lA) and lVault.TryLoad(cTargetB, lB) and (lA = 'S3cret!') and (lB = 'Ander!') then
        Exit(lMaster);
  finally
    lVault.Free;
  end;
end;

procedure TVaultTests.ChangeMasterPasswordFailedWriteChangesNothing;
var
  lFailAt: Integer;
  lStore: TMemoryBlobStore;
  lStoreRef: IRdcBlobStore;
  lVault: TRdcPasswordVault;
begin
  // Two items: 2 staged writes + staged vault + vault + 2 copies = 6 writes. Each one failing must leave the old
  // master password working for everything, with no staging leftovers; a 7th never happens, so that one succeeds.
  for lFailAt := 1 to 7 do
  begin
    lStore := TMemoryBlobStore.Create;
    lStoreRef := lStore;
    lVault := TRdcPasswordVault.Create(lStoreRef, cIterations);
    try
      lVault.Initialize(cMaster);
      lVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
      lVault.Save(cTargetB, 'admin', 'Ander!');
      lStore.FWriteCount := 0;
      lStore.FailAt := lFailAt;
      Assert.AreEqual(lFailAt = 7, lVault.ChangeMasterPassword(cMaster, 'Nieuw-Hoofdwachtwoord'), Format('write %d', [lFailAt]));
      lStore.FailAt := 0;
      Assert.AreEqual(Integer(0), Integer(Length(lStore.Targets('RDCManagerX:~'))), Format('staging left after write %d', [lFailAt]));
      if lFailAt = 7 then
        Assert.AreEqual('Nieuw-Hoofdwachtwoord', MasterThatOpensAll(lStoreRef))
      else
        Assert.AreEqual(cMaster, MasterThatOpensAll(lStoreRef), Format('write %d', [lFailAt]));
    finally
      lVault.Free;
    end;
  end;
end;

procedure TVaultTests.ChangeMasterPasswordCrashIsRecovered;
var
  lFailAt: Integer;
  lStore: TMemoryBlobStore;
  lStoreRef: IRdcBlobStore;
  lVault: TRdcPasswordVault;
begin
  // A crash at any write: after the next start (recovery in the constructor) one of the two master passwords opens
  // the vault and every item. Up to and including the vault write the old one, after it the new one.
  for lFailAt := 1 to 6 do
  begin
    lStore := TMemoryBlobStore.Create;
    lStoreRef := lStore;
    lVault := TRdcPasswordVault.Create(lStoreRef, cIterations);
    try
      lVault.Initialize(cMaster);
      lVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
      lVault.Save(cTargetB, 'admin', 'Ander!');
      lStore.FWriteCount := 0;
      lStore.FailAt := lFailAt;
      lStore.FailRaises := True;
      Assert.WillRaise(procedure begin lVault.ChangeMasterPassword(cMaster, 'Nieuw-Hoofdwachtwoord'); end, EAbort);
    finally
      lVault.Free;
    end;
    lStore.FailAt := 0;
    if lFailAt <= 4 then
      Assert.AreEqual(cMaster, MasterThatOpensAll(lStoreRef), Format('crash at write %d', [lFailAt]))
    else
      Assert.AreEqual('Nieuw-Hoofdwachtwoord', MasterThatOpensAll(lStoreRef), Format('crash at write %d', [lFailAt]));
    Assert.AreEqual(Integer(0), Integer(Length(lStore.Targets('RDCManagerX:~'))), Format('staging left after crash at write %d', [lFailAt]));
  end;
end;

function HostA: TRdcHostRef;
begin
  Result := TRdcHostRef.Create(TRdcPasswordVault.DirectHostKey('srv01.corp.local'), 'srv01.corp.local');
end;

function HostB: TRdcHostRef;
begin
  Result := TRdcHostRef.Create(TRdcPasswordVault.DirectHostKey('rdp.aanvaller.tld'), 'rdp.aanvaller.tld');
end;

procedure TVaultTests.NewHostAsksAndDeclineGivesNothing;
var
  lAsked: Integer;
  lPassword: string;
  lAnswer: Boolean;
  lAsk: TRdcApproveHostsFunc;
begin
  FVault.Initialize(cMaster);
  Assert.IsTrue(FVault.SaveAccount(cTargetA, 'corp\beheer', 'S3cret!', [HostA]));
  lAsked := 0;
  lAnswer := False;
  lAsk := function(const aMissing: TArray<TRdcHostRef>): Boolean
    begin
      Inc(lAsked);
      Assert.AreEqual(Integer(1), Integer(Length(aMissing)));
      Assert.AreEqual(HostB.Key, aMissing[0].Key);
      Result := lAnswer;
    end;
  // A file pointing the same account at another host: asked, and No gives no password.
  Assert.AreEqual(rlrDeclined, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostB], lAsk, lPassword));
  Assert.AreEqual('', lPassword);
  Assert.AreEqual(1, lAsked);
  // Declining is not remembered as approval: asked again next time; Yes gives the password and is remembered.
  lAnswer := True;
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostB], lAsk, lPassword));
  Assert.AreEqual('S3cret!', lPassword);
  Assert.AreEqual(2, lAsked);
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostB], lAsk, lPassword));
  Assert.AreEqual(2, lAsked, 'approved host asked again');
  // Without a question callback a new host is never approved.
  Assert.AreEqual(rlrDeclined, FVault.LoadApproved(cTargetA, 'corp\beheer', [TRdcHostRef.Create('host:x', 'x')], nil, lPassword));
end;

procedure TVaultTests.ApprovedHostDoesNotAsk;
var
  lPassword: string;
begin
  FVault.Initialize(cMaster);
  FVault.SaveAccount(cTargetA, 'corp\beheer', 'S3cret!', [HostA]);
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostA],
    function(const aMissing: TArray<TRdcHostRef>): Boolean
    begin
      Assert.Fail('asked for an approved host');
      Result := False;
    end, lPassword));
  Assert.AreEqual('S3cret!', lPassword);
  // Case and spaces in the host name do not matter.
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [TRdcHostRef.Create(TRdcPasswordVault.DirectHostKey(' SRV01.Corp.Local '), '')], nil, lPassword));
  // Nothing stored or vault locked: rlrNone.
  Assert.AreEqual(rlrNone, FVault.LoadApproved(cTargetB, 'admin', [HostA], nil, lPassword));
  FVault.Lock;
  Assert.AreEqual(rlrNone, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostA], nil, lPassword));
end;

procedure TVaultTests.OldItemAsksPerHost;
var
  lAsked: Integer;
  lPassword: string;
begin
  // An item from before the host binding (plain password): still loadable, but every host is new.
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  Assert.IsTrue(FVault.TryLoad(cTargetA, lPassword));
  Assert.AreEqual('S3cret!', lPassword);
  Assert.AreEqual(Integer(1), Integer(Length(FVault.MissingHosts(cTargetA, [HostA]))));
  lAsked := 0;
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostA],
    function(const aMissing: TArray<TRdcHostRef>): Boolean
    begin
      Inc(lAsked);
      Result := True;
    end, lPassword));
  Assert.AreEqual(1, lAsked);
  Assert.AreEqual('S3cret!', lPassword);
  Assert.AreEqual(Integer(0), Integer(Length(FVault.MissingHosts(cTargetA, [HostA]))));
  Assert.IsTrue(FVault.TryLoad(cTargetA, lPassword), 'TryLoad reads the new format too');
  Assert.AreEqual('S3cret!', lPassword);
  Assert.IsFalse(FStore.Contains('S3cret!'));
end;

procedure TVaultTests.OnlyMissingHostsAreAsked;
var
  lGateway: TRdcHostRef;
  lPassword: string;
begin
  // Server approved, gateway with credSharing not: only the gateway is asked.
  FVault.Initialize(cMaster);
  FVault.SaveAccount(cTargetA, 'corp\beheer', 'S3cret!', [HostA]);
  lGateway := TRdcHostRef.Create(TRdcPasswordVault.ViaGatewayHostKey('gw.aanvaller.tld:443', 'srv01.corp.local'), 'gw');
  Assert.AreEqual(rlrDeclined, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostA, lGateway],
    function(const aMissing: TArray<TRdcHostRef>): Boolean
    begin
      Assert.AreEqual(Integer(1), Integer(Length(aMissing)));
      Assert.AreEqual(lGateway.Key, aMissing[0].Key);
      Result := False;
    end, lPassword));
  Assert.AreEqual('', lPassword);
  // ApproveHosts (group connect: one question for all) approves without loading.
  Assert.IsTrue(FVault.ApproveHosts(cTargetA, 'corp\beheer', [lGateway]));
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [HostA, lGateway], nil, lPassword));
end;

procedure TVaultTests.HostKeysAreBoundToRouteAndTailnet;
begin
  // The same name directly, in another tailnet (control URL) or as a gateway: all different approvals.
  // Tailnet: bound to the tailnet's MagicDNS suffix and the device's MagicDNS name (two tailnets on the same control
  // server with the same device name are different hosts).
  Assert.AreNotEqual(TRdcPasswordVault.DirectHostKey('srv.tail1234.ts.net'), TRdcPasswordVault.TailnetHostKey('tail1234.ts.net', 'srv.tail1234.ts.net'));
  Assert.AreNotEqual(TRdcPasswordVault.TailnetHostKey('tail1234.ts.net', 'srv.tail1234.ts.net'), TRdcPasswordVault.TailnetHostKey('tail9999.ts.net', 'srv.tail9999.ts.net'));
  Assert.AreEqual(TRdcPasswordVault.TailnetHostKey('Tail1234.ts.net.', 'SRV.tail1234.ts.net.'), TRdcPasswordVault.TailnetHostKey('tail1234.ts.net', 'srv.tail1234.ts.net'));
  Assert.IsTrue(TRdcPasswordVault.TailnetHostKey('tail1234.ts.net', 'srv.tail1234.ts.net').StartsWith('ts2:'), 'old ts: approvals do not match');
  Assert.AreNotEqual(TRdcPasswordVault.DirectHostKey('srv01'), TRdcPasswordVault.ViaGatewayHostKey('gw.corp.local', 'srv01'));
  Assert.AreNotEqual(TRdcPasswordVault.ViaGatewayHostKey('gw.corp.local', 'srv01'), TRdcPasswordVault.ViaGatewayHostKey('gw.evil.tld', 'srv01'));
  Assert.AreNotEqual(TRdcPasswordVault.ViaGatewayHostKey('gw.corp.local', 'srv01'), TRdcPasswordVault.ViaGatewayHostKey('gw.corp.local', 'srv02'));
end;

procedure TVaultTests.ApprovalsSurviveMasterPasswordChange;
var
  lPassword: string;
  lVault: TRdcPasswordVault;
begin
  FVault.Initialize(cMaster);
  FVault.SaveAccount(cTargetA, 'corp\beheer', 'S3cret!', [HostA]);
  Assert.IsTrue(FVault.ChangeMasterPassword(cMaster, 'Nieuw-Hoofdwachtwoord'));
  lVault := TRdcPasswordVault.Create(FStoreRef, cIterations);
  try
    Assert.IsTrue(lVault.Unlock('Nieuw-Hoofdwachtwoord'));
    Assert.AreEqual(rlrLoaded, lVault.LoadApproved(cTargetA, 'corp\beheer', [HostA], nil, lPassword));
    Assert.AreEqual('S3cret!', lPassword);
  finally
    lVault.Free;
  end;
end;

procedure TVaultTests.AuthenticationLevelIsForcedForVaultPasswords;
begin
  // 0 = connect without warning: never with a vault password; 1 (required) and 2 (warn) stay.
  // Direct and Gateway with a vault password: always 1 (required), whatever the file says.
  Assert.AreEqual(Cardinal(1), TRdcPasswordVault.AuthenticationLevelFor(0, True, rkDirect));
  Assert.AreEqual(Cardinal(1), TRdcPasswordVault.AuthenticationLevelFor(2, True, rkDirect));
  Assert.AreEqual(Cardinal(1), TRdcPasswordVault.AuthenticationLevelFor(0, True, rkGateway));
  Assert.AreEqual(Cardinal(1), TRdcPasswordVault.AuthenticationLevelFor(2, True, rkGateway));
  // Tailscale (127.0.0.2, name never matches): at least 2.
  Assert.AreEqual(Cardinal(2), TRdcPasswordVault.AuthenticationLevelFor(0, True, rkTailscale));
  Assert.AreEqual(Cardinal(1), TRdcPasswordVault.AuthenticationLevelFor(1, True, rkTailscale));
  Assert.AreEqual(Cardinal(2), TRdcPasswordVault.AuthenticationLevelFor(2, True, rkTailscale));
  // Typed password: as in the file, for every route.
  Assert.AreEqual(Cardinal(0), TRdcPasswordVault.AuthenticationLevelFor(0, False, rkDirect));
  Assert.AreEqual(Cardinal(0), TRdcPasswordVault.AuthenticationLevelFor(0, False, rkTailscale));
end;

procedure TVaultTests.ReadErrorAbortsChange;
begin
  // A transient read error must not count as "undecryptable" (which would delete the item after the commit).
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  FVault.Save(cTargetB, 'admin', 'Ander!');
  FStore.FailReadTarget := LowerCase(cTargetB);
  Assert.IsFalse(FVault.ChangeMasterPassword(cMaster, 'Nieuw-Hoofdwachtwoord'));
  Assert.AreEqual(Ord(crStoreError), Ord(FVault.LastChangeResult));
  FStore.FailReadTarget := '';
  Assert.AreEqual(cMaster, MasterThatOpensAll(FStoreRef));
  Assert.IsTrue(FVault.IsUnlocked, 'nothing changed: still unlocked with the old key');
end;

procedure TVaultTests.FailedRollbackLocksVault;
begin
  // Writes: stage A, stage B, staged vault, vault (commit), copy A, copy B, rollback A, rollback B, old vault.
  FVault.Initialize(cMaster);
  FVault.Save(cTargetA, 'corp\beheer', 'S3cret!');
  FVault.Save(cTargetB, 'admin', 'Ander!');
  FStore.FWriteCount := 0;
  FStore.FailAt := 5;           // copy A fails
  FStore.FailAlso := [9];       // and restoring the old vault item fails
  Assert.IsFalse(FVault.ChangeMasterPassword(cMaster, 'Nieuw-Hoofdwachtwoord'));
  Assert.AreEqual(Ord(crInconsistent), Ord(FVault.LastChangeResult));
  Assert.IsFalse(FVault.IsUnlocked, 'locked: memory and store disagree');
  FStore.FailAt := 0;
  FStore.FailAlso := [];
  // The next start finishes the change: one master password opens everything.
  Assert.AreEqual('Nieuw-Hoofdwachtwoord', MasterThatOpensAll(FStoreRef));
end;

procedure TVaultTests.RecoveryWaitsForRunningChange;
var
  lHeld: TEvent;
  lRelease: TEvent;
  lThread: TThread;
  lVault: TRdcPasswordVault;
begin
  // Another instance holds the change mutex (phase 1: staged items, no staged vault item yet). A starting instance
  // must not clean up that staging area; once the mutex is free, leftovers are removed.
  TRdcPasswordVault.ChangeMutexName := 'Local\RDCManagerX.VaultChange.Test.' + IntToStr(GetCurrentProcessId);
  FStore.Write('RDCManagerX:~staging:' + cTargetA, 'x', TBytes.Create(1, 2, 3));
  lHeld := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := TThread.CreateAnonymousThread(
    procedure
    var
      lMutex: THandle;
    begin
      lMutex := CreateMutex(nil, True, PChar(TRdcPasswordVault.ChangeMutexName));
      lHeld.SetEvent;
      lRelease.WaitFor(10000);
      ReleaseMutex(lMutex);
      CloseHandle(lMutex);
    end);
  lThread.FreeOnTerminate := False;
  try
    lThread.Start;
    lHeld.WaitFor(10000);
    lVault := TRdcPasswordVault.Create(FStoreRef, cIterations);
    lVault.Free;
    Assert.AreEqual(Integer(1), Integer(Length(FStore.Targets('RDCManagerX:~'))), 'staging left alone while the mutex is held');
    lRelease.SetEvent;
    lThread.WaitFor;
    lVault := TRdcPasswordVault.Create(FStoreRef, cIterations);
    lVault.Free;
    Assert.AreEqual(Integer(0), Integer(Length(FStore.Targets('RDCManagerX:~'))), 'cleaned up afterwards');
  finally
    lThread.Free;
    lHeld.Free;
    lRelease.Free;
    TRdcPasswordVault.ChangeMutexName := 'Local\RDCManagerX.VaultChange';
  end;
end;

procedure TVaultTests.SameHostViaUnknownGatewayAsks;
var
  lAsked: TArray<string>;
  lAsk: TRdcApproveHostsFunc;
  lPassword: string;
  lServer: TRdcHostRef;
  lViaCorp: TRdcHostRef;
  lViaEvil: TRdcHostRef;
begin
  // srv01 approved directly. A foreign file puts gw.evil.tld in front of it (credSharing off): the combination
  // counts as a new host and is asked; via the already approved gateway it is not.
  lServer := TRdcHostRef.Create(TRdcPasswordVault.DirectHostKey('srv01.corp.local'), 'srv01');
  lViaCorp := TRdcHostRef.Create(TRdcPasswordVault.ViaGatewayHostKey('gw.corp.local', 'srv01.corp.local'), 'srv01 via gw.corp.local');
  lViaEvil := TRdcHostRef.Create(TRdcPasswordVault.ViaGatewayHostKey('gw.evil.tld', 'srv01.corp.local'), 'srv01 via gw.evil.tld');
  FVault.Initialize(cMaster);
  FVault.SaveAccount(cTargetA, 'corp\beheer', 'S3cret!', [lServer, lViaCorp]);
  lAsk := function(const aMissing: TArray<TRdcHostRef>): Boolean
    var
      lHost: TRdcHostRef;
    begin
      for lHost in aMissing do
        lAsked := lAsked + [lHost.Key];
      Result := False;
    end;
  lAsked := [];
  Assert.AreEqual(rlrDeclined, FVault.LoadApproved(cTargetA, 'corp\beheer', [lServer, lViaEvil], lAsk, lPassword));
  Assert.AreEqual(Integer(1), Integer(Length(lAsked)));
  Assert.AreEqual(lViaEvil.Key, lAsked[0]);
  lAsked := [];
  Assert.AreEqual(rlrLoaded, FVault.LoadApproved(cTargetA, 'corp\beheer', [lServer, lViaCorp], lAsk, lPassword));
  Assert.AreEqual(Integer(0), Integer(Length(lAsked)));
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
