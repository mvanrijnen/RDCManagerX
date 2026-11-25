unit RdcmX.Tests.Tailscale;

{
  Tests voor RdcmX.Tailscale: configuratie-JSON, status-parsing, doeladressen en (als tsbridge.dll naast de
  test-exe staat) de DLL zelf zonder netwerk: aanmaken, status, forward openen/sluiten, ongeldige configuratie.
  Er wordt NIET met een echt tailnet verbonden.
}

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Credentials,
  RdcmX.Model,
  RdcmX.Tailscale;

type
  /// <summary>Kluis in het geheugen voor RdcBuildTailnetConfig.</summary>
  TFakeSecrets = class(TInterfacedObject, IRdcSecretAccess)
  public
    Items: TDictionary<string, string>;
    CanStore: Boolean;
    Unlocked: Boolean;
    constructor Create;
    destructor Destroy; override;
    function CanStoreSecrets: Boolean;
    function HasSecret(const aTarget: string): Boolean;
    function LoadSecret(const aTarget, aReason: string; out aSecret: string): Boolean;
    function SaveSecret(const aTarget, aAccount, aSecret, aReason: string): Boolean;
    procedure DeleteSecret(const aTarget: string);
    procedure DeleteSecretsWithPrefix(const aPrefix: string);
  end;

  [TestFixture]
  TTailscaleTests = class
  private
    function TempDir: string;
    function EphemeralConfig: TRdcTailnetConfig;
  public
    [Test]
    procedure ConfigJsonContainsFields;
    [Test]
    procedure ConfigWipeClearsSecrets;
    [Test]
    procedure StatusFromJson;
    [Test]
    procedure StatusFromInvalidJsonIsEmpty;
    [Test]
    procedure TargetFormatting;
    [Test]
    procedure DefaultHostNameHasPrefix;
    [Test]
    procedure BridgeCreateStatusClose;
    [Test]
    procedure BridgeRejectsMissingStateKey;
    [Test]
    procedure BridgeForwardOpensLocalPort;
    [Test]
    procedure ManagerReportsMissingNetwork;
    [Test]
    procedure ConfigEphemeralNeedsNoVault;
    [Test]
    procedure ConfigNonEphemeralCreatesAndReusesStateKey;
    [Test]
    procedure ConfigNonEphemeralWithoutVaultFails;
    [Test]
    procedure ConfigUsesStoredAuthKeyUnlessTyped;
    [Test]
    procedure NewStateKeyRemovesUnreadableState;
    [Test]
    procedure SecretsAreBoundToControlServer;
    [Test]
    procedure UntrustedFileValuesAreSanitized;
    [Test]
    procedure ValidatorsRejectUnsafeValues;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.Net.Socket;

{ TFakeSecrets }

constructor TFakeSecrets.Create;
begin
  inherited Create;
  Items := TDictionary<string, string>.Create;
  CanStore := True;
  Unlocked := True;
end;

destructor TFakeSecrets.Destroy;
begin
  Items.Free;
  inherited;
end;

function TFakeSecrets.CanStoreSecrets: Boolean;
begin
  Result := CanStore;
end;

function TFakeSecrets.HasSecret(const aTarget: string): Boolean;
begin
  Result := Items.ContainsKey(aTarget);
end;

function TFakeSecrets.LoadSecret(const aTarget, aReason: string; out aSecret: string): Boolean;
begin
  Result := Unlocked and Items.TryGetValue(aTarget, aSecret);
end;

function TFakeSecrets.SaveSecret(const aTarget, aAccount, aSecret, aReason: string): Boolean;
begin
  Result := CanStore and Unlocked;
  if Result then
    Items.AddOrSetValue(aTarget, aSecret);
end;

procedure TFakeSecrets.DeleteSecret(const aTarget: string);
begin
  Items.Remove(aTarget);
end;

procedure TFakeSecrets.DeleteSecretsWithPrefix(const aPrefix: string);
var
  lKey: string;
begin
  for lKey in Items.Keys.ToArray do
    if lKey.StartsWith(aPrefix) then
      Items.Remove(lKey);
