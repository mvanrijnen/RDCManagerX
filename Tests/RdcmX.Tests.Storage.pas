unit RdcmX.Tests.Storage;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.AppSettings, RdcmX.Credentials, RdcmX.Model, RdcmX.Shortcuts, RdcmX.Storage, RdcmX.Storage.Json, RdcmX.Storage.Rdg, RdcmX.Storage.Sidecar, RdcmX.WakeOnLan, RdcmX.XmlTree;

type
  [TestFixture]
  TStorageTests = class
  private
    FBytes: TBytes;
    FFile: TRdcFile;
    FSampleFileName: string;
    FTempDir: string;
    function FindNode(const aCaption: string): TRdcNode;
    function FindServerByHost(const aHost: string; aOccurrence: Integer = 1): TRdcServer;
    function OriginalText: string;
    function TextOf(const aBytes: TBytes): string;
    function BytesOf(const aText: string): TBytes;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure CountsAndNesting;
    [Test]
    procedure DuplicateHostnamesKeepOwnCredentials;
    [Test]
    procedure FileScopeProfileReference;
    [Test]
    procedure LogonInheritedFromGroupForDc01;
    [Test]
    procedure EffectiveRemoteDesktopOfDevWorkstation;
    [Test]
    procedure AllFavoritesResolve;
    [Test]
    procedure RoundTripIsByteIdentical;
    [Test]
    procedure RoundTripIsCanonicallyEqual;
    [Test]
    procedure RenameUpdatesFavoritesAndNothingElse;
    [Test]
    procedure UnknownElementsArePreserved;
    [Test]
    [TestCase('Alleen gebruiker', 'contosoict,CONTOSO,CONTOSO,contosoict')]
    [TestCase('Lokaal account', '.\Developer,.,.,Developer')]
    [TestCase('Domein in naam (klein)', 'contoso\contosobatch,contoso,contoso,contosobatch')]
    [TestCase('Domein in naam (groot)', 'CONTOSO\Planning,CONTOSO,CONTOSO,Planning')]
    [TestCase('Machine-account', 'vm-win11-dev\Developer,vm-win11-dev,vm-win11-dev,Developer')]
    [TestCase('Machine als domein', 'Developer,VM-DEV-04,VM-DEV-04,Developer')]
    [TestCase('UPN', 'user@contoso.local,CONTOSO,,user@contoso.local')]
    procedure SplitLogon(const aRawUser, aRawDomain, aExpectedDomain, aExpectedUser: string);
    [Test]
    procedure ResolveLogonOnNodes;
    [Test]
    procedure RdgToRdcxToRdgKeepsModelAndExtras;
    [Test]
    procedure ExternalChangeIsDetected;
    [Test]
    procedure PasswordsAreNeverStored;
    [Test]
    procedure PasswordTestFile;
    [Test]
    procedure NewerRdcxFormatIsRejected;
    [Test]
    procedure ProfileRenameUpdatesReferences;
    [Test]
    procedure NewProfileIsWrittenWithoutPassword;
    [Test]
    procedure HostSectionOnlyInSidecarAndNotInherited;
    [Test]
    [TestCase('Streepjes', '00-11-22-aa-BB-cc')]
    [TestCase('Dubbele punten', '00:11:22:AA:BB:CC')]
    [TestCase('Cisco', '0011.22aa.bbcc')]
    [TestCase('Kaal', '001122AABBCC')]
    procedure MagicPacket(const aMac: string);
    [Test]
    [TestCase('Te kort', '00-11-22-33-44')]
    [TestCase('Ongeldig teken', '00-11-22-33-44-GG')]
    [TestCase('Leeg', '')]
    procedure InvalidMacIsRejected(const aMac: string);
    [Test]
    procedure FavoriteSurvivesRenameAndReload;
    [Test]
    procedure RecentIsNewestFirstAndLimited;
    [Test]
    procedure RemovingGroupRemovesItsShortcuts;
    [Test]
    [TestCase('Domeinaccount', 'srv01.corp.local,CORP,beheer,RDCManagerX:account:corp\beheer')]
    [TestCase('Domeinaccount op andere server', 'srv02,corp,BEHEER,RDCManagerX:account:corp\beheer')]
    [TestCase('UPN', 'srv01,,Beheer@Corp.local,RDCManagerX:account:beheer@corp.local')]
    [TestCase('Lokaal met punt', 'srv01,.,Admin,RDCManagerX:server:srv01:admin')]
    [TestCase('Lokaal zonder domein', 'SRV01,,admin,RDCManagerX:server:srv01:admin')]
    [TestCase('Lokaal met machinenaam', 'pc-07.corp.local,PC-07,admin,RDCManagerX:server:pc-07.corp.local:admin')]
    procedure CredentialTargets(const aHost, aDomain, aUser, aExpected: string);
    [Test]
    procedure RouteDefaultsToDirect;
    [Test]
    procedure RoutesAndDefinitionsOnlyInSidecar;
    [Test]
    procedure DefinitionsSurviveRdcxAndConversionBack;
    [Test]
    procedure SecretTargetsPerId;
  end;

implementation

function FindSample(const aName: string): string;
var
  lDir: string;
  lIndex: Integer;
begin
  // Vanaf de exe omhoog zoeken naar Samples\<naam>.
  lDir := ExtractFilePath(ParamStr(0));
  for lIndex := 0 to 6 do
  begin
    Result := TPath.Combine(TPath.Combine(lDir, 'Samples'), aName);
    if TFile.Exists(Result) then
      Exit;
    lDir := ExtractFilePath(ExcludeTrailingPathDelimiter(lDir));
  end;
  Result := '';
end;

{ TStorageTests }

