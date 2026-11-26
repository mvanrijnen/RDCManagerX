unit RdcmX.UpdateCheck;

{
  Update check: asks GitHub which release is the latest and compares its version with this exe.

  - One fixed request: HTTPS GET https://api.github.com/repos/mvanrijnen/RDCManagerX/releases/latest. WinHTTP
    validates the certificate; no redirects, no other hosts. User-Agent "RDCManagerX" (GitHub requires one; it carries
    no user data). GitHub sees the IP address of this PC, nothing else.
  - Nothing is downloaded or run: the result is only a version number and the release page, which the user can open
    in the browser. The page URL from the answer is used only when it is the release page of this repository.
  - WinHTTP is imported here with "delayed" (System.Net.HttpClient imports winhttp.dll statically, which would let
    the loader pick up a planted winhttp.dll next to the exe before RdcmX.DllSearch restricts the search path).
  - No VCL: the test project tests the parsing and version comparison without network.
}

interface

uses
  System.SysUtils;

const
  cRdcReleasesUrl = 'https://github.com/mvanrijnen/RDCManagerX/releases';

type
  TRdcLatestRelease = record
    /// <summary>yyyy.mm.dd.xxx (without the "v" of the tag).</summary>
    Version: string;
    /// <summary>Release page on GitHub (always below cRdcReleasesUrl).</summary>
    PageUrl: string;
  end;