end;

function TTailscaleTests.TempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'rdcmx-tstest-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Result);
end;

function TTailscaleTests.EphemeralConfig: TRdcTailnetConfig;
begin
  Result := Default(TRdcTailnetConfig);
  Result.Id := 'test';
  Result.HostName := 'rdcmx-test';
  Result.Ephemeral := True;
  Result.Dir := TempDir;
end;

procedure TTailscaleTests.ConfigJsonContainsFields;
var
  lConfig: TRdcTailnetConfig;
  lValue: TJSONValue;
begin
  lConfig := EphemeralConfig;
  lConfig.AuthKey := 'tskey-auth-abc';
  lConfig.ControlUrl := 'https://hs.example';
  lValue := TJSONObject.ParseJSONValue(lConfig.ToJson);
  try
    Assert.AreEqual('rdcmx-test', lValue.GetValue<string>('hostname'));
    Assert.AreEqual('tskey-auth-abc', lValue.GetValue<string>('authKey'));
    Assert.IsTrue(lValue.GetValue<Boolean>('ephemeral'));
    Assert.AreEqual('https://hs.example', lValue.GetValue<string>('controlUrl'));
    Assert.AreEqual(lConfig.Dir, lValue.GetValue<string>('dir'));
  finally
    lValue.Free;
  end;
end;

procedure TTailscaleTests.ConfigWipeClearsSecrets;
var
  lConfig: TRdcTailnetConfig;
begin
  lConfig := EphemeralConfig;
  lConfig.AuthKey := 'tskey-auth-' + IntToStr(Random(1000000));
  lConfig.StateKey := 'c2VjcmV0';
  lConfig.Wipe;
  Assert.AreEqual('', lConfig.AuthKey);
  Assert.AreEqual('', lConfig.StateKey);
end;

procedure TTailscaleTests.StatusFromJson;
var
  lStatus: TRdcTailnetStatus;
begin
  lStatus := TRdcTailnetStatus.FromJson('{"state":"Running","ips":["100.64.0.5","fd7a::5"],"dnsName":"x.ts.net.","authUrl":"","lastError":""}');
  Assert.IsTrue(lStatus.IsRunning);
  Assert.AreEqual(2, Integer(Length(lStatus.IPs)));
  Assert.AreEqual('100.64.0.5', lStatus.IPs[0]);
  Assert.AreEqual('x.ts.net.', lStatus.DnsName);
end;

procedure TTailscaleTests.StatusFromInvalidJsonIsEmpty;
var
  lStatus: TRdcTailnetStatus;
begin
  lStatus := TRdcTailnetStatus.FromJson('geen json');
  Assert.AreEqual('', lStatus.State);
  Assert.IsFalse(lStatus.IsRunning);
end;

procedure TTailscaleTests.TargetFormatting;
begin
  Assert.AreEqual('thuis-pc:3389', RdcTailnetTarget('thuis-pc', 3389));
  Assert.AreEqual('100.64.0.5:3390', RdcTailnetTarget('100.64.0.5', 3390));
  Assert.AreEqual('[fd7a::5]:3389', RdcTailnetTarget('fd7a::5', 3389));
  Assert.AreEqual('[fd7a::5]:3389', RdcTailnetTarget('[fd7a::5]', 3389));
end;

procedure TTailscaleTests.DefaultHostNameHasPrefix;
begin
  Assert.StartsWith('rdpclient', RdcDefaultTailnetHostName);
  Assert.AreEqual(LowerCase(RdcDefaultTailnetHostName), RdcDefaultTailnetHostName);
end;

procedure TTailscaleTests.BridgeCreateStatusClose;
var
  lConfig: TRdcTailnetConfig;
  lNet: TRdcTailnet;
