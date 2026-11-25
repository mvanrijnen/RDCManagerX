unit RdcmX.Tests.Ping;

{
  Bereikbaarheid: RdcCheckHost (ICMP, anders TCP naar de RDP-poort) tegen deze pc zelf, en de instelling "ping" op de
  route (erft van groep/bestand, alleen Direct).
}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Model, RdcmX.Ping;

type
  [TestFixture]
  TPingTests = class
  public
    [Test]
    procedure LocalhostIsOnline;
    [Test]
    procedure UnknownHostIsOffline;
    [Test]
    procedure TargetKeyIsCaseInsensitive;
    [Test]
    procedure PingSettingInheritsFromGroup;
  end;

implementation

procedure TPingTests.LocalhostIsOnline;
var
  lRoundTrip: Integer;
begin
  Assert.IsTrue(RdcCheckHost('localhost', 3389, 1000, lRoundTrip));
  Assert.IsTrue(lRoundTrip >= 0);
end;

procedure TPingTests.UnknownHostIsOffline;
var
  lRoundTrip: Integer;
begin
  // .invalid bestaat nooit (RFC 2606): niet op te lossen = niet bereikbaar.
  Assert.IsFalse(RdcCheckHost('bestaat-niet.invalid', 3389, 500, lRoundTrip));
  Assert.AreEqual(-1, lRoundTrip);
  Assert.IsFalse(RdcCheckHost('', 3389, 500, lRoundTrip));
end;

procedure TPingTests.TargetKeyIsCaseInsensitive;
begin
  Assert.AreEqual(TRdcPingTarget.Create('DC03', 3389).Key, TRdcPingTarget.Create(' dc03 ', 3389).Key);
  Assert.AreNotEqual(TRdcPingTarget.Create('dc03', 3389).Key, TRdcPingTarget.Create('dc03', 3390).Key);
end;

procedure TPingTests.PingSettingInheritsFromGroup;
var
  lFile: TRdcFile;
  lGroup: TRdcGroup;
  lServer: TRdcServer;
begin
  lFile := TRdcFile.Create('Test');
  try
    lGroup := TRdcGroup(lFile.Add(TRdcGroup.Create('Servers')));
    lServer := TRdcServer(lGroup.Add(TRdcServer.Create('dc03')));
    Assert.IsFalse(lServer.EffectiveRoute.PingEnabled, 'standaard uit');
    // Aan op het bestand (de bovenste knoop): geldt voor alles eronder.
    lFile.Settings.Route.Inherit := False;
    lFile.Settings.Route.PingEnabled := True;
    Assert.IsTrue(lServer.EffectiveRoute.PingEnabled);
    // Groep zet het weer uit.
    lGroup.Settings.Route.Inherit := False;
    lGroup.Settings.Route.PingEnabled := False;
    Assert.IsFalse(lServer.EffectiveRoute.PingEnabled);
  finally
    lFile.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPingTests);

end.