/// <summary>Asks GitHub for the latest release (blocking, up to about 15 s; call from a background thread).</summary>
function RdcFetchLatestRelease(out aRelease: TRdcLatestRelease; out aError: string): Boolean;
/// <summary>Reads tag_name and html_url from the GitHub API answer. False when the tag is not a version
/// "vyyyy.mm.dd.xxx"; a page URL outside cRdcReleasesUrl is replaced by the releases page.</summary>
function RdcParseLatestRelease(const aJson: string; out aRelease: TRdcLatestRelease): Boolean;
/// <summary>Compares two versions yyyy.mm.dd.xxx part by part: &lt; 0, 0 or &gt; 0. Invalid parts count as 0.</summary>
function RdcCompareVersions(const aLeft, aRight: string): Integer;
/// <summary>Is aVersion of the form yyyy.mm.dd.xxx (four numeric parts)?</summary>
function RdcIsVersion(const aVersion: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.JSON,
  RdcmX.Lang;

{$WARN SYMBOL_PLATFORM OFF}

type
  HINTERNET = Pointer;

const
  cWinHttp = 'winhttp.dll';
  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4;
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  WINHTTP_FLAG_SECURE = $00800000;
  WINHTTP_QUERY_STATUS_CODE = 19;
  WINHTTP_QUERY_FLAG_NUMBER = $20000000;
  WINHTTP_OPTION_REDIRECT_POLICY = 88;
  WINHTTP_OPTION_REDIRECT_POLICY_NEVER = 0;
  INTERNET_DEFAULT_HTTPS_PORT = 443;
  cApiHost = 'api.github.com';
  cApiPath = '/repos/mvanrijnen/RDCManagerX/releases/latest';
  cMaxAnswer = 1024 * 1024;

function WinHttpOpen(aAgent: PWideChar; aAccessType: DWORD; aProxy, aProxyBypass: PWideChar; aFlags: DWORD): HINTERNET; stdcall; external cWinHttp name 'WinHttpOpen' delayed;
function WinHttpConnect(aSession: HINTERNET; aServer: PWideChar; aPort: Word; aReserved: DWORD): HINTERNET; stdcall; external cWinHttp name 'WinHttpConnect' delayed;
function WinHttpOpenRequest(aConnect: HINTERNET; aVerb, aObject, aVersion, aReferrer: PWideChar; aAcceptTypes: Pointer; aFlags: DWORD): HINTERNET; stdcall; external cWinHttp name 'WinHttpOpenRequest' delayed;
function WinHttpSetTimeouts(aHandle: HINTERNET; aResolve, aConnect, aSend, aReceive: Integer): BOOL; stdcall; external cWinHttp name 'WinHttpSetTimeouts' delayed;
function WinHttpSetOption(aHandle: HINTERNET; aOption: DWORD; aBuffer: Pointer; aLength: DWORD): BOOL; stdcall; external cWinHttp name 'WinHttpSetOption' delayed;
function WinHttpSendRequest(aRequest: HINTERNET; aHeaders: PWideChar; aHeadersLength: DWORD; aOptional: Pointer; aOptionalLength, aTotalLength: DWORD; aContext: NativeUInt): BOOL; stdcall; external cWinHttp name 'WinHttpSendRequest' delayed;
function WinHttpReceiveResponse(aRequest: HINTERNET; aReserved: Pointer): BOOL; stdcall; external cWinHttp name 'WinHttpReceiveResponse' delayed;
function WinHttpQueryHeaders(aRequest: HINTERNET; aInfoLevel: DWORD; aName: PWideChar; aBuffer: Pointer; var aBufferLength: DWORD; aIndex: PDWORD): BOOL; stdcall; external cWinHttp name 'WinHttpQueryHeaders' delayed;
function WinHttpReadData(aRequest: HINTERNET; aBuffer: Pointer; aToRead: DWORD; var aRead: DWORD): BOOL; stdcall; external cWinHttp name 'WinHttpReadData' delayed;
function WinHttpCloseHandle(aHandle: HINTERNET): BOOL; stdcall; external cWinHttp name 'WinHttpCloseHandle' delayed;

function IsDigits(const aText: string): Boolean;
var
  lChar: Char;
begin
  // TryStrToInt alone also accepts '0x7', '$7' and a sign.
  Result := aText <> '';
  for lChar in aText do
    if not CharInSet(lChar, ['0'..'9']) then
      Exit(False);
end;

function VersionParts(const aVersion: string; out aParts: TArray<Integer>): Boolean;
var
  lIndex: Integer;
  lTexts: TArray<string>;
begin
  lTexts := aVersion.Split(['.']);
  SetLength(aParts, 4);
  Result := Length(lTexts) = 4;
  for lIndex := 0 to 3 do
    if (lIndex >= Length(lTexts)) or not IsDigits(lTexts[lIndex]) or (Length(lTexts[lIndex]) > 4) or not TryStrToInt(lTexts[lIndex], aParts[lIndex]) then
    begin
      aParts[lIndex] := 0;
      Result := False;
    end;
end;

function RdcIsVersion(const aVersion: string): Boolean;
var
  lParts: TArray<Integer>;
begin
  Result := VersionParts(aVersion, lParts);
end;

function RdcCompareVersions(const aLeft, aRight: string): Integer;
var
  lIndex: Integer;
  lLeft: TArray<Integer>;
  lRight: TArray<Integer>;
begin
  VersionParts(aLeft, lLeft);
  VersionParts(aRight, lRight);
  for lIndex := 0 to 3 do
    if lLeft[lIndex] <> lRight[lIndex] then
      Exit(lLeft[lIndex] - lRight[lIndex]);
  Result := 0;
end;

function RdcParseLatestRelease(const aJson: string; out aRelease: TRdcLatestRelease): Boolean;
var
  lRoot: TJSONValue;
  lTag: string;
  lUrl: string;
begin
  aRelease := Default(TRdcLatestRelease);
  Result := False;
  lRoot := TJSONObject.ParseJSONValue(aJson);
  try
    if not (lRoot is TJSONObject) then
      Exit;
    lTag := TJSONObject(lRoot).GetValue<string>('tag_name', '');
    lUrl := TJSONObject(lRoot).GetValue<string>('html_url', '');
  finally
    lRoot.Free;
  end;
  if not lTag.StartsWith('v') or not RdcIsVersion(Copy(lTag, 2, MaxInt)) then
    Exit;
  aRelease.Version := Copy(lTag, 2, MaxInt);
  // Only ever the release page of this repository (no other site, no characters that change the URL).
  if lUrl = cRdcReleasesUrl + '/tag/' + lTag then
    aRelease.PageUrl := lUrl
  else
    aRelease.PageUrl := cRdcReleasesUrl + '/latest';
  Result := True;
end;

function RdcFetchLatestRelease(out aRelease: TRdcLatestRelease; out aError: string): Boolean;
var
  lAnswer: TBytes;
  lChunk: array[0..8191] of Byte;
  lConnect: HINTERNET;
  lPolicy: DWORD;
  lRead: DWORD;
  lRequest: HINTERNET;
  lSession: HINTERNET;
  lSize: DWORD;
  lStatus: DWORD;
begin
  aRelease := Default(TRdcLatestRelease);
  aError := '';
  Result := False;
  lConnect := nil;
  lRequest := nil;
  try
    // Automatic proxy (Windows 8.1 and later), the same as the browser uses.
    lSession := WinHttpOpen('RDCManagerX', WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, nil, nil, 0);
    if lSession = nil then
      lSession := WinHttpOpen('RDCManagerX', WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  except
    on E: Exception do
    begin
      aError := E.Message; // winhttp.dll not loadable
      Exit;
    end;
  end;
  if lSession = nil then
  begin
    aError := SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    WinHttpSetTimeouts(lSession, 10000, 10000, 10000, 15000);
    lConnect := WinHttpConnect(lSession, cApiHost, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if lConnect <> nil then
      lRequest := WinHttpOpenRequest(lConnect, 'GET', cApiPath, nil, nil, nil, WINHTTP_FLAG_SECURE);
    if lRequest = nil then
    begin
      aError := SysErrorMessage(GetLastError);
      Exit;
    end;
    lPolicy := WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    WinHttpSetOption(lRequest, WINHTTP_OPTION_REDIRECT_POLICY, @lPolicy, SizeOf(lPolicy));
    if not WinHttpSendRequest(lRequest, 'Accept: application/vnd.github+json', DWORD(-1), nil, 0, 0, 0) or not WinHttpReceiveResponse(lRequest, nil) then
    begin
      aError := SysErrorMessage(GetLastError);
      Exit;
    end;
    lSize := SizeOf(lStatus);
    lStatus := 0;
    if not WinHttpQueryHeaders(lRequest, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER, nil, @lStatus, lSize, nil) or (lStatus <> 200) then
    begin
      aError := Format('HTTP %d', [lStatus]);
      Exit;
    end;
    lAnswer := nil;
    repeat
      lRead := 0;
      if not WinHttpReadData(lRequest, @lChunk[0], SizeOf(lChunk), lRead) then
      begin
        aError := SysErrorMessage(GetLastError);
        Exit;
      end;
      if lRead > 0 then
      begin
        SetLength(lAnswer, Length(lAnswer) + Integer(lRead));
        Move(lChunk[0], lAnswer[Length(lAnswer) - Integer(lRead)], lRead);
      end;
    until (lRead = 0) or (Length(lAnswer) > cMaxAnswer);
    if Length(lAnswer) > cMaxAnswer then
    begin
      aError := _('antwoord te groot');
      Exit;
    end;
    Result := RdcParseLatestRelease(TEncoding.UTF8.GetString(lAnswer), aRelease);
    if not Result then
      aError := _('geen versie in het antwoord');
  finally
    if lRequest <> nil then
      WinHttpCloseHandle(lRequest);
    if lConnect <> nil then
      WinHttpCloseHandle(lConnect);
    WinHttpCloseHandle(lSession);
  end;
end;

end.
