unit RdcmX.Crypto;

{
  Cryptografie voor de wachtwoordkluis, uitsluitend via de ingebouwde Windows-cryptografie (CNG, bcrypt.dll);
  geen eigen implementaties van algoritmen en geen externe bibliotheken.

  - Sleutelafleiding: PBKDF2-HMAC-SHA256 (BCryptDeriveKeyPBKDF2).
  - Versleuteling: AES-256-GCM (geauthenticeerd: knoeien of een verkeerde sleutel geeft een fout, geen onzin).
    Nonce van 12 bytes, tag van 16 bytes; "authenticated data" bindt de versleutelde gegevens aan hun context.
  - Willekeur: BCryptGenRandom met de door het systeem aanbevolen generator.
  - Geheugen: CryptProtectMemory (sleutel versleuteld in het geheugen zolang hij niet gebruikt wordt) en
    WipeBytes om gevoelige buffers te overschrijven.
}

interface

uses
  Winapi.Windows,
  System.SysUtils;

const
  cRdcKeySize = 32;      // AES-256
  cRdcNonceSize = 12;    // GCM
  cRdcTagSize = 16;      // GCM
  cRdcSaltSize = 16;

type
  ERdcCryptoError = class(Exception);

  TRdcCrypto = class abstract
  public
    class function RandomBytes(aCount: Integer): TBytes; static;
    /// <summary>PBKDF2-HMAC-SHA256.</summary>
    class function DeriveKey(const aPassword: string; const aSalt: TBytes; aIterations: Cardinal; aKeySize: Integer = cRdcKeySize): TBytes; static;
    /// <summary>AES-256-GCM. Resultaat: nonce (12) + tag (16) + versleutelde data.</summary>
    class function Encrypt(const aKey, aPlain, aAssociatedData: TBytes): TBytes; static;
    /// <summary>Omgekeerde van Encrypt. False bij een verkeerde sleutel, verkeerde aAssociatedData of geknoei.</summary>
    class function TryDecrypt(const aKey, aSealed, aAssociatedData: TBytes; out aPlain: TBytes): Boolean; static;
    /// <summary>Buffer in het geheugen versleutelen/ontsleutelen (alleen binnen dit proces); lengte veelvoud van 16.</summary>
    class procedure ProtectMemory(var aBuffer: TBytes); static;
    class procedure UnprotectMemory(var aBuffer: TBytes); static;
  end;

/// <summary>Inhoud overschrijven en leegmaken.</summary>
procedure WipeBytes(var aBytes: TBytes);

implementation

uses
  RdcmX.Lang;

type
  NTSTATUS = Integer;
  BCRYPT_HANDLE = Pointer;

  // BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO (bcrypt.h), natuurlijke uitlijning.
  TBCryptAuthInfo = record
    cbSize: ULONG;
    dwInfoVersion: ULONG;
    pbNonce: PByte;
    cbNonce: ULONG;
    pbAuthData: PByte;
    cbAuthData: ULONG;
    pbTag: PByte;
    cbTag: ULONG;
    pbMacContext: PByte;
    cbMacContext: ULONG;
    cbAAD: ULONG;
    cbData: UInt64;
    dwFlags: ULONG;
  end;

const
  bcryptdll = 'bcrypt.dll';
  BCRYPT_ALG_HANDLE_HMAC_FLAG = $00000008;
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;
  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO_VERSION = 1;
  STATUS_SUCCESS = 0;
  STATUS_AUTH_TAG_MISMATCH = NTSTATUS($C000A002);
  CRYPTPROTECTMEMORY_BLOCK_SIZE = 16;
  CRYPTPROTECTMEMORY_SAME_PROCESS = 0;

