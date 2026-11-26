unit RdcmX.Tests.AdSync;

{
  Tests for the Active Directory sync (RdcmX.AdSync) with fake LDAP results (fictional contoso.com).
}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.AdSync, RdcmX.Model;

type
  [TestFixture]
  TAdSyncTests = class
  private
    FFile: TRdcFile;
    FGroup: TRdcGroup;
    function Sync(const aEntries: TArray<TRdcAdEntry>): TRdcAdSyncResult;
    function FindServer(const aCaption: string): TRdcServer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DnHelpers;
    [Test]
    procedure SubOusBecomeSubgroups;
    [Test]
    procedure FlatModePutsAllComputersInTheGroup;
    [Test]
    procedure DisabledAndFilteredComputersAreSkipped;
    [Test]
    procedure RefreshUpdatesMovesAndRemoves;
    [Test]
    procedure ManualAndBusyServersStay;
    [Test]
    procedure OwnSettingsSurviveARefresh;
    [Test]
    procedure EmptyOusAreNotShown;
    [Test]
    procedure AdSettingDoesNotInherit;
  end;

implementation

const
  cBase = 'OU=Servers,DC=contoso,DC=com';

function Entries: TArray<TRdcAdEntry>;
begin
  Result := [
    TRdcAdEntry.Ou(cBase, 'Servers'), // the base itself (subtree search returns it): ignored
    TRdcAdEntry.Ou('OU=Datacenter,' + cBase, 'Datacenter'),
    TRdcAdEntry.Ou('OU=SQL,OU=Datacenter,' + cBase, 'SQL'),
    TRdcAdEntry.Computer('CN=DC01,OU=Datacenter,' + cBase, 'DC01', 'dc01.contoso.com'),
    TRdcAdEntry.Computer('CN=SQL01,OU=SQL,OU=Datacenter,' + cBase, 'SQL01', 'sql01.contoso.com'),
    TRdcAdEntry.Computer('CN=APP01,' + cBase, 'APP01', '')];
end;

procedure TAdSyncTests.Setup;
begin
  FFile := TRdcFile.Create('Contoso');
  FGroup := TRdcGroup(FFile.Add(TRdcGroup.Create('AD servers')));
  FGroup.Settings.Ad.Inherit := False;
  FGroup.Settings.Ad.OuDn := cBase;
end;

procedure TAdSyncTests.TearDown;
begin
  FFile.Free;
end;

function TAdSyncTests.Sync(const aEntries: TArray<TRdcAdEntry>): TRdcAdSyncResult;
begin
  Result := RdcAdSync(FGroup, aEntries, nil, nil);
end;

function TAdSyncTests.FindServer(const aCaption: string): TRdcServer;
var
  lNode: TRdcNode;
