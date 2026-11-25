unit RdcmX.Log;

{
  Optionele debug-log naar bestand. Aan met de opdrachtregelparameter /debuglog; het bestand komt in
  %LOCALAPPDATA%\RDCManagerX\debug.log. Bevat gebeurtenissen en disconnect-codes, nooit wachtwoorden.
}

interface

type
  TRdcLog = class abstract
  private
    class var FEnabled: Boolean;
    class var FFileName: string;
  public
    class procedure Initialize;
    class procedure Write(const aMessage: string);
    class property Enabled: Boolean read FEnabled;
    class property FileName: string read FFileName;
  end;

implementation

uses
  System.IOUtils, System.SysUtils;

{ TRdcLog }

class procedure TRdcLog.Initialize;
var
  lFolder: string;
begin
  FEnabled := FindCmdLineSwitch('debuglog', True);
  if not FEnabled then
    Exit;
  lFolder := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RDCManagerX');
  try
    TDirectory.CreateDirectory(lFolder);
    FFileName := TPath.Combine(lFolder, 'debug.log');
    Write('--- Start ' + ParamStr(0));
  except
    FEnabled := False;
  end;
end;

class procedure TRdcLog.Write(const aMessage: string);
begin
  if not FEnabled then
    Exit;
  try
    TFile.AppendAllText(FFileName, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + '  ' + aMessage + sLineBreak, TEncoding.UTF8);
  except
    // logging mag nooit de app laten falen
  end;
end;

end.