begin
  // De DLL zit als resource in de test-exe (zoals in RDCManagerX.exe): hij moet uitgepakt en geladen worden.
  Assert.IsTrue(TRdcTsBridge.Available, TRdcTsBridge.LoadError);
  Assert.AreNotEqual('', TRdcTsBridge.Version);
  lConfig := EphemeralConfig;
  lNet := TRdcTailnet.Create(lConfig);
  try
    Assert.IsTrue(lNet.Handle > 0);
    Assert.AreEqual('NoState', lNet.Status.State);
    lNet.Close;
    Assert.AreEqual('Closed', lNet.Status.State);
  finally
    lNet.Free;
  end;
end;

procedure TTailscaleTests.BridgeRejectsMissingStateKey;
var
  lConfig: TRdcTailnetConfig;
begin
  if not TRdcTsBridge.Available then
  begin
    Assert.Pass('tsbridge.dll niet aanwezig');
    Exit;
  end;
  lConfig := EphemeralConfig;
  lConfig.Ephemeral := False; // niet-ephemeral zonder state-sleutel: weigeren (nooit onversleuteld opslaan)
  Assert.WillRaise(
    procedure
    begin
      TRdcTailnet.Create(lConfig).Free;
    end, ETsBridge);
end;

procedure TTailscaleTests.BridgeForwardOpensLocalPort;
var
  lConfig: TRdcTailnetConfig;
  lNet: TRdcTailnet;
  lPort: Integer;
  lSocket: TSocket;
begin
  if not TRdcTsBridge.Available then
  begin
    Assert.Pass('tsbridge.dll niet aanwezig');
    Exit;
  end;
  lConfig := EphemeralConfig;
  lNet := TRdcTailnet.Create(lConfig);
  try
    lPort := lNet.AddForward('127.0.0.2:0', 'thuis-pc:3389');
    Assert.IsTrue(lPort > 0, 'geen vrije poort gekregen');
    // De listener moet bereikbaar zijn (het doorsturen zelf faalt: de node zit niet in een tailnet).
    lSocket := TSocket.Create(TSocketType.TCP);
    try
      lSocket.Connect('', '127.0.0.2', '', lPort);
      Assert.IsTrue(TSocketState.Connected in lSocket.State);
    finally
      lSocket.Free;
    end;
    lNet.RemoveForward(lPort);
  finally
    lNet.Free;
  end;
end;

procedure TTailscaleTests.ManagerReportsMissingNetwork;
var
  lManager: TRdcTailnetManager;
begin
  lManager := TRdcTailnetManager.Create;
  try
    Assert.IsFalse(lManager.IsRunning('bestaat-niet'));
    Assert.AreEqual(0, lManager.RefCount('bestaat-niet'));
    Assert.WillRaise(
      procedure
      begin
        lManager.AddForward('bestaat-niet', '127.0.0.2:0', 'x:3389');
      end, ETsBridge);
    lManager.Release('bestaat-niet'); // mag geen fout geven
  finally
    lManager.Free;
  end;
end;

function NewDef(aEphemeral: Boolean): TRdcTailnetDef;
begin
  Result := TRdcTailnetDef.Create;
  Result.Id := '{11111111-2222-3333-4444-555555555555}';
  Result.Name := 'Thuis';
  Result.Ephemeral := aEphemeral;
end;

procedure TTailscaleTests.ConfigEphemeralNeedsNoVault;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lSecrets: TFakeSecrets;
  lSecretsRef: IRdcSecretAccess;
begin
  lSecrets := TFakeSecrets.Create;
  lSecretsRef := lSecrets;
  lSecrets.CanStore := False;
  lDef := NewDef(True);
  try
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual('', lConfig.StateKey);
    Assert.AreEqual('', lConfig.AuthKey);
    Assert.AreEqual(RdcDefaultTailnetHostName, lConfig.HostName);
    Assert.AreEqual(RdcTailnetDir(lDef.Id), lConfig.Dir);
    Assert.AreEqual(0, Integer(lSecrets.Items.Count), 'niets opgeslagen');
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.ConfigNonEphemeralCreatesAndReusesStateKey;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lFirst: string;
  lSecrets: TFakeSecrets;
  lSecretsRef: IRdcSecretAccess;
