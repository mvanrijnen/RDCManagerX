program RDCManagerX;

uses
  // First: restricts DLL loading by name to System32 before any other unit initializes (DLL planting).
  RdcmX.DllSearch in 'Source\RdcmX.DllSearch.pas',
  Vcl.Forms,
  MSTSCLib_TLB in 'Source\Imports\MSTSCLib_TLB.pas',
  RdcmX.AppSettings in 'Source\RdcmX.AppSettings.pas',
  RdcmX.Credentials in 'Source\RdcmX.Credentials.pas',
  RdcmX.Crypto in 'Source\RdcmX.Crypto.pas',
  RdcmX.Lang in 'Source\RdcmX.Lang.pas',
  RdcmX.Log in 'Source\RdcmX.Log.pas',
  RdcmX.Model in 'Source\RdcmX.Model.pas',
  RdcmX.Rdp.Host in 'Source\RdcmX.Rdp.Host.pas',
  RdcmX.Ping in 'Source\RdcmX.Ping.pas',
  RdcmX.Tailscale in 'Source\RdcmX.Tailscale.pas',
  RdcmX.UI.Tailnets in 'Source\RdcmX.UI.Tailnets.pas' {frmTailnets},
  RdcmX.UI.Gateways in 'Source\RdcmX.UI.Gateways.pas' {frmGateways},
  RdcmX.Rdp.Session in 'Source\RdcmX.Rdp.Session.pas',
  RdcmX.Sessions in 'Source\RdcmX.Sessions.pas',
  RdcmX.Shortcuts in 'Source\RdcmX.Shortcuts.pas',
  RdcmX.Storage in 'Source\RdcmX.Storage.pas',
  RdcmX.Storage.Json in 'Source\RdcmX.Storage.Json.pas',
  RdcmX.Storage.Rdg in 'Source\RdcmX.Storage.Rdg.pas',
  RdcmX.Storage.Sidecar in 'Source\RdcmX.Storage.Sidecar.pas',
  RdcmX.UI.CredentialPrompt in 'Source\RdcmX.UI.CredentialPrompt.pas' {frmCredentialPrompt},
  RdcmX.UI.Icons in 'Source\RdcmX.UI.Icons.pas',
  RdcmX.UI.Main in 'Source\RdcmX.UI.Main.pas' {frmMain},
  RdcmX.UI.MasterPassword in 'Source\RdcmX.UI.MasterPassword.pas' {frmMasterPassword},
  RdcmX.UI.Options in 'Source\RdcmX.UI.Options.pas' {frmOptions},
  RdcmX.UI.Profiles in 'Source\RdcmX.UI.Profiles.pas' {frmProfiles},
  RdcmX.UI.Properties in 'Source\RdcmX.UI.Properties.pas' {frmProperties},
  RdcmX.UI.SectionPage in 'Source\RdcmX.UI.SectionPage.pas',
  RdcmX.UI.SessionPanes in 'Source\RdcmX.UI.SessionPanes.pas',
  RdcmX.UI.SessionWindow in 'Source\RdcmX.UI.SessionWindow.pas',
  RdcmX.UI.TabStrip in 'Source\RdcmX.UI.TabStrip.pas',
  RdcmX.UI.Theme in 'Source\RdcmX.UI.Theme.pas',
  RdcmX.WakeOnLan in 'Source\RdcmX.WakeOnLan.pas',
  RdcmX.XmlTree in 'Source\RdcmX.XmlTree.pas';

{$R *.res}
// Versie yyyy.mm.dd.xxx: Source\Version.rc wordt bij elke build gegenereerd door Tools\NextVersion.ps1 (Tools\Version.targets).
{$R 'Version.res' 'Source\Version.rc'}
{$R 'TsBridge.res' 'Source\TsBridge.rc'}
{$R 'Help.res' 'Source\Help.rc'}
{$R 'HelpChm.res' 'Source\HelpChm.rc'}
{$R 'Lang.res' 'Source\Lang.rc'}

begin
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  TRdcLog.Initialize;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'RDCManagerX';
  // Thema vóór het eerste venster: later wisselen maakt alle vensters (en dus RDP-sessies) opnieuw aan.
  ApplyStartupTheme;
  // Language before the first window as well: forms translate their DFM texts while loading.
  ApplyStartupLanguage;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
