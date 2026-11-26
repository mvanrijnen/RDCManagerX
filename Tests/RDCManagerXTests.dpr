program RDCManagerXTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

{$R 'TsBridgeTest.res' 'TsBridgeTest.rc'}

uses
  Winapi.ActiveX,
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  RdcmX.Model in '..\Source\RdcmX.Model.pas',
  RdcmX.AppSettings in '..\Source\RdcmX.AppSettings.pas',
  RdcmX.Credentials in '..\Source\RdcmX.Credentials.pas',
  RdcmX.Crypto in '..\Source\RdcmX.Crypto.pas',
  RdcmX.Lang in '..\Source\RdcmX.Lang.pas',
  RdcmX.Log in '..\Source\RdcmX.Log.pas',
  RdcmX.Ping in '..\Source\RdcmX.Ping.pas',
  RdcmX.Redirections in '..\Source\RdcmX.Redirections.pas',
  RdcmX.Shortcuts in '..\Source\RdcmX.Shortcuts.pas',
  RdcmX.Storage in '..\Source\RdcmX.Storage.pas',
  RdcmX.Storage.Json in '..\Source\RdcmX.Storage.Json.pas',
  RdcmX.Storage.Rdg in '..\Source\RdcmX.Storage.Rdg.pas',
  RdcmX.Storage.Sidecar in '..\Source\RdcmX.Storage.Sidecar.pas',
  RdcmX.Tailscale in '..\Source\RdcmX.Tailscale.pas',
  RdcmX.WakeOnLan in '..\Source\RdcmX.WakeOnLan.pas',
  RdcmX.XmlTree in '..\Source\RdcmX.XmlTree.pas',
  RdcmX.Tests.AppSettings in 'RdcmX.Tests.AppSettings.pas',
  RdcmX.Tests.Lang in 'RdcmX.Tests.Lang.pas',
  RdcmX.Tests.Ping in 'RdcmX.Tests.Ping.pas',
  RdcmX.Tests.Redirections in 'RdcmX.Tests.Redirections.pas',
  RdcmX.Tests.Experience in 'RdcmX.Tests.Experience.pas',
  RdcmX.AdSync in '..\Source\RdcmX.AdSync.pas',
  RdcmX.AdLdap in '..\Source\RdcmX.AdLdap.pas',
  RdcmX.Tests.AdSync in 'RdcmX.Tests.AdSync.pas',
  RdcmX.Tests.Storage in 'RdcmX.Tests.Storage.pas',
  RdcmX.Tests.Tailscale in 'RdcmX.Tests.Tailscale.pas',
  RdcmX.Tests.Vault in 'RdcmX.Tests.Vault.pas';

var
  lLogger: ITestLogger;
  lResults: IRunResults;
  lRunner: ITestRunner;
begin
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    try
      TDUnitX.CheckCommandLine;
      lRunner := TDUnitX.CreateRunner;
      lRunner.UseRTTI := True;
      lRunner.FailsOnNoAsserts := False;
      lLogger := TDUnitXConsoleLogger.Create(True);
      lRunner.AddLogger(lLogger);
      lResults := lRunner.Execute;
      if not lResults.AllPassed then
        System.ExitCode := EXIT_ERRORS;
    except
      on E: Exception do
      begin
        Writeln(E.ClassName, ': ', E.Message);
        System.ExitCode := EXIT_ERRORS;
      end;
    end;
  finally
    lRunner := nil;
    lResults := nil;
    lLogger := nil;
    CoUninitialize;
  end;
end.