begin
  lSecrets := TFakeSecrets.Create;
  lSecretsRef := lSecrets;
  lDef := NewDef(False);
  try
    lDef.NodeHostName := 'mijn-pc';
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual('mijn-pc', lConfig.HostName);
    Assert.AreEqual(44, Length(lConfig.StateKey), '32 bytes base64');
    Assert.IsTrue(lSecrets.Items.ContainsKey(TRdcPasswordVault.TailnetStateKeyTarget(lDef.Id, lDef.ControlUrl)));
    lFirst := lConfig.StateKey;
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual(lFirst, lConfig.StateKey, 'zelfde sleutel bij de volgende keer');
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.ConfigNonEphemeralWithoutVaultFails;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lSecrets: TFakeSecrets;
  lSecretsRef: IRdcSecretAccess;
begin
  lSecrets := TFakeSecrets.Create;
  lSecretsRef := lSecrets;
  lSecrets.CanStore := False;
  lDef := NewDef(False);
  try
    Assert.IsFalse(RdcBuildTailnetConfig(lDef, lSecretsRef, 'tskey-auth-x', lConfig, lError));
    Assert.Contains(lError, 'ephemeral');
    Assert.AreEqual('', lConfig.AuthKey, 'geheimen gewist bij een fout');
    // Kluis aanwezig maar vergrendeld (en niet ontgrendeld): ook een fout.
    lSecrets.CanStore := True;
    lSecrets.Items.Add(TRdcPasswordVault.TailnetStateKeyTarget(lDef.Id, lDef.ControlUrl), 'x');
    lSecrets.Unlocked := False;
    Assert.IsFalse(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError));
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.ConfigUsesStoredAuthKeyUnlessTyped;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lSecrets: TFakeSecrets;
  lSecretsRef: IRdcSecretAccess;
begin
  lSecrets := TFakeSecrets.Create;
  lSecretsRef := lSecrets;
  lDef := NewDef(True);
  try
    lSecrets.Items.Add(TRdcPasswordVault.TailnetAuthKeyTarget(lDef.Id, lDef.ControlUrl), 'tskey-auth-stored');
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual('tskey-auth-stored', lConfig.AuthKey);
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, 'tskey-auth-typed', lConfig, lError), lError);
    Assert.AreEqual('tskey-auth-typed', lConfig.AuthKey);
    lConfig.Wipe;
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.NewStateKeyRemovesUnreadableState;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lSecrets: TFakeSecrets;
  lSecretsRef: IRdcSecretAccess;
  lStateDir: string;
begin
  // Kluis geleegd: de state-sleutel is weg, maar het (versleutelde) state-bestand staat er nog.
  lSecrets := TFakeSecrets.Create;
  lSecretsRef := lSecrets;
  lDef := NewDef(False);
  try
    lDef.Id := TGUID.NewGuid.ToString;
    lStateDir := TPath.Combine(RdcTailnetDir(lDef.Id), 'state');
    TDirectory.CreateDirectory(lStateDir);
    TFile.WriteAllText(TPath.Combine(lStateDir, 'state.dpapi'), 'oud');
    try
      Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
      Assert.IsFalse(TDirectory.Exists(lStateDir), 'oude state verwijderd');
      lConfig.Wipe;
    finally
      if TDirectory.Exists(RdcTailnetDir(lDef.Id)) then
        TDirectory.Delete(RdcTailnetDir(lDef.Id), True);
    end;
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.SecretsAreBoundToControlServer;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lSecrets: TFakeSecrets;
  lSecretsRef: IRdcSecretAccess;