// "delayed": resolved at first use, after RdcmX.DllSearch restricted DLL loading to System32 (DLL planting).
{$WARN SYMBOL_PLATFORM OFF}
function BCryptOpenAlgorithmProvider(out phAlgorithm: BCRYPT_HANDLE; pszAlgId, pszImplementation: PWideChar; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptCloseAlgorithmProvider(hAlgorithm: BCRYPT_HANDLE; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptSetProperty(hObject: BCRYPT_HANDLE; pszProperty: PWideChar; pbInput: PByte; cbInput: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptGenerateSymmetricKey(hAlgorithm: BCRYPT_HANDLE; out phKey: BCRYPT_HANDLE; pbKeyObject: PByte; cbKeyObject: ULONG; pbSecret: PByte; cbSecret: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptDestroyKey(hKey: BCRYPT_HANDLE): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptEncrypt(hKey: BCRYPT_HANDLE; pbInput: PByte; cbInput: ULONG; pPaddingInfo: Pointer; pbIV: PByte; cbIV: ULONG; pbOutput: PByte; cbOutput: ULONG; out pcbResult: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptDecrypt(hKey: BCRYPT_HANDLE; pbInput: PByte; cbInput: ULONG; pPaddingInfo: Pointer; pbIV: PByte; cbIV: ULONG; pbOutput: PByte; cbOutput: ULONG; out pcbResult: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptDeriveKeyPBKDF2(hPrf: BCRYPT_HANDLE; pbPassword: PByte; cbPassword: ULONG; pbSalt: PByte; cbSalt: ULONG; cIterations: UInt64; pbDerivedKey: PByte; cbDerivedKey: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function BCryptGenRandom(hAlgorithm: BCRYPT_HANDLE; pbBuffer: PByte; cbBuffer: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external bcryptdll delayed;
function CryptProtectMemory(pDataIn: Pointer; cbDataIn: DWORD; dwFlags: DWORD): BOOL; stdcall; external 'crypt32.dll' delayed;
function CryptUnprotectMemory(pDataIn: Pointer; cbDataIn: DWORD; dwFlags: DWORD): BOOL; stdcall; external 'crypt32.dll' delayed;
{$WARN SYMBOL_PLATFORM ON}

procedure Check(aStatus: NTSTATUS; const aWhat: string);
begin
  if aStatus <> STATUS_SUCCESS then
    raise ERdcCryptoError.CreateFmt(_('%s mislukt (status $%.8x)'), [aWhat, Cardinal(aStatus)]);
end;

procedure WipeBytes(var aBytes: TBytes);
begin
  if Length(aBytes) > 0 then
    FillChar(aBytes[0], Length(aBytes), 0);
  aBytes := nil;
end;

function OpenAesGcm: BCRYPT_HANDLE;
const
  cChainingMode: string = 'ChainingModeGCM';
begin
  Check(BCryptOpenAlgorithmProvider(Result, 'AES', nil, 0), _('AES openen'));
  try
    Check(BCryptSetProperty(Result, 'ChainingMode', PByte(PWideChar(cChainingMode)), (Length(cChainingMode) + 1) * SizeOf(WideChar), 0), _('GCM instellen'));
  except
    BCryptCloseAlgorithmProvider(Result, 0);
    raise;
  end;
end;

function PointerOrNil(const aBytes: TBytes): PByte;
begin
  if Length(aBytes) > 0 then
    Result := @aBytes[0]
  else
    Result := nil;
end;

{ TRdcCrypto }

class function TRdcCrypto.RandomBytes(aCount: Integer): TBytes;
begin
  SetLength(Result, aCount);
  if aCount > 0 then
    Check(BCryptGenRandom(nil, @Result[0], aCount, BCRYPT_USE_SYSTEM_PREFERRED_RNG), _('Willekeurige bytes'));
end;

class function TRdcCrypto.DeriveKey(const aPassword: string; const aSalt: TBytes; aIterations: Cardinal; aKeySize: Integer): TBytes;
var
  lAlgorithm: BCRYPT_HANDLE;
  lPassword: TBytes;
begin
  SetLength(Result, aKeySize);
  lPassword := TEncoding.UTF8.GetBytes(aPassword);
  try
    Check(BCryptOpenAlgorithmProvider(lAlgorithm, 'SHA256', nil, BCRYPT_ALG_HANDLE_HMAC_FLAG), _('HMAC-SHA256 openen'));
    try
      Check(BCryptDeriveKeyPBKDF2(lAlgorithm, PointerOrNil(lPassword), Length(lPassword), PointerOrNil(aSalt), Length(aSalt), aIterations, @Result[0], aKeySize, 0), 'PBKDF2');
    finally
      BCryptCloseAlgorithmProvider(lAlgorithm, 0);
    end;
  finally
    WipeBytes(lPassword);
  end;
end;

class function TRdcCrypto.Encrypt(const aKey, aPlain, aAssociatedData: TBytes): TBytes;
var
  lAlgorithm: BCRYPT_HANDLE;
  lAuthInfo: TBCryptAuthInfo;
  lKey: BCRYPT_HANDLE;
  lNonce: TBytes;
  lResultSize: ULONG;
begin
  if Length(aKey) <> cRdcKeySize then
    raise ERdcCryptoError.Create(_('Ongeldige sleutellengte'));
  lNonce := RandomBytes(cRdcNonceSize);
  SetLength(Result, cRdcNonceSize + cRdcTagSize + Length(aPlain));
  Move(lNonce[0], Result[0], cRdcNonceSize);
  lAlgorithm := OpenAesGcm;
  try
    Check(BCryptGenerateSymmetricKey(lAlgorithm, lKey, nil, 0, @aKey[0], Length(aKey), 0), _('Sleutel aanmaken'));
    try
      FillChar(lAuthInfo, SizeOf(lAuthInfo), 0);
      lAuthInfo.cbSize := SizeOf(lAuthInfo);
      lAuthInfo.dwInfoVersion := BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO_VERSION;
      lAuthInfo.pbNonce := @Result[0];
      lAuthInfo.cbNonce := cRdcNonceSize;
      lAuthInfo.pbAuthData := PointerOrNil(aAssociatedData);
      lAuthInfo.cbAuthData := Length(aAssociatedData);
      lAuthInfo.pbTag := @Result[cRdcNonceSize];
      lAuthInfo.cbTag := cRdcTagSize;
      Check(BCryptEncrypt(lKey, PointerOrNil(aPlain), Length(aPlain), @lAuthInfo, nil, 0, PByte(@Result[0]) + cRdcNonceSize + cRdcTagSize, Length(aPlain), lResultSize, 0), _('Versleutelen'));
    finally
      BCryptDestroyKey(lKey);
    end;
  finally
    BCryptCloseAlgorithmProvider(lAlgorithm, 0);
  end;
end;

class function TRdcCrypto.TryDecrypt(const aKey, aSealed, aAssociatedData: TBytes; out aPlain: TBytes): Boolean;
var
  lAlgorithm: BCRYPT_HANDLE;
  lAuthInfo: TBCryptAuthInfo;
  lCipherSize: Integer;
  lKey: BCRYPT_HANDLE;
  lResultSize: ULONG;
  lStatus: NTSTATUS;
  lTag: TBytes;
begin
  aPlain := nil;
  if (Length(aKey) <> cRdcKeySize) or (Length(aSealed) < cRdcNonceSize + cRdcTagSize) then
    Exit(False);
  lCipherSize := Length(aSealed) - cRdcNonceSize - cRdcTagSize;
  SetLength(aPlain, lCipherSize);
  lTag := Copy(aSealed, cRdcNonceSize, cRdcTagSize);
  lAlgorithm := OpenAesGcm;
  try
    Check(BCryptGenerateSymmetricKey(lAlgorithm, lKey, nil, 0, @aKey[0], Length(aKey), 0), _('Sleutel aanmaken'));
    try
      FillChar(lAuthInfo, SizeOf(lAuthInfo), 0);
      lAuthInfo.cbSize := SizeOf(lAuthInfo);
      lAuthInfo.dwInfoVersion := BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO_VERSION;
      lAuthInfo.pbNonce := @aSealed[0];
      lAuthInfo.cbNonce := cRdcNonceSize;
      lAuthInfo.pbAuthData := PointerOrNil(aAssociatedData);
      lAuthInfo.cbAuthData := Length(aAssociatedData);
      lAuthInfo.pbTag := @lTag[0];
      lAuthInfo.cbTag := cRdcTagSize;
      lStatus := BCryptDecrypt(lKey, PByte(@aSealed[0]) + cRdcNonceSize + cRdcTagSize, lCipherSize, @lAuthInfo, nil, 0, PointerOrNil(aPlain), lCipherSize, lResultSize, 0);
    finally
      BCryptDestroyKey(lKey);
    end;
  finally
    BCryptCloseAlgorithmProvider(lAlgorithm, 0);
  end;
  Result := lStatus = STATUS_SUCCESS;
  if not Result then
  begin
    WipeBytes(aPlain);
    if lStatus <> STATUS_AUTH_TAG_MISMATCH then
      Check(lStatus, _('Ontsleutelen'));
  end;
end;

class procedure TRdcCrypto.ProtectMemory(var aBuffer: TBytes);
begin
  if Length(aBuffer) mod CRYPTPROTECTMEMORY_BLOCK_SIZE <> 0 then
    raise ERdcCryptoError.Create(_('Buffer moet een veelvoud van 16 bytes zijn'));
  if (Length(aBuffer) > 0) and not CryptProtectMemory(@aBuffer[0], Length(aBuffer), CRYPTPROTECTMEMORY_SAME_PROCESS) then
    RaiseLastOSError;
end;

class procedure TRdcCrypto.UnprotectMemory(var aBuffer: TBytes);
begin
  if (Length(aBuffer) > 0) and not CryptUnprotectMemory(@aBuffer[0], Length(aBuffer), CRYPTPROTECTMEMORY_SAME_PROCESS) then
    RaiseLastOSError;
end;

end.
