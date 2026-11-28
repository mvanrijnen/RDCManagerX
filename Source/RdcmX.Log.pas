unit RdcmX.Log;

{
  Optionele debug-log naar bestand. Aan met de opdrachtregelparameter /debuglog; het bestand komt in
  %LOCALAPPDATA%\RDCManagerX\debug.log. Bevat gebeurtenissen en disconnect-codes, nooit wachtwoorden.
}

interface

uses
  System.SysUtils;

type
  TRdcLog = class abstract
  private
    class var FEnabled: Boolean;
    class var FFileName: string;
    class procedure InstallStackTraces; static;
  public
    class procedure Initialize;
    class procedure Write(const aMessage: string);
    // Unexpected exception: class, message, address as module+offset (look it up in the .map file next to the
    // Release exe) and the call stack captured when it was raised.
    class procedure WriteException(E: Exception; const aContext: string);
    class function AddressText(aAddress: Pointer): string; static;
    class property Enabled: Boolean read FEnabled;
    class property FileName: string read FFileName;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils;

const
  cMaxFrames = 48;

type
  TRdcStackInfo = record
    Count: Integer;
    Frames: array[0..cMaxFrames - 1] of Pointer;
  end;
  PRdcStackInfo = ^TRdcStackInfo;

const
  GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT = $00000002;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function RdcCaptureStackBackTrace(aFramesToSkip, aFramesToCapture: DWORD; aBackTrace: Pointer; aBackTraceHash: PDWORD): Word; stdcall; external kernel32 name 'RtlCaptureStackBackTrace';
function RdcGetModuleHandleEx(aFlags: DWORD; aModuleName: Pointer; out aModule: HMODULE): BOOL; stdcall; external kernel32 name 'GetModuleHandleExW';

function CaptureStackInfo(aRecord: System.PExceptionRecord): Pointer;
var
  lInfo: PRdcStackInfo;
begin
  // Called when an exception is raised (also access violations), while the faulting frames are still on the stack.
  New(lInfo);
  lInfo.Count := RdcCaptureStackBackTrace(1, cMaxFrames, @lInfo.Frames[0], nil);
  Result := lInfo;
end;

function StackInfoText(aInfo: Pointer): string;
var
  lIndex: Integer;
  lInfo: PRdcStackInfo;
begin
  Result := '';
  lInfo := aInfo;
  if lInfo = nil then
    Exit;
  for lIndex := 0 to lInfo.Count - 1 do
    Result := Result + '    ' + TRdcLog.AddressText(lInfo.Frames[lIndex]) + sLineBreak;
end;

procedure FreeStackInfo(aInfo: Pointer);
begin
  Dispose(PRdcStackInfo(aInfo));
end;

{ TRdcLog }

class function TRdcLog.AddressText(aAddress: Pointer): string;
var
  lModule: HMODULE;
  lName: array[0..MAX_PATH] of Char;
begin
  // Module + offset instead of the absolute address: ASLR loads the exe at a different base every run.
  if RdcGetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS or GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, aAddress, lModule) and (GetModuleFileName(lModule, lName, Length(lName)) > 0) then
    Result := Format('%s+$%x', [ExtractFileName(lName), NativeUInt(aAddress) - NativeUInt(lModule)])
  else
    Result := Format('$%p', [aAddress]);
end;

class procedure TRdcLog.InstallStackTraces;
begin
  // Only with /debuglog: capturing a stack for every exception costs a little, and nobody reads it otherwise.
  if Assigned(Exception.GetExceptionStackInfoProc) then
    Exit;
  Exception.GetExceptionStackInfoProc := CaptureStackInfo;
  Exception.GetStackInfoStringProc := StackInfoText;
  Exception.CleanUpStackInfoProc := FreeStackInfo;
end;

class procedure TRdcLog.WriteException(E: Exception; const aContext: string);
var
  lStack: string;
begin
  if not FEnabled or (E = nil) then
    Exit;
  try
    Write(Format('FOUT (%s): %s: %s, adres %s', [aContext, E.ClassName, E.Message, AddressText(ExceptAddr)]));
    lStack := E.StackTrace.TrimRight;
    if lStack <> '' then
      Write('Stack:' + sLineBreak + lStack);
  except
    // logging mag nooit de app laten falen
  end;
end;

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
    InstallStackTraces;
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