begin
  lNode := FFile.FindByPath('Contoso\AD servers\' + aCaption);
  if lNode is TRdcServer then
    Result := TRdcServer(lNode)
  else
    Result := nil;
end;

procedure TAdSyncTests.DnHelpers;
begin
  Assert.AreEqual('OU=Datacenter,DC=contoso,DC=com', RdcAdParentDn('CN=DC01,OU=Datacenter,DC=contoso,DC=com'));
  Assert.AreEqual('OU=Servers,DC=contoso,DC=com', RdcAdParentDn('CN=Smith\, John,OU=Servers,DC=contoso,DC=com'), 'escaped comma');
  Assert.AreEqual('', RdcAdParentDn('DC=com'));
  Assert.AreEqual('ou=servers,dc=contoso,dc=com', RdcAdNormalizeDn('OU = Servers, DC=Contoso , DC=com'));
end;

procedure TAdSyncTests.SubOusBecomeSubgroups;
var
  lResult: TRdcAdSyncResult;
  lServer: TRdcServer;
begin
  lResult := Sync(Entries);
  Assert.AreEqual(5, lResult.Added, '2 OUs + 3 computers');
  lServer := FindServer('Datacenter\SQL\SQL01');
  Assert.IsNotNull(lServer);
  Assert.AreEqual('sql01.contoso.com', lServer.Name, 'connects to the DNS name');
  Assert.IsNotNull(FindServer('Datacenter\DC01'));
  Assert.IsNotNull(FindServer('APP01'), 'computer directly in the base OU');
  Assert.AreEqual('APP01', FindServer('APP01').Name, 'no DNS name: the computer name');
  // A second refresh with the same result changes nothing.
  lResult := Sync(Entries);
  Assert.AreEqual(0, lResult.Added + lResult.Updated + lResult.Removed);
end;

procedure TAdSyncTests.FlatModePutsAllComputersInTheGroup;
var
  lResult: TRdcAdSyncResult;
begin
  FGroup.Settings.Ad.Values['subOus'] := 'False';
  lResult := Sync(Entries);
  Assert.AreEqual(3, lResult.Added);
  Assert.AreEqual(3, FGroup.Count);
  Assert.IsNotNull(FindServer('SQL01'));
end;

procedure TAdSyncTests.DisabledAndFilteredComputersAreSkipped;
begin
  FGroup.Settings.Ad.Values['subOus'] := 'False';
  FGroup.Settings.Ad.Values['nameFilter'] := 'S*';
  Sync(Entries + [TRdcAdEntry.Computer('CN=SRVOLD,' + cBase, 'SRVOLD', 'srvold.contoso.com', True)]);
  Assert.AreEqual(1, FGroup.Count, 'only SQL01: filter S*, SRVOLD disabled');
  Assert.IsNotNull(FindServer('SQL01'));
  FGroup.Settings.Ad.Values['skipDisabled'] := 'False';
  Sync(Entries + [TRdcAdEntry.Computer('CN=SRVOLD,' + cBase, 'SRVOLD', 'srvold.contoso.com', True)]);
  Assert.IsNotNull(FindServer('SRVOLD'));
end;

procedure TAdSyncTests.RefreshUpdatesMovesAndRemoves;
var
  lEntries: TArray<TRdcAdEntry>;
  lResult: TRdcAdSyncResult;
begin
  Sync(Entries);
  // SQL01 and OU SQL disappear; DC01 gets another DNS name.
  lEntries := [
    TRdcAdEntry.Ou('OU=Datacenter,' + cBase, 'Datacenter'),
    TRdcAdEntry.Computer('CN=DC01,OU=Datacenter,' + cBase, 'DC01', 'dc01.corp.contoso.com'),
    TRdcAdEntry.Computer('CN=APP01,' + cBase, 'APP01', '')];
  lResult := Sync(lEntries);
  Assert.AreEqual(1, lResult.Updated, 'DC01 host name');
  Assert.AreEqual(2, lResult.Removed, 'SQL01 and the empty OU group SQL');
  Assert.AreEqual('dc01.corp.contoso.com', FindServer('Datacenter\DC01').Name);
  Assert.IsNull(FFile.FindByPath('Contoso\AD servers\Datacenter\SQL'));
end;

procedure TAdSyncTests.ManualAndBusyServersStay;
var
  lManual: TRdcServer;
  lResult: TRdcAdSyncResult;
begin
  Sync(Entries);
  lManual := TRdcServer(TRdcGroup(FFile.FindByPath('Contoso\AD servers\Datacenter\SQL')).Add(TRdcServer.Create('manual.contoso.com')));
  // Everything gone from AD; DC01 has an open session.
  lResult := RdcAdSync(FGroup, [],
    function(aServer: TRdcServer): Boolean
    begin
      Result := SameText(aServer.Name, 'dc01.contoso.com');
    end, nil);
  Assert.IsNotNull(FindServer('Datacenter\DC01'), 'busy server stays');
  Assert.IsNotNull(FFile.FindByPath('Contoso\AD servers\Datacenter\SQL\manual.contoso.com'), 'manual server stays');
  Assert.AreSame(lManual, FFile.FindByPath('Contoso\AD servers\Datacenter\SQL\manual.contoso.com'));
  Assert.IsNull(FindServer('APP01'));
  Assert.AreEqual(2, lResult.Removed, 'SQL01 and APP01');
  Assert.IsTrue(lResult.Kept >= 3, 'DC01, group SQL (manual server) and group Datacenter (DC01)');
end;

procedure TAdSyncTests.OwnSettingsSurviveARefresh;
var
  lServer: TRdcServer;
begin
  Sync(Entries);
  lServer := FindServer('Datacenter\DC01');
  lServer.Settings.Connection.Inherit := False;
  lServer.Settings.Connection.Values['port'] := '3390';
  Sync(Entries);
  Assert.AreSame(lServer, FindServer('Datacenter\DC01'), 'same object, not recreated');
  Assert.AreEqual(3390, lServer.EffectiveConnection.Port);
end;

procedure TAdSyncTests.EmptyOusAreNotShown;
var
  lEntries: TArray<TRdcAdEntry>;
  lResult: TRdcAdSyncResult;
begin
  // An empty OU, an OU with only a disabled computer, and an OU whose only computer sits two levels deeper.
  lEntries := Entries + [
    TRdcAdEntry.Ou('OU=Empty,' + cBase, 'Empty'),
    TRdcAdEntry.Ou('OU=Old,' + cBase, 'Old'),
    TRdcAdEntry.Computer('CN=OLD01,OU=Old,' + cBase, 'OLD01', 'old01.contoso.com', True),
    TRdcAdEntry.Ou('OU=Branch,' + cBase, 'Branch'),
    TRdcAdEntry.Ou('OU=Floor1,OU=Branch,' + cBase, 'Floor1'),
    TRdcAdEntry.Ou('OU=Room1,OU=Floor1,OU=Branch,' + cBase, 'Room1'),
    TRdcAdEntry.Computer('CN=PC01,OU=Room1,OU=Floor1,OU=Branch,' + cBase, 'PC01', 'pc01.contoso.com')];
  Sync(lEntries);
  Assert.IsNull(FFile.FindByPath('Contoso\AD servers\Empty'), 'empty OU');
  Assert.IsNull(FFile.FindByPath('Contoso\AD servers\Old'), 'OU with only a disabled computer');
  Assert.IsNotNull(FindServer('Branch\Floor1\Room1\PC01'), 'OUs above a computer are kept');
  // The computer in Room1 is gone: Room1, Floor1 and Branch become empty and are removed.
  lResult := Sync(Entries + [
    TRdcAdEntry.Ou('OU=Branch,' + cBase, 'Branch'),
    TRdcAdEntry.Ou('OU=Floor1,OU=Branch,' + cBase, 'Floor1'),
    TRdcAdEntry.Ou('OU=Room1,OU=Floor1,OU=Branch,' + cBase, 'Room1')]);
  Assert.AreEqual(4, lResult.Removed, 'PC01 and the three OU groups');
  Assert.IsNull(FFile.FindByPath('Contoso\AD servers\Branch'));
end;

procedure TAdSyncTests.AdSettingDoesNotInherit;
var
  lChild: TRdcGroup;
begin
  Sync(Entries);
  lChild := TRdcGroup(FFile.FindByPath('Contoso\AD servers\Datacenter'));
  Assert.IsTrue(FGroup.Settings.Ad.IsLinked);
  Assert.IsFalse(lChild.Settings.Ad.IsLinked, 'subgroups are not linked themselves');
  Assert.IsFalse(TRdcxAdSettings.InRdg);
  Assert.IsFalse(TRdcxAdItemSettings.InRdg);
end;

initialization
  TDUnitX.RegisterTestFixture(TAdSyncTests);

end.
