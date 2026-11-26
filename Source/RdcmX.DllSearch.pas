unit RdcmX.DllSearch;

{
  DLL planting protection. Must be the FIRST unit in the dpr uses clause: its initialization then runs before any
  other unit (VCL, ComObj, ...) can load a DLL by name.

  SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32) makes every later LoadLibrary by plain name (including
  Delphi's "delayed" imports) look only in System32, not in the exe folder (Downloads, a share) or the PATH. DLLs
  loaded by full path (the hash-pinned tsbridge.dll) and COM in-process servers (registered full paths, such as
  mstscax.dll) are not affected.

  Limits: the static imports in the exe's import table are resolved by the loader before any code runs. Our own
  (bcrypt, crypt32, iphlpapi) are therefore declared "delayed"; the KnownDLLs (kernel32, user32, advapi32, ...)
  always come from System32. Static imports of the Delphi RTL/VCL (version.dll, winspool.drv, wtsapi32.dll) cannot
  be delayed from here and still follow the standard search order (exe folder first).
}

interface

implementation

uses
  Winapi.Windows;

const
  LOAD_LIBRARY_SEARCH_SYSTEM32 = $00000800; // not in Winapi.Windows of Delphi 12

type
  TSetDefaultDllDirectories = function(aDirectoryFlags: DWORD): BOOL; stdcall;

procedure RestrictDllSearchToSystem32;
var
  lSetDefaultDllDirectories: TSetDefaultDllDirectories;
begin
  // Looked up dynamically: a static import of a missing function would stop the exe from starting at all.
  @lSetDefaultDllDirectories := GetProcAddress(GetModuleHandle(kernel32), 'SetDefaultDllDirectories');
  if Assigned(lSetDefaultDllDirectories) then
    lSetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32);
  // Also drop the current directory from the classic search order (for callers that bypass the default dirs).
  SetDllDirectory('');
end;

initialization
  RestrictDllSearchToSystem32;

end.
