unit RdcmX.Tests.Redirections;

{
  Tests for the warning about risky redirections in a file (RdcmX.Redirections).
}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Model, RdcmX.Redirections;

type
  [TestFixture]
  TRedirectionTests = class
  public
    [Test]
    procedure HarmlessFileHasNoFindings;
    [Test]
    procedure InheritedRedirectionCountsPerServer;
    [Test]
    procedure StartProgramAndKeyboardHookAreFound;
    [Test]
    procedure FingerprintChangesOnlyWithRiskySettings;
  end;

implementation

function NewFile(out aGroup: TRdcGroup; out aServer1, aServer2: TRdcServer): TRdcFile;
begin
  Result := TRdcFile.Create('Test');
  Result.FileName := 'C:\Temp\Test.rdg';
  aGroup := TRdcGroup(Result.Add(TRdcGroup.Create('Servers')));
  aServer1 := TRdcServer(aGroup.Add(TRdcServer.Create('srv01')));
  aServer2 := TRdcServer(aGroup.Add(TRdcServer.Create('srv02')));
end;

procedure TRedirectionTests.HarmlessFileHasNoFindings;
var
  lFile: TRdcFile;
  lGroup: TRdcGroup;
  lServer1: TRdcServer;
  lServer2: TRdcServer;
begin
  lFile := NewFile(lGroup, lServer1, lServer2);
  try
    // Defaults (clipboard, printers and smart cards are not in the list; keyboard hook default = full screen only).
    Assert.AreEqual(Integer(0), Integer(Length(RdcRiskyRedirections(lFile))));
    Assert.AreEqual('', RdcRedirectionFingerprint(lFile, RdcRiskyRedirections(lFile)));
  finally
    lFile.Free;
  end;
end;

procedure TRedirectionTests.InheritedRedirectionCountsPerServer;
var
  lFile: TRdcFile;
  lFindings: TArray<TRdcRedirectionFinding>;
  lGroup: TRdcGroup;
  lServer1: TRdcServer;
  lServer2: TRdcServer;
begin
  lFile := NewFile(lGroup, lServer1, lServer2);
  try
    // Drives on for the group: both servers inherit it.
    lGroup.Settings.LocalResources.Inherit := False;
    lGroup.Settings.LocalResources.Values['redirectDrives'] := 'True';
    lFindings := RdcRiskyRedirections(lFile);
    Assert.AreEqual(Integer(2), Integer(Length(lFindings)));
    Assert.AreEqual(Ord(rrkDrives), Ord(lFindings[0].Kind));
    Assert.IsTrue(RdcRedirectionWarning(lFile, lFindings).Contains('srv01, srv02'));
    // One server switches its own ports on as well.
    lServer2.Settings.LocalResources.Inherit := False;
    lServer2.Settings.LocalResources.Values['redirectPorts'] := 'True';
    lFindings := RdcRiskyRedirections(lFile);
    Assert.AreEqual(Integer(2), Integer(Length(lFindings)), 'srv01 drives (inherited) + srv02 ports (own section: drives back to default)');
  finally
    lFile.Free;
  end;
end;

procedure TRedirectionTests.StartProgramAndKeyboardHookAreFound;
var
  lFile: TRdcFile;
  lFindings: TArray<TRdcRedirectionFinding>;
  lGroup: TRdcGroup;
  lServer1: TRdcServer;
  lServer2: TRdcServer;
begin
  lFile := NewFile(lGroup, lServer1, lServer2);
  try
    lServer1.Settings.Connection.Inherit := False;
    lServer1.Settings.Connection.Values['startProgram'] := 'cmd.exe /c evil.bat';
    lServer2.Settings.LocalResources.Inherit := False;
    lServer2.Settings.LocalResources.Values['keyboardHook'] := 'Remote';
    lFindings := RdcRiskyRedirections(lFile);
    Assert.AreEqual(Integer(2), Integer(Length(lFindings)));
    Assert.AreEqual(Ord(rrkStartProgram), Ord(lFindings[0].Kind));
    Assert.AreEqual('cmd.exe /c evil.bat', lFindings[0].Detail);
    Assert.AreEqual(Ord(rrkKeyboardHook), Ord(lFindings[1].Kind));
    Assert.IsTrue(RdcRedirectionWarning(lFile, lFindings).Contains('cmd.exe /c evil.bat'));
  finally
    lFile.Free;
  end;
end;

procedure TRedirectionTests.FingerprintChangesOnlyWithRiskySettings;
var
  lFile: TRdcFile;
  lFingerprint: string;
  lGroup: TRdcGroup;
  lServer1: TRdcServer;
  lServer2: TRdcServer;
begin
  lFile := NewFile(lGroup, lServer1, lServer2);
  try
    lServer1.Settings.LocalResources.Inherit := False;
    lServer1.Settings.LocalResources.Values['redirectDrives'] := 'True';
    lFingerprint := RdcRedirectionFingerprint(lFile, RdcRiskyRedirections(lFile));
    Assert.AreNotEqual('', lFingerprint);
    // An unrelated change (a comment, another server's display) keeps the fingerprint.
    lServer2.DisplayName := 'Something else';
    Assert.AreEqual(lFingerprint, RdcRedirectionFingerprint(lFile, RdcRiskyRedirections(lFile)));
    // Another risky setting changes it.
    lServer2.Settings.LocalResources.Inherit := False;
    lServer2.Settings.LocalResources.Values['redirectPorts'] := 'True';
    Assert.AreNotEqual(lFingerprint, RdcRedirectionFingerprint(lFile, RdcRiskyRedirections(lFile)));
  finally
    lFile.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRedirectionTests);

end.
