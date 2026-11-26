unit RdcmX.Tests.Experience;

{
  Tests for the user experience settings (rdcmxExperience): defaults, mstsc presets, performance flags,
  connection type, inheritance, and that the section never goes into the .rdg.
}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Model;

type
  [TestFixture]
  TExperienceTests = class
  public
    [Test]
    procedure DefaultsMatchMstscAutoDetect;
    [Test]
    procedure PerformanceFlagsFollowCheckBoxes;
    [Test]
    procedure PresetsMatchMstsc;
    [Test]
    procedure ConnectionTypeAndInheritance;
    [Test]
    procedure SectionIsNotInRdg;
  end;

implementation

procedure TExperienceTests.DefaultsMatchMstscAutoDetect;
var
  lFile: TRdcFile;
  lServer: TRdcServer;
begin
  lFile := TRdcFile.Create('Test');
  try
    lServer := TRdcServer(lFile.Add(TRdcServer.Create('srv01')));
    Assert.AreEqual(Ord(csAuto), Ord(lServer.EffectiveExperience.ConnectionSpeed));
    Assert.AreEqual(Cardinal(7), lServer.EffectiveExperience.NetworkConnectionType);
    Assert.IsTrue(lServer.EffectiveExperience.Options = [Low(TRdcExperienceOption)..High(TRdcExperienceOption)]);
    Assert.IsFalse(lServer.EffectiveExperience.BitmapCaching);
    Assert.IsTrue(lServer.EffectiveExperience.AutoReconnect);
    Assert.IsFalse(lServer.EffectiveExperience.KeepAlive);
    // Everything allowed: only the two "enable" flags.
    Assert.AreEqual($180, lServer.EffectiveExperience.PerformanceFlags);
  finally
    lFile.Free;
  end;
end;

procedure TExperienceTests.PerformanceFlagsFollowCheckBoxes;
var
  lSettings: TRdcxExperienceSettings;
begin
  lSettings := TRdcxExperienceSettings.Create;
  try
    lSettings.Values['desktopBackground'] := 'False';  // $1
    lSettings.Values['showWindowContents'] := 'False'; // $2
    lSettings.Values['menuAnimations'] := 'False';     // $4
    lSettings.Values['visualStyles'] := 'False';       // $8
    lSettings.Values['fontSmoothing'] := 'False';      // no $80
    lSettings.Values['desktopComposition'] := 'False'; // no $100
    Assert.AreEqual($F, lSettings.PerformanceFlags);
    lSettings.Values['visualStyles'] := 'True';
    lSettings.Values['fontSmoothing'] := 'True';
    Assert.AreEqual($87, lSettings.PerformanceFlags);
  finally
    lSettings.Free;
  end;
end;

procedure TExperienceTests.PresetsMatchMstsc;
begin
  Assert.IsTrue(TRdcxExperienceSettings.PresetFor(csModem) = []);
  Assert.IsTrue(TRdcxExperienceSettings.PresetFor(csLowBroadband) = [eoVisualStyles]);
  Assert.IsTrue(TRdcxExperienceSettings.PresetFor(csSatellite) = [eoDesktopComposition, eoVisualStyles]);
  Assert.IsTrue(TRdcxExperienceSettings.PresetFor(csHighBroadband) = [eoFontSmoothing, eoDesktopComposition, eoShowWindowContents, eoVisualStyles]);
  Assert.IsTrue(TRdcxExperienceSettings.PresetFor(csLan) = [Low(TRdcExperienceOption)..High(TRdcExperienceOption)]);
end;

procedure TExperienceTests.ConnectionTypeAndInheritance;
var
  lFile: TRdcFile;
  lGroup: TRdcGroup;
  lServer: TRdcServer;
begin
  lFile := TRdcFile.Create('Test');
  try
    lGroup := TRdcGroup(lFile.Add(TRdcGroup.Create('Branch')));
    lServer := TRdcServer(lGroup.Add(TRdcServer.Create('srv01')));
    lGroup.Settings.Experience.Inherit := False;
    lGroup.Settings.Experience.Values['connectionSpeed'] := 'LowBroadband';
    lGroup.Settings.Experience.Values['keepAlive'] := 'True';
    Assert.AreEqual(Cardinal(2), lServer.EffectiveExperience.NetworkConnectionType);
    Assert.IsTrue(lServer.EffectiveExperience.KeepAlive, 'inherited from the group');
    lServer.Settings.Experience.Inherit := False;
    lServer.Settings.Experience.Values['connectionSpeed'] := 'LAN';
    Assert.AreEqual(Cardinal(6), lServer.EffectiveExperience.NetworkConnectionType);
    Assert.IsFalse(lServer.EffectiveExperience.KeepAlive, 'own section: missing element = default');
  finally
    lFile.Free;
  end;
end;

procedure TExperienceTests.SectionIsNotInRdg;
begin
  Assert.IsFalse(TRdcxExperienceSettings.InRdg);
  Assert.AreEqual('rdcmxExperience', TRdcxExperienceSettings.XmlName);
end;

initialization
  TDUnitX.RegisterTestFixture(TExperienceTests);

end.
