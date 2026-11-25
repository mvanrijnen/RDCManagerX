unit RdcmX.Tests.AppSettings;

{
  settings.json: alleen wat in een sessie veranderd is wordt weggeschreven, zodat twee sessies (vensters) elkaars
  instellingen niet overschrijven (bijv. "Wachtwoorden onthouden"). Werkt op een tijdelijk bestand.
}

interface

uses
  System.IOUtils, System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.AppSettings;

type
  [TestFixture]
  TAppSettingsTests = class
  private
    FDir: string;
    FFile: string;
    function NewSession: TRdcAppSettings;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TwoSessionsKeepEachOthersChanges;
    [Test]
    procedure OldSessionDoesNotRevertOption;
    [Test]
    procedure NoChangesWritesNothing;
    [Test]
    procedure UnknownKeysArePreserved;
    [Test]
    procedure LayoutsMergePerMonitorConfig;
  end;

implementation

procedure TAppSettingsTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'rdcmx-settings-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FFile := TPath.Combine(FDir, 'settings.json');
end;

procedure TAppSettingsTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function TAppSettingsTests.NewSession: TRdcAppSettings;
begin
  Result := TRdcAppSettings.Create;
  Result.FileName := FFile;
  Result.Load;
end;

procedure TAppSettingsTests.TwoSessionsKeepEachOthersChanges;
var
  lA: TRdcAppSettings;
  lB: TRdcAppSettings;
  lCheck: TRdcAppSettings;
begin
  lA := NewSession;
  lB := NewSession;
  lCheck := nil;
  try
    lB.RememberPasswords := True;
    lB.Save;
    lA.Theme := 'dark';
    lA.Save;
    lCheck := NewSession;
    Assert.IsTrue(lCheck.RememberPasswords, 'wijziging van sessie B bewaard');
    Assert.AreEqual('dark', lCheck.Theme, 'wijziging van sessie A bewaard');
  finally
    lCheck.Free;
    lB.Free;
    lA.Free;
  end;
end;

procedure TAppSettingsTests.OldSessionDoesNotRevertOption;
var
  lCheck: TRdcAppSettings;
  lNew: TRdcAppSettings;
  lOld: TRdcAppSettings;
begin
  // Precies het probleem: een oude sessie (optie nog uit) sluit na een sessie die de optie aanzette.
  lOld := NewSession;
  lNew := NewSession;
  lCheck := nil;
  try
    lNew.RememberPasswords := True;
    lNew.Save;
    lOld.OpenFiles.Add('C:\x.rdg'); // de oude sessie bewaart bij afsluiten zijn open bestanden
    lOld.Save;
    lCheck := NewSession;
    Assert.IsTrue(lCheck.RememberPasswords, 'oude sessie mag de optie niet terugzetten');
    Assert.AreEqual(1, lCheck.OpenFiles.Count);
  finally
    lCheck.Free;
    lNew.Free;
    lOld.Free;
  end;
end;

procedure TAppSettingsTests.NoChangesWritesNothing;
var
  lA: TRdcAppSettings;
  lStamp: TDateTime;
begin
  lA := NewSession;
  try
    lA.Save;
    Assert.IsFalse(TFile.Exists(FFile), 'niets veranderd: geen bestand aangemaakt');
    lA.AutoSave := True;
    lA.Save;
    Assert.IsTrue(TFile.Exists(FFile));
    lStamp := TFile.GetLastWriteTime(FFile);
    Sleep(50);
    lA.Save;
    Assert.AreEqual(lStamp, TFile.GetLastWriteTime(FFile), 'tweede keer zonder wijziging: niet opnieuw geschreven');
  finally
    lA.Free;
  end;
end;

procedure TAppSettingsTests.UnknownKeysArePreserved;
var
  lA: TRdcAppSettings;
begin
  TFile.WriteAllText(FFile, '{"toekomstigeOptie": 42, "theme": "light"}', TEncoding.UTF8);
  lA := NewSession;
  try
    lA.AutoSave := True;
    lA.Save;
  finally
    lA.Free;
  end;
  Assert.Contains(TFile.ReadAllText(FFile), '"toekomstigeOptie"');
  Assert.Contains(TFile.ReadAllText(FFile), '"light"');
end;

procedure TAppSettingsTests.LayoutsMergePerMonitorConfig;
var
  lA: TRdcAppSettings;
  lB: TRdcAppSettings;
  lCheck: TRdcAppSettings;
  lLayout: TRdcWindowLayout;
begin
  lA := NewSession;
  lB := NewSession;
  lCheck := nil;
  try
    lLayout := Default(TRdcWindowLayout);
    lLayout.Valid := True;
    lLayout.Width := 800;
    lLayout.Height := 600;
    lA.SetLayout('monitor-A', lLayout);
    lA.Save;
    lLayout.Width := 1024;
    lB.SetLayout('monitor-B', lLayout);
    lB.Save;
    lCheck := NewSession;
    Assert.AreEqual(800, lCheck.GetLayout('monitor-A').Width);
    Assert.AreEqual(1024, lCheck.GetLayout('monitor-B').Width);
  finally
    lCheck.Free;
    lB.Free;
    lA.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAppSettingsTests);

end.