procedure TStorageTests.Setup;
begin
  FSampleFileName := FindSample('Voorbeeld.rdg');
  Assert.IsNotEmpty(FSampleFileName, 'Samples\Voorbeeld.rdg niet gevonden');
  FBytes := TFile.ReadAllBytes(FSampleFileName);
  FFile := TRdcRdgFormat.Read(FBytes, FSampleFileName);
  FTempDir := TPath.Combine(TPath.GetTempPath, 'RdcmXTests_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TStorageTests.TearDown;
begin
  FreeAndNil(FFile);
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TStorageTests.TextOf(const aBytes: TBytes): string;
begin
  Result := TEncoding.UTF8.GetString(aBytes);
end;

function TStorageTests.BytesOf(const aText: string): TBytes;
begin
  // Origineel heeft een BOM; tekst bevat die (als U+FEFF) al wanneer hij met TextOf is gemaakt.
  Result := TEncoding.UTF8.GetBytes(aText);
end;

function TStorageTests.OriginalText: string;
begin
  Result := TextOf(FBytes);
end;

function TStorageTests.FindNode(const aCaption: string): TRdcNode;
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  Result := nil;
  lNodes := TList<TRdcNode>.Create;
  try
    FFile.CollectNodes(lNodes);
    for lNode in lNodes do
      if lNode.Caption = aCaption then
        Exit(lNode);
  finally
    lNodes.Free;
  end;
end;

function TStorageTests.FindServerByHost(const aHost: string; aOccurrence: Integer): TRdcServer;
var
  lFound: Integer;
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  Result := nil;
  lFound := 0;
  lNodes := TList<TRdcNode>.Create;
  try
    FFile.CollectServers(lNodes);
    for lNode in lNodes do
      if SameText(lNode.Name, aHost) then
      begin
        Inc(lFound);
        if lFound = aOccurrence then
          Exit(TRdcServer(lNode));
      end;
  finally
    lNodes.Free;
  end;
end;

procedure TStorageTests.CountsAndNesting;
var
  lGroups: Integer;
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
  lServers: TList<TRdcNode>;
  lWerkstations: TRdcGroup;
begin
  lNodes := TList<TRdcNode>.Create;
  lServers := TList<TRdcNode>.Create;
  try
    FFile.CollectNodes(lNodes);
    FFile.CollectServers(lServers);
    lGroups := 0;
    for lNode in lNodes do
      if lNode is TRdcGroup then
        Inc(lGroups);
    Assert.AreEqual('CONTOSO', FFile.Name);
    Assert.AreEqual(6, lGroups, 'groepen');
    Assert.AreEqual(68, Integer(lServers.Count), 'servers');
    Assert.AreEqual(2, FFile.Count, 'groepen direct onder het bestand');
    Assert.AreEqual(15, TRdcGroup(FindNode('100 - Servers')).Count);
    lWerkstations := FindNode('200 - Werkstations') as TRdcGroup;
    Assert.AreEqual(4, lWerkstations.Count);
    Assert.AreEqual(0, TRdcGroup(FindNode('200 - Tijdelijke Computers')).Count, 'lege groep');
    Assert.IsFalse(TRdcGroup(FindNode('200 - Tijdelijke Computers')).Expanded);
    Assert.AreEqual(27, TRdcGroup(FindNode('210 - Persoonlijke Computers')).Count);
    Assert.AreEqual(8, TRdcGroup(FindNode('220 - Ontwikkel Machines')).Count);
    Assert.AreEqual(18, TRdcGroup(FindNode('290 - Algemene werkstations')).Count);
    Assert.AreEqual(2, Integer(FFile.Profiles.Count), 'credential-profielen');
    Assert.AreEqual('ws-internal01', FindServerByHost('ws-internal01').Caption, 'server zonder displayName');
  finally
    lServers.Free;
    lNodes.Free;
  end;
end;

procedure TStorageTests.DuplicateHostnamesKeepOwnCredentials;
var
  lDomain: string;
  lFirst: TRdcServer;
  lSecond: TRdcServer;
  lUser: string;
begin
  lFirst := FindServerByHost('appserver01', 1);
  lSecond := FindServerByHost('appserver01', 2);
  Assert.IsNotNull(lFirst);
  Assert.IsNotNull(lSecond);
  Assert.AreNotSame(lFirst, lSecond);
  Assert.AreEqual('200 - appserver01 (Administrator)', lFirst.Caption);
  Assert.AreEqual('210 - appserver01 (appserver)', lSecond.Caption);
  Assert.IsTrue(lFirst.Settings.Logon.Inherit);
  Assert.IsTrue(lFirst.ResolveLogon(lDomain, lUser));
  Assert.AreEqual('CONTOSO', lDomain);
  Assert.AreEqual('contosoict', lUser);
  Assert.IsFalse(lSecond.Settings.Logon.Inherit);
  Assert.IsTrue(lSecond.ResolveLogon(lDomain, lUser));
  Assert.AreEqual('CONTOSO', lDomain);
  Assert.AreEqual('appserver', lUser);
  // Captions verschillen, dus geen #n-suffix nodig; identificatie nooit op hostnaam alleen.
  Assert.AreEqual('CONTOSO\100 - Servers\210 - appserver01 (appserver)', lSecond.Path(True));
  Assert.AreSame(lSecond, FFile.FindByPath(lSecond.Path(True)));
end;

procedure TStorageTests.FileScopeProfileReference;
var
  lDomain: string;
  lServer: TRdcServer;
  lUser: string;
begin
  lServer := FindServerByHost('vm-win11-dev');
  Assert.IsNotNull(lServer);
  Assert.IsTrue(lServer.Settings.Logon.IsFileProfile);
  Assert.AreEqual('vm-win11-dev\Developer', lServer.Settings.Logon.ProfileName);
  Assert.IsNotNull(FFile.FindProfile('vm-win11-dev\Developer'));
  Assert.IsTrue(lServer.ResolveLogon(lDomain, lUser));
  Assert.AreEqual('vm-win11-dev', lDomain);
  Assert.AreEqual('Developer', lUser);
end;

procedure TStorageTests.LogonInheritedFromGroupForDc01;
var
  lDc01: TRdcServer;
  lLogon: TRdcLogonCredentials;
begin
  lDc01 := FindServerByHost('dc01');
  Assert.IsTrue(lDc01.Settings.Logon.Inherit, 'dc01 heeft geen eigen logonCredentials');
  lLogon := lDc01.EffectiveLogon;
  Assert.AreSame(FindNode('100 - Servers').Settings.Logon, lLogon, 'overgeërfd van 100 - Servers');
  Assert.AreEqual('contosoict', lLogon.UserName);
  Assert.AreEqual('CONTOSO', lLogon.Domain);
  Assert.IsTrue(lLogon.IsCustom);
end;

procedure TStorageTests.EffectiveRemoteDesktopOfDevWorkstation;
var
  lRemote: TRdcRemoteDesktopSettings;
  lServer: TRdcServer;
begin
  lServer := FindServerByHost('vm-dev-04');
  lRemote := lServer.EffectiveRemoteDesktop;
  Assert.AreSame(lServer.Settings.RemoteDesktop, lRemote, 'eigen sectie');
  Assert.IsTrue(lRemote.SameSizeAsClientArea);
  Assert.IsFalse(lRemote.FullScreen);
  Assert.AreEqual(32, lRemote.ColorDepth);
  // <size> ontbreekt: RDCMan-default (niet de 1920 x 1080 van het bestand). Zie TE VERIFIËREN in RdcmX.Model.
  Assert.IsFalse(lRemote.HasValue('size'));
  Assert.AreEqual(1024, lRemote.Width);
  Assert.AreEqual(768, lRemote.Height);
  // Ter vergelijking: een server zonder eigen sectie erft 1920 x 1080 van het bestand.
  Assert.AreEqual(1920, FindServerByHost('dc01').EffectiveRemoteDesktop.Width);
end;

procedure TStorageTests.AllFavoritesResolve;
const
  cExpected: array[0..5] of string = ('100 - testserver01', '200 - appserver01 (Administrator)', '710 - dc02', 'vm-dev-build01', 'vm-powerbi01', 'vm-w1125h2');
var
  lIndex: Integer;
begin
  Assert.AreEqual(6, FFile.Favorites.Count);
  for lIndex := 0 to High(cExpected) do
  begin
    Assert.IsNotNull(FFile.Favorites[lIndex].Node, FFile.Favorites[lIndex].Path);
    Assert.AreEqual(cExpected[lIndex], FFile.Favorites[lIndex].Node.Caption);
  end;
  Assert.AreSame(FindServerByHost('appserver01', 1), FFile.Favorites[1].Node, 'juiste appserver01');
  Assert.IsTrue(FFile.Connected.Present);
  Assert.AreEqual(0, FFile.Connected.Count);
  Assert.IsTrue(FFile.RecentlyUsed.Present);
  Assert.AreEqual(0, FFile.Warnings.Count, FFile.Warnings.Text);
end;

procedure TStorageTests.RoundTripIsByteIdentical;
var
  lOutput: TBytes;
begin
  lOutput := TRdcRdgFormat.Write(FFile);
  Assert.AreEqual(TextOf(FBytes), TextOf(lOutput), 'tekst');
  Assert.IsTrue((Length(lOutput) = Length(FBytes)) and CompareMem(@lOutput[0], @FBytes[0], Length(FBytes)), 'bytes');
end;

procedure TStorageTests.RoundTripIsCanonicallyEqual;
var
  lFormat: TRdcXmlFormat;
  lOriginal: TRdcXmlNode;
  lWritten: TRdcXmlNode;
begin
  lOriginal := TRdcRdgFormat.ParseXml(FBytes, lFormat);
  lWritten := TRdcRdgFormat.ParseXml(TRdcRdgFormat.Write(FFile), lFormat);
  try
    Assert.IsTrue(lOriginal.IsEqual(lWritten));
  finally
    lWritten.Free;
    lOriginal.Free;
  end;
end;

procedure TStorageTests.RenameUpdatesFavoritesAndNothingElse;
var
  lExpected: string;
  lReloaded: TRdcFile;
  lServer: TRdcServer;
  lWritten: TBytes;
begin
  lServer := FindServerByHost('dc02');
  lServer.DisplayName := '711 - dc02 nieuw';
  lWritten := TRdcRdgFormat.Write(FFile);
  lExpected := OriginalText.Replace('<displayName>710 - dc02</displayName>', '<displayName>711 - dc02 nieuw</displayName>').Replace('<server>CONTOSO\100 - Servers\710 - dc02</server>', '<server>CONTOSO\100 - Servers\711 - dc02 nieuw</server>');
  Assert.AreEqual(lExpected, TextOf(lWritten), 'alleen naam en favorites-pad gewijzigd');
  lReloaded := TRdcRdgFormat.Read(lWritten);
  try
    Assert.AreEqual('CONTOSO\100 - Servers\711 - dc02 nieuw', lReloaded.Favorites[2].Path);
    Assert.IsNotNull(lReloaded.Favorites[2].Node);
    Assert.AreEqual('dc02', lReloaded.Favorites[2].Node.Name);
  finally
    lReloaded.Free;
  end;
end;

procedure TStorageTests.UnknownElementsArePreserved;
const
  cServerAnchor = '          <name>testserver01</name>'#13#10'        </properties>'#13#10;
  cServerExtra = '        <customThing attr="1">'#13#10'          <x>y &amp; z</x>'#13#10'        </customThing>'#13#10;
  cSectionAnchor = '      <colorDepth>24</colorDepth>'#13#10;
  cSectionExtra = '      <newSetting>abc</newSetting>'#13#10;
  cRootAnchor = '  <recentlyUsed />';
  cRootExtra = #13#10'  <futureElement version="2" />';
var
  lModified: string;
  lModifiedFile: TRdcFile;
begin
  lModified := OriginalText;
  Assert.IsTrue(lModified.Contains(cServerAnchor));
  lModified := lModified.Replace(cServerAnchor, cServerAnchor + cServerExtra);
  Assert.IsTrue(lModified.Contains(cSectionAnchor));
  lModified := lModified.Replace(cSectionAnchor, cSectionAnchor + cSectionExtra);
  lModified := lModified.Replace(cRootAnchor, cRootAnchor + cRootExtra);

  lModifiedFile := TRdcRdgFormat.Read(BytesOf(lModified));
  try
    Assert.AreEqual(1, Integer(lModifiedFile.RootUnknown.Count));
    Assert.AreEqual(lModified, TextOf(TRdcRdgFormat.Write(lModifiedFile)));
    // Ook na een .rdcx-omweg.
    lModifiedFile.Free;
    lModifiedFile := nil;
    lModifiedFile := TRdcJsonFormat.Read(TRdcJsonFormat.Write(TRdcRdgFormat.Read(BytesOf(lModified))));
    Assert.AreEqual(lModified, TextOf(TRdcRdgFormat.Write(lModifiedFile)), 'na .rdcx');
  finally
    lModifiedFile.Free;
  end;
end;

procedure TStorageTests.SplitLogon(const aRawUser, aRawDomain, aExpectedDomain, aExpectedUser: string);
var
  lDomain: string;
  lUser: string;
begin
  TRdcCredentialsSettings.SplitLogon(aRawUser, aRawDomain, lDomain, lUser);
  Assert.AreEqual(aExpectedDomain, lDomain, 'domein');
  Assert.AreEqual(aExpectedUser, lUser, 'gebruiker');
end;

procedure TStorageTests.ResolveLogonOnNodes;

  procedure Check(const aHost, aDomain, aUser: string);
  var
    lDomain: string;
    lUser: string;
  begin
    Assert.IsTrue(FindServerByHost(aHost).ResolveLogon(lDomain, lUser), aHost);
    Assert.AreEqual(aDomain, lDomain, aHost + ' domein');
    Assert.AreEqual(aUser, lUser, aHost + ' gebruiker');
  end;

begin
  Check('lt-service01', 'CONTOSO', 'Planning');
  Check('pc-batch', 'contoso', 'contosobatch');
  Check('vm-dev-build01', '.', 'Developer');
  Check('vm-dev-04', 'VM-DEV-04', 'Developer');
  Check('lt-admin01', 'CONTOSO', 'contosoict');       // geërfd van 200 - Werkstations
  Check('vm-dev-01w11', 'CONTOSO', 'contosoict');  // geërfd via 220 -> 200
end;

procedure TStorageTests.RdgToRdcxToRdgKeepsModelAndExtras;
var
  lFromJson: TRdcFile;
  lFromRdg: TRdcFile;
  lGroup: TRdcNode;
  lRdcx: string;
  lRdg: string;
  lRdg2: string;
  lServer: TRdcServer;
begin
  // Extra's zetten (o.a. op de tweede appserver01: test het #-pad niet nodig, captions verschillen).
  lServer := FindServerByHost('appserver01', 2);
  lServer.Settings.Extras.Inherit := False;
  lServer.Settings.Extras.DisplayMode := dmFixed;
  lServer.Settings.Extras.ResizeDebounceMs := 250;
  lGroup := FindNode('100 - Servers');
  lGroup.Settings.Extras.Inherit := False;
  lGroup.Settings.Extras.DisplayMode := dmClientArea;

  lRdg := TPath.Combine(FTempDir, 'test.rdg');
  lRdcx := TPath.Combine(FTempDir, 'test.rdcx');
  lRdg2 := TPath.Combine(FTempDir, 'terug.rdg');
  Assert.AreEqual(srSaved, TRdcStorage.Save(FFile, lRdg));
  Assert.IsTrue(TFile.Exists(TRdcSidecar.FileNameFor(lRdg)), 'sidecar geschreven');
  Assert.AreEqual(OriginalText, TextOf(TFile.ReadAllBytes(lRdg)), 'extra''s niet in de .rdg');

  lFromRdg := TRdcStorage.Load(lRdg);
  try
    lServer := TRdcServer(lFromRdg.FindByPath('CONTOSO\100 - Servers\210 - appserver01 (appserver)'));
    Assert.IsFalse(lServer.Settings.Extras.Inherit);
    Assert.AreEqual(dmFixed, lServer.Settings.Extras.DisplayMode);
    Assert.AreEqual(250, lServer.EffectiveExtras.ResizeDebounceMs);
    Assert.AreEqual(dmClientArea, TRdcServer(lFromRdg.FindByPath('CONTOSO\100 - Servers\700 - dc01')).EffectiveExtras.DisplayMode, 'geërfd van de groep');

    Assert.AreEqual(srSaved, TRdcStorage.Save(lFromRdg, lRdcx));
  finally
    lFromRdg.Free;
  end;

  lFromJson := TRdcStorage.Load(lRdcx);
  try
    Assert.AreEqual(ffRdcx, lFromJson.Format);
    Assert.AreEqual(dmFixed, lFromJson.FindByPath('CONTOSO\100 - Servers\210 - appserver01 (appserver)').Settings.Extras.DisplayMode);
    Assert.AreEqual(6, lFromJson.Favorites.Count);
    Assert.IsNotNull(lFromJson.Favorites[5].Node);
    Assert.AreEqual(srSaved, TRdcStorage.Save(lFromJson, lRdg2));
  finally
    lFromJson.Free;
  end;
  Assert.AreEqual(OriginalText, TextOf(TFile.ReadAllBytes(lRdg2)), '.rdg na .rdcx-omweg identiek');
  Assert.AreEqual(TFile.ReadAllText(TRdcSidecar.FileNameFor(lRdg)), TFile.ReadAllText(TRdcSidecar.FileNameFor(lRdg2)), 'sidecar identiek');
end;

procedure TStorageTests.ExternalChangeIsDetected;
var
  lCalls: Integer;
  lFileName: string;
  lLoaded: TRdcFile;
begin
  lFileName := TPath.Combine(FTempDir, 'extern.rdg');
  TFile.WriteAllBytes(lFileName, FBytes);
  lLoaded := TRdcStorage.Load(lFileName);
  try
    Assert.IsFalse(TRdcStorage.HasExternalChange(lLoaded));
    // Zelfde inhoud, ander tijdstempel: geen wijziging.
    TFile.SetLastWriteTimeUtc(lFileName, Now - 1);
    Assert.IsFalse(TRdcStorage.HasExternalChange(lLoaded), 'alleen touch');

    TFile.WriteAllText(lFileName, OriginalText.Replace('710 - dc02', '710 - dc02 (RDCMan)'), TEncoding.UTF8);
    Assert.IsTrue(TRdcStorage.HasExternalChange(lLoaded));
    lCalls := 0;
    Assert.AreEqual(srCancelled, TRdcStorage.Save(lLoaded, '',
      function(aFile: TRdcFile): TRdcExternalChangeAction
      begin
        Inc(lCalls);
        Result := ecaCancel;
      end));
    Assert.AreEqual(1, lCalls);
    Assert.AreEqual(srReloadRequested, TRdcStorage.Save(lLoaded, '',
      function(aFile: TRdcFile): TRdcExternalChangeAction
      begin
        Result := ecaReload;
      end));
    Assert.AreEqual(srSaved, TRdcStorage.Save(lLoaded, '',
      function(aFile: TRdcFile): TRdcExternalChangeAction
      begin
        Result := ecaOverwrite;
      end));
    Assert.IsTrue(TFile.Exists(lFileName + '.bak'), '.bak gemaakt');
    Assert.IsTrue(TFile.ReadAllText(lFileName + '.bak', TEncoding.UTF8).Contains('710 - dc02 (RDCMan)'), '.bak = versie vóór overschrijven');
    Assert.AreEqual(OriginalText, TextOf(TFile.ReadAllBytes(lFileName)));
    Assert.IsFalse(TFile.Exists(lFileName + '.tmp'), 'geen .tmp achtergebleven');
    Assert.IsFalse(TRdcStorage.HasExternalChange(lLoaded), 'na opslaan weer in sync');
  finally
    lLoaded.Free;
  end;
end;

procedure TStorageTests.PasswordsAreNeverStored;
var
  lText: string;
  lWithPassword: TRdcFile;
begin
  lText := OriginalText.Replace('<userName>appserver</userName>'#13#10'          <password />', '<userName>appserver</userName>'#13#10'          <password>AQAAANCMnd8BFdERjHoAwE/Cl+s=</password>');
  Assert.AreNotEqual(OriginalText, lText);
  lWithPassword := TRdcRdgFormat.Read(BytesOf(lText));
  try
    Assert.AreEqual(1, lWithPassword.Warnings.Count, 'melding dat het wachtwoord is genegeerd');
    Assert.AreEqual(OriginalText, TextOf(TRdcRdgFormat.Write(lWithPassword)), 'wachtwoord wordt leeg geschreven');
    Assert.IsFalse(TEncoding.UTF8.GetString(TRdcJsonFormat.Write(lWithPassword)).Contains('AQAAANCMnd8'), 'niet in .rdcx');
  finally
    lWithPassword.Free;
  end;
end;

procedure TStorageTests.PasswordTestFile;
var
  lFileName: string;
  lLoaded: TRdcFile;
begin
  lFileName := FindSample('password-test.rdg');
  if lFileName = '' then
  begin
    Assert.Pass('Samples\password-test.rdg ontbreekt; test overgeslagen.');
    Exit;
  end;
  lLoaded := TRdcStorage.Load(lFileName);
  try
    Assert.IsTrue(lLoaded.Warnings.Count > 0, 'opgeslagen wachtwoord gemeld');
    Assert.IsFalse(TEncoding.UTF8.GetString(TRdcRdgFormat.Write(lLoaded)).Contains('<password>'), 'geen wachtwoord in de uitvoer');
  finally
    lLoaded.Free;
  end;
end;

procedure TStorageTests.NewerRdcxFormatIsRejected;
var
  lRead: TTestLocalMethod;
begin
  lRead :=
    procedure
    begin
      TRdcJsonFormat.Read(TEncoding.UTF8.GetBytes('{"formatVersion": 99, "root": {}}')).Free;
    end;
  Assert.WillRaise(lRead, ERdcFormatError);
end;

procedure TStorageTests.ProfileRenameUpdatesReferences;
const
  cOld = 'vm-win11-dev\Developer';
  cNew = 'Developer (vm-win11-dev)';
var
  lFileName: string;
  lCount: Integer;
  lReloaded: TRdcFile;
  lUsage: Integer;
begin
  lUsage := FFile.ProfileUsageCount(cOld);
  Assert.IsTrue(lUsage > 0, 'profiel wordt gebruikt in het voorbeeld');
  FFile.RenameProfileReferences(cOld, cNew);
  FFile.FindProfile(cOld).ProfileName := cNew;
  lCount := FFile.ProfileUsageCount(cOld);
  Assert.AreEqual(0, lCount);
  lCount := FFile.ProfileUsageCount(cNew);
  Assert.AreEqual(lUsage, lCount);

  lFileName := TPath.Combine(FTempDir, 'profiel.rdg');
  Assert.AreEqual(srSaved, TRdcStorage.Save(FFile, lFileName));
  lReloaded := TRdcStorage.Load(lFileName);
  try
    Assert.IsNotNull(lReloaded.FindProfile(cNew));
    Assert.IsNull(lReloaded.FindProfile(cOld));
    lCount := lReloaded.ProfileUsageCount(cNew);
    Assert.AreEqual(lUsage, lCount);
  finally
    lReloaded.Free;
  end;
  // Alleen de naam verandert: terug hernoemen geeft weer exact het origineel.
  FFile.RenameProfileReferences(cNew, cOld);
  FFile.FindProfile(cNew).ProfileName := cOld;
  Assert.AreEqual(OriginalText, TextOf(TRdcRdgFormat.Write(FFile)));
end;

procedure TStorageTests.NewProfileIsWrittenWithoutPassword;
var
  lCount: Integer;
  lText: string;
begin
  FFile.AddProfile('beheer', 'CONTOSO\beheer', 'CONTOSO');
  lText := TextOf(TRdcRdgFormat.Write(FFile));
  Assert.Contains(lText, '<credentialsProfile inherit="None">' + sLineBreak + '        <profileName scope="Local">beheer</profileName>' + sLineBreak + '        <userName>CONTOSO\beheer</userName>' + sLineBreak + '        <password />' + sLineBreak + '        <domain>CONTOSO</domain>');
  lCount := FFile.ProfileUsageCount('beheer');
  Assert.AreEqual(0, lCount);
end;

procedure TStorageTests.HostSectionOnlyInSidecarAndNotInherited;
var
  lFileName: string;
  lGroup: TRdcNode;
  lReloaded: TRdcFile;
  lServer: TRdcServer;
begin
  lServer := TRdcServer(FFile.FindByPath('CONTOSO\100 - Servers\700 - dc01'));
  Assert.IsNotNull(lServer);
  lServer.Settings.Host.Inherit := False;
  lServer.Settings.Host.MacAddress := '00-11-22-AA-BB-CC';
  lGroup := FindNode('100 - Servers');
  lGroup.Settings.Host.Inherit := False;
  lGroup.Settings.Host.MacAddress := 'FF-FF-FF-FF-FF-FF';

  lFileName := TPath.Combine(FTempDir, 'wol.rdg');
  Assert.AreEqual(srSaved, TRdcStorage.Save(FFile, lFileName));
  Assert.AreEqual(OriginalText, TextOf(TFile.ReadAllBytes(lFileName)), 'WOL-gegevens niet in de .rdg');
  Assert.Contains(TFile.ReadAllText(TRdcSidecar.FileNameFor(lFileName)), '00-11-22-AA-BB-CC');

  lReloaded := TRdcStorage.Load(lFileName);
  try
    lServer := TRdcServer(lReloaded.FindByPath('CONTOSO\100 - Servers\700 - dc01'));
    Assert.IsNotNull(lServer);
    Assert.IsFalse(lServer.Settings.Host.Inherit);
    Assert.AreEqual('00-11-22-AA-BB-CC', lServer.Settings.Host.MacAddress);
    Assert.AreEqual('255.255.255.255', lServer.Settings.Host.WolBroadcast);
    Assert.AreEqual(9, lServer.Settings.Host.WolPort);
    Assert.IsTrue(lServer.Settings.Extras.Inherit, 'extra''s blijven overerven');
    Assert.AreEqual(0, lReloaded.Warnings.Count, 'geen sidecar-waarschuwingen');
  finally
    lReloaded.Free;
  end;
end;

procedure TStorageTests.RouteDefaultsToDirect;
var
  lGateway: TRdcGatewayDef;
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  // Bestaande definities (zonder rdcmxRoute) krijgen de route Direct: het huidige gedrag.
  lNodes := TList<TRdcNode>.Create;
  try
    FFile.CollectServers(lNodes);
    Assert.IsTrue(lNodes.Count > 0);
    for lNode in lNodes do
      Assert.AreEqual(Ord(rkDirect), Ord(lNode.EffectiveRoute.Kind), lNode.Caption);
  finally
    lNodes.Free;
  end;
  Assert.AreEqual(0, Integer(FFile.Tailnets.Count));
  Assert.AreEqual(0, Integer(FFile.Gateways.Count));

  lGateway := TRdcGatewayDef.Create;
  try
    lGateway.HostName := ' rdg.example.com ';
    Assert.AreEqual('rdg.example.com', lGateway.Address);
    lGateway.Port := 443;
    Assert.AreEqual('rdg.example.com', lGateway.Address);
    lGateway.Port := 4443;
    Assert.AreEqual('rdg.example.com:4443', lGateway.Address);
  finally
    lGateway.Free;
  end;
end;

procedure TStorageTests.RoutesAndDefinitionsOnlyInSidecar;
var
  lFileName: string;
  lGateway: TRdcGatewayDef;
  lGroup: TRdcNode;
  lReloaded: TRdcFile;
  lServer: TRdcNode;
  lSidecar: string;
  lTailnet: TRdcTailnetDef;
begin
  lTailnet := TRdcTailnetDef.Create;
  lTailnet.Id := '{11111111-2222-3333-4444-555555555555}';
  lTailnet.Name := 'Thuis';
  lTailnet.Ephemeral := False;
  lTailnet.ControlUrl := 'https://hs.example.com';
  FFile.Tailnets.Add(lTailnet);
  lGateway := TRdcGatewayDef.Create;
  lGateway.Id := '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}';
  lGateway.Name := 'Werk';
  lGateway.HostName := 'rdg.example.com';
  lGateway.Port := 4443;
  lGateway.Usage := guBypassLocal;
  lGateway.CredsMode := gcmSeparate;
  lGateway.AuthMethod := glmAny;
  lGateway.UserName := 'gwuser';
  lGateway.Domain := 'CONTOSO';
  FFile.Gateways.Add(lGateway);

  // Groep via Tailscale; één server daarbinnen via de gateway.
  lGroup := FindNode('100 - Servers');
  lGroup.Settings.Route.Inherit := False;
  lGroup.Settings.Route.Kind := rkTailscale;
  lGroup.Settings.Route.TailnetId := lTailnet.Id;
  lServer := FFile.FindByPath('CONTOSO\100 - Servers\700 - dc01');
  Assert.IsNotNull(lServer);
  lServer.Settings.Route.Inherit := False;
  lServer.Settings.Route.Kind := rkGateway;
  lServer.Settings.Route.GatewayId := lGateway.Id;
  Assert.AreEqual(1, FFile.TailnetUsageCount(lTailnet.Id));
  Assert.AreEqual(1, FFile.GatewayUsageCount(lGateway.Id));

  lFileName := TPath.Combine(FTempDir, 'routes.rdg');
  Assert.AreEqual(srSaved, TRdcStorage.Save(FFile, lFileName));
  Assert.AreEqual(OriginalText, TextOf(TFile.ReadAllBytes(lFileName)), 'routes en definities niet in de .rdg');
  lSidecar := TFile.ReadAllText(TRdcSidecar.FileNameFor(lFileName));
  Assert.Contains(lSidecar, 'rdg.example.com');
  Assert.Contains(lSidecar, '"rdcmxRoute"');
  Assert.DoesNotContain(lSidecar, 'password', True);
  Assert.DoesNotContain(lSidecar, 'authKey', True);

  lReloaded := TRdcStorage.Load(lFileName);
  try
    Assert.AreEqual(0, lReloaded.Warnings.Count, 'geen sidecar-waarschuwingen');
    Assert.AreEqual(1, Integer(lReloaded.Tailnets.Count));
    lTailnet := lReloaded.FindTailnet('{11111111-2222-3333-4444-555555555555}');
    Assert.IsNotNull(lTailnet);
    Assert.AreEqual('Thuis', lTailnet.Name);
    Assert.IsFalse(lTailnet.Ephemeral);
    Assert.AreEqual('https://hs.example.com', lTailnet.ControlUrl);
    lGateway := lReloaded.FindGateway('{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}');
    Assert.IsNotNull(lGateway, 'id niet hoofdlettergevoelig');
    Assert.AreEqual(Ord(guBypassLocal), Ord(lGateway.Usage));
    Assert.AreEqual(Ord(gcmSeparate), Ord(lGateway.CredsMode));
    Assert.AreEqual(Ord(glmAny), Ord(lGateway.AuthMethod));
    Assert.AreEqual(4443, lGateway.Port);
    Assert.AreEqual('gwuser', lGateway.UserName);

    lServer := lReloaded.FindByPath('CONTOSO\100 - Servers\700 - dc01');
    Assert.AreEqual(Ord(rkGateway), Ord(lServer.EffectiveRoute.Kind));
    lServer := lServer.Parent;
    Assert.AreEqual(Ord(rkTailscale), Ord(lServer.EffectiveRoute.Kind));
    Assert.AreEqual('{11111111-2222-3333-4444-555555555555}', lServer.EffectiveRoute.TailnetId);
  finally
    lReloaded.Free;
  end;
end;

procedure TStorageTests.DefinitionsSurviveRdcxAndConversionBack;
var
  lGateway: TRdcGatewayDef;
  lRdcxName: string;
  lRdgName: string;
  lReloaded: TRdcFile;
  lTailnet: TRdcTailnetDef;
begin
  lTailnet := TRdcTailnetDef.Create;
  lTailnet.Id := '{11111111-2222-3333-4444-555555555555}';
  lTailnet.Name := 'Prive';
  lTailnet.NodeHostName := 'mijn-laptop';
  lTailnet.LocalAddress := '127.0.0.3';
  FFile.Tailnets.Add(lTailnet);
  lGateway := TRdcGatewayDef.Create;
  lGateway.Id := '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}';
  lGateway.Name := 'Werk';
  lGateway.HostName := 'rdg.example.com';
  lGateway.Usage := guAutoDetect;
  lGateway.CredsMode := gcmSmartCard;
  lGateway.TailnetId := lTailnet.Id;
  FFile.Gateways.Add(lGateway);

  lRdcxName := TPath.Combine(FTempDir, 'defs.rdcx');
  Assert.AreEqual(srSaved, TRdcStorage.Save(FFile, lRdcxName));
  lReloaded := TRdcStorage.Load(lRdcxName);
  try
    lTailnet := lReloaded.FindTailnet('{11111111-2222-3333-4444-555555555555}');
    Assert.IsNotNull(lTailnet);
    Assert.AreEqual('mijn-laptop', lTailnet.NodeHostName);
    Assert.AreEqual('127.0.0.3', lTailnet.LocalAddress);
    Assert.IsTrue(lTailnet.Ephemeral);
    lGateway := lReloaded.FindGateway('{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}');
    Assert.IsNotNull(lGateway);
    Assert.AreEqual(Ord(guAutoDetect), Ord(lGateway.Usage));
    Assert.AreEqual(Ord(gcmSmartCard), Ord(lGateway.CredsMode));
    Assert.AreEqual(lTailnet.Id, lGateway.TailnetId);

    // Terug naar .rdg: de .rdg zelf blijft byte-identiek, de definities gaan naar de sidecar.
    lRdgName := TPath.Combine(FTempDir, 'defs.rdg');
    Assert.AreEqual(srSaved, TRdcStorage.Save(lReloaded, lRdgName));
    Assert.AreEqual(OriginalText, TextOf(TFile.ReadAllBytes(lRdgName)));
    Assert.Contains(TFile.ReadAllText(TRdcSidecar.FileNameFor(lRdgName)), 'mijn-laptop');
  finally
    lReloaded.Free;
  end;
end;

procedure TStorageTests.SecretTargetsPerId;
begin
  // Per id, en gebonden aan de server: andere control URL / gateway-host = ander doel (geheim niet te vinden).
  Assert.StartsWith('RDCManagerX:tailnet:{aa}:', TRdcPasswordVault.TailnetAuthKeyTarget('{AA}', ''));
  Assert.EndsWith(':authkey', TRdcPasswordVault.TailnetAuthKeyTarget('{AA}', ''));
  Assert.EndsWith(':statekey', TRdcPasswordVault.TailnetStateKeyTarget('{AA}', ''));
  Assert.AreEqual(TRdcPasswordVault.TailnetAuthKeyTarget('{AA}', 'https://HS.example.com/'), TRdcPasswordVault.TailnetAuthKeyTarget('{aa}', 'https://hs.example.com'), 'normalisatie');
  Assert.AreNotEqual(TRdcPasswordVault.TailnetAuthKeyTarget('{AA}', ''), TRdcPasswordVault.TailnetAuthKeyTarget('{AA}', 'https://evil.example.com'));
  Assert.AreNotEqual(TRdcPasswordVault.TailnetStateKeyTarget('{AA}', ''), TRdcPasswordVault.TailnetStateKeyTarget('{AA}', 'https://evil.example.com'));
  Assert.StartsWith(TRdcPasswordVault.TailnetTargetPrefix('{AA}'), TRdcPasswordVault.TailnetStateKeyTarget('{AA}', 'https://x'));
  Assert.StartsWith('RDCManagerX:gateway:{aa}:', TRdcPasswordVault.GatewayTarget(' {AA} ', 'rdg.example.com'));
  Assert.AreEqual(TRdcPasswordVault.GatewayTarget('{AA}', 'RDG.example.com'), TRdcPasswordVault.GatewayTarget('{aa}', 'rdg.example.com'));
  Assert.AreNotEqual(TRdcPasswordVault.GatewayTarget('{AA}', 'rdg.example.com'), TRdcPasswordVault.GatewayTarget('{AA}', 'evil.example.com'));
  Assert.AreNotEqual(TRdcPasswordVault.GatewayTarget('{AA}', 'rdg.example.com'), TRdcPasswordVault.GatewayTarget('{AA}', 'rdg.example.com:4443'));
  Assert.StartsWith(TRdcPasswordVault.GatewayTargetPrefix('{AA}'), TRdcPasswordVault.GatewayTarget('{AA}', 'x'));
end;

procedure TStorageTests.MagicPacket(const aMac: string);
var
  lIndex: Integer;
  lMac: TRdcMacAddress;
  lPacket: TBytes;
begin
  Assert.IsTrue(TRdcWakeOnLan.TryParseMac(aMac, lMac));
  Assert.AreEqual('00-11-22-AA-BB-CC', TRdcWakeOnLan.FormatMac(lMac));
  lPacket := TRdcWakeOnLan.BuildMagicPacket(lMac);
  Assert.AreEqual(102, Integer(Length(lPacket)));
  for lIndex := 0 to 5 do
    Assert.AreEqual(Integer($FF), Integer(lPacket[lIndex]));
  for lIndex := 0 to 15 do
  begin
    Assert.AreEqual(Integer($00), Integer(lPacket[6 + lIndex * 6]));
    Assert.AreEqual(Integer($CC), Integer(lPacket[6 + lIndex * 6 + 5]));
  end;
end;

procedure TStorageTests.InvalidMacIsRejected(const aMac: string);
var
  lMac: TRdcMacAddress;
begin
  Assert.IsFalse(TRdcWakeOnLan.TryParseMac(aMac, lMac));
end;

procedure TStorageTests.FavoriteSurvivesRenameAndReload;
var
  lFavorites: TArray<TRdcStoredShortcut>;
  lRecent: TArray<TRdcStoredShortcut>;
  lReloaded: TRdcClientShortcuts;
  lServer: TRdcServer;
  lShortcuts: TRdcClientShortcuts;
begin
  FFile.FileName := TPath.Combine(FTempDir, 'favorieten.rdg');
  lServer := TRdcServer(FFile.FindByPath('CONTOSO\100 - Servers\700 - dc01'));
  Assert.IsNotNull(lServer);
  lShortcuts := TRdcClientShortcuts.Create;
  try
    lShortcuts.FileOpened(FFile);
    lShortcuts.AddFavorite(lServer);
    Assert.IsTrue(lShortcuts.IsFavorite(lServer));
    // Hernoemen: de favoriet volgt het object, het pad wordt bij opslaan bijgewerkt.
    lServer.DisplayName := 'dc01 nieuw';
    lShortcuts.SaveTo(lFavorites, lRecent);
  finally
    lShortcuts.Free;
  end;
  Assert.AreEqual(1, Integer(Length(lFavorites)));
  Assert.AreEqual(lServer.Path(True), lFavorites[0].Path);
  Assert.AreEqual(FFile.FileName, lFavorites[0].FileName);

  lReloaded := TRdcClientShortcuts.Create;
  try
    lReloaded.LoadFrom(lFavorites, lRecent);
    Assert.AreEqual(0, Integer(Length(lReloaded.FavoriteServers)), 'bestand nog niet open: niets tonen');
    lReloaded.FileOpened(FFile);
    Assert.AreEqual(1, Integer(Length(lReloaded.FavoriteServers)));
    Assert.AreSame(lServer, lReloaded.FavoriteServers[0]);
  finally
    lReloaded.Free;
  end;
end;

procedure TStorageTests.RecentIsNewestFirstAndLimited;
var
  lNodes: TList<TRdcNode>;
  lRecent: TArray<TRdcServer>;
  lServers: TArray<TRdcServer>;
  lShortcuts: TRdcClientShortcuts;
  lIndex: Integer;
begin
  lNodes := TList<TRdcNode>.Create;
  try
    FFile.CollectServers(lNodes);
    for lIndex := 0 to 3 do
      lServers := lServers + [TRdcServer(lNodes[lIndex])];
  finally
    lNodes.Free;
  end;
  lShortcuts := TRdcClientShortcuts.Create;
  try
    lShortcuts.MaxRecent := 3;
    for lIndex := 0 to 3 do
      lShortcuts.AddRecent(lServers[lIndex]);
    lRecent := lShortcuts.RecentServers;
    Assert.AreEqual(3, Integer(Length(lRecent)), 'maximaal 3');
    Assert.AreSame(lServers[3], lRecent[0], 'nieuwste eerst');
    Assert.AreSame(lServers[1], lRecent[2]);
    // Opnieuw verbinden met een bestaande: naar voren, geen dubbele.
    lShortcuts.AddRecent(lServers[1]);
    lRecent := lShortcuts.RecentServers;
    Assert.AreEqual(3, Integer(Length(lRecent)));
    Assert.AreSame(lServers[1], lRecent[0]);
    // Lijst verkleinen kort direct in.
    lShortcuts.MaxRecent := 1;
    Assert.AreEqual(1, Integer(Length(lShortcuts.RecentServers)));
  finally
    lShortcuts.Free;
  end;
end;

procedure TStorageTests.RemovingGroupRemovesItsShortcuts;
var
  lGroup: TRdcNode;
  lServer: TRdcServer;
  lShortcuts: TRdcClientShortcuts;
begin
  lServer := TRdcServer(FFile.FindByPath('CONTOSO\100 - Servers\700 - dc01'));
  lGroup := FFile.FindByPath('CONTOSO\100 - Servers');
  lShortcuts := TRdcClientShortcuts.Create;
  try
    lShortcuts.AddFavorite(lServer);
    lShortcuts.AddRecent(lServer);
    lShortcuts.NodeRemoved(lGroup);
    Assert.IsFalse(lShortcuts.IsFavorite(lServer));
    Assert.AreEqual(0, Integer(Length(lShortcuts.RecentServers)));
  finally
    lShortcuts.Free;
  end;
end;

procedure TStorageTests.CredentialTargets(const aHost, aDomain, aUser, aExpected: string);
begin
  Assert.AreEqual(aExpected, TRdcPasswordVault.TargetFor(aHost, aDomain, aUser));
end;

initialization
  TDUnitX.RegisterTestFixture(TStorageTests);

end.