begin
  // Auth key opgeslagen voor Tailscale zelf; een (gemanipuleerd) bestand met hetzelfde id maar een andere control
  // server mag die key niet krijgen.
  lSecrets := TFakeSecrets.Create;
  lSecretsRef := lSecrets;
  lDef := NewDef(True);
  try
    lSecrets.Items.Add(TRdcPasswordVault.TailnetAuthKeyTarget(lDef.Id, ''), 'tskey-auth-geheim');
    lDef.ControlUrl := 'https://evil.example.com';
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual('', lConfig.AuthKey, 'key niet naar een andere control server');
    lDef.ControlUrl := '';
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual('tskey-auth-geheim', lConfig.AuthKey);
    lConfig.Wipe;
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.UntrustedFileValuesAreSanitized;
var
  lConfig: TRdcTailnetConfig;
  lDef: TRdcTailnetDef;
  lError: string;
  lSecretsRef: IRdcSecretAccess;
begin
  lSecretsRef := TFakeSecrets.Create;
  lDef := NewDef(True);
  try
    // Lokaal adres uit het bestand: nooit iets anders dan loopback (anders staat de tunnel open voor het LAN).
    lDef.LocalAddress := '0.0.0.0';
    Assert.AreEqual(cTsDefaultLocalAddress, RdcTailnetLocalAddress(lDef));
    lDef.LocalAddress := '192.168.1.10';
    Assert.AreEqual(cTsDefaultLocalAddress, RdcTailnetLocalAddress(lDef));
    lDef.LocalAddress := '127.0.0.3';
    Assert.AreEqual('127.0.0.3', RdcTailnetLocalAddress(lDef));
    // Ongeldige node-naam: standaardnaam.
    lDef.NodeHostName := 'Rare Naam!';
    Assert.IsTrue(RdcBuildTailnetConfig(lDef, lSecretsRef, '', lConfig, lError), lError);
    Assert.AreEqual(RdcDefaultTailnetHostName, lConfig.HostName);
    // Onveilige control URL: weigeren.
    lDef.ControlUrl := 'http://hs.example.com';
    Assert.IsFalse(RdcBuildTailnetConfig(lDef, lSecretsRef, 'tskey-auth-x', lConfig, lError));
    Assert.AreEqual('', lConfig.AuthKey);
  finally
    lDef.Free;
  end;
end;

procedure TTailscaleTests.ValidatorsRejectUnsafeValues;
begin
  Assert.IsTrue(RdcIsValidControlUrl(''));
  Assert.IsTrue(RdcIsValidControlUrl('https://hs.example.com'));
  Assert.IsTrue(RdcIsValidControlUrl('https://hs.example.com:8443/'));
  Assert.IsTrue(RdcIsValidControlUrl('http://localhost:8080'));
  Assert.IsTrue(RdcIsValidControlUrl('http://127.0.0.1:8080'));
  Assert.IsFalse(RdcIsValidControlUrl('http://hs.example.com'));
  Assert.IsFalse(RdcIsValidControlUrl('http://localhost.evil.com'));
  Assert.IsFalse(RdcIsValidControlUrl('https://user@evil.com'));
  Assert.IsFalse(RdcIsValidControlUrl('file:///c:/x'));
  Assert.IsFalse(RdcIsValidControlUrl('hs.example.com'));
  Assert.IsFalse(RdcIsValidLoopbackAddress('0.0.0.0'));
  Assert.IsFalse(RdcIsValidLoopbackAddress('127.0.0'));
  Assert.IsFalse(RdcIsValidLoopbackAddress('127.0.0.256'));
  Assert.IsTrue(RdcIsValidLoopbackAddress('127.0.0.2'));
  Assert.IsFalse(RdcIsValidNodeHostName('-x'));
  Assert.IsFalse(RdcIsValidNodeHostName('X'));
  Assert.IsTrue(RdcIsValidNodeHostName('rdpclient-pc1'));
  // Alleen https-login-URL's worden geopend (anders kan ShellExecute een programma starten).
  Assert.IsFalse(RdcOpenAuthUrl('C:\Windows\System32\calc.exe'));
  Assert.IsFalse(RdcOpenAuthUrl('file:///C:/Windows/System32/calc.exe'));
  Assert.IsFalse(RdcOpenAuthUrl('http://login.tailscale.com/a/x'));
  Assert.IsFalse(RdcOpenAuthUrl('https://login.tailscale.com/a/x" & calc'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTailscaleTests);

end.
