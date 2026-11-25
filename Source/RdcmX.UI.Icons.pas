unit RdcmX.UI.Icons;

{
  Iconen voor de boom, per DPI opgebouwd (aanroepen bij start en na elke DPI-wissel).
  Basis: de Windows stock-iconen voor map en server op exact de gevraagde grootte. Een status-stip
  rechtsonder wordt zelf getekend (met anti-aliasing via dekking per pixel) en in een 32-bits icoon gezet.
  Favorieten (ster) en Recent (klok) komen uit het Windows-iconenlettertype (Segoe Fluent Icons / MDL2 Assets).
}

interface

uses
  Vcl.Controls, Vcl.ImgList;

const
  ciGroup = 0;
  /// <summary>Server zonder sessie: blauw (geen ping, of nog niet geprobeerd).</summary>
  ciServer = 1;
  ciServerConnecting = 2;
  ciServerConnected = 3;
  ciServerError = 4;
  ciFavorites = 5;
  ciRecent = 6;
  /// <summary>Server zonder sessie, gepingd en niet bereikbaar: rood.</summary>
  ciServerOffline = 7;
  /// <summary>Server zonder sessie, gepingd en bereikbaar: groen.</summary>
  ciServerOnline = 8;
  /// <summary>Server zonder sessie, bereikbaar, maar er antwoordt een andere computer (verouderd DNS-record): oranje.</summary>
  ciServerWrongHost = 9;

procedure BuildNodeImages(aImages: TCustomImageList; aPPI: Integer);

implementation

uses
  Winapi.CommCtrl, Winapi.ShellAPI, Winapi.Windows,
  System.Math, System.SysUtils, System.Types,
  Vcl.Forms;

type
  TPixels = array of Cardinal; // $AARRGGBB, niet-gepremultiplieerd
  PHICON = ^HICON;

function SHDefExtractIconW(pszIconFile: PWideChar; iIndex: Integer; uFlags: UINT; phiconLarge, phiconSmall: PHICON; nIconSize: UINT): HRESULT; stdcall; external 'shell32.dll' name 'SHDefExtractIconW';

function LoadStockIcon(aStockId: Integer; aSize: Integer): HICON;
var
  lInfo: TSHStockIconInfo;
begin
  Result := 0;
  FillChar(lInfo, SizeOf(lInfo), 0);
  lInfo.cbSize := SizeOf(lInfo);
  if Succeeded(SHGetStockIconInfo(aStockId, SHGSI_ICONLOCATION, lInfo)) then
    if not Succeeded(SHDefExtractIconW(lInfo.szPath, lInfo.iIcon, 0, @Result, nil, Cardinal(aSize))) then
      Result := 0;
  if Result = 0 then
    Result := CopyIcon(LoadIcon(0, IDI_APPLICATION));
end;

function IconToPixels(aIcon: HICON; aSize: Integer): TPixels;
var
  lBitmapInfo: TBitmapInfo;
  lDC: HDC;
  lHasAlpha: Boolean;
  lIconInfo: TIconInfo;
  lIndex: Integer;
  lMask: TPixels;
begin
  SetLength(Result, aSize * aSize);
  if not GetIconInfo(aIcon, lIconInfo) then
    Exit;
  lDC := GetDC(0);
  try
    FillChar(lBitmapInfo, SizeOf(lBitmapInfo), 0);
    lBitmapInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    lBitmapInfo.bmiHeader.biWidth := aSize;
    lBitmapInfo.bmiHeader.biHeight := -aSize; // top-down
    lBitmapInfo.bmiHeader.biPlanes := 1;
    lBitmapInfo.bmiHeader.biBitCount := 32;
    lBitmapInfo.bmiHeader.biCompression := BI_RGB;
    if lIconInfo.hbmColor <> 0 then
      GetDIBits(lDC, lIconInfo.hbmColor, 0, aSize, @Result[0], lBitmapInfo, DIB_RGB_COLORS);

    lHasAlpha := False;
    for lIndex := 0 to High(Result) do
      if Result[lIndex] shr 24 <> 0 then
      begin
        lHasAlpha := True;
        Break;
      end;
    if not lHasAlpha and (lIconInfo.hbmMask <> 0) then
    begin
      // Oud icoon zonder alfakanaal: het masker bepaalt de transparantie.
      SetLength(lMask, aSize * aSize);
      GetDIBits(lDC, lIconInfo.hbmMask, 0, aSize, @lMask[0], lBitmapInfo, DIB_RGB_COLORS);
      for lIndex := 0 to High(Result) do
        if lMask[lIndex] and $00FFFFFF = 0 then
          Result[lIndex] := Result[lIndex] or $FF000000
        else
          Result[lIndex] := 0;
    end;
  finally
    ReleaseDC(0, lDC);
    if lIconInfo.hbmColor <> 0 then
      DeleteObject(lIconInfo.hbmColor);
    if lIconInfo.hbmMask <> 0 then
      DeleteObject(lIconInfo.hbmMask);
  end;
end;

procedure BlendPixel(var aDest: Cardinal; aColor: Cardinal; aCoverage: Double);
var
  lDa: Double;
  lOa: Double;
  lSa: Double;

  function Channel(aShift: Integer): Cardinal;
  var
    lSc: Double;
    lDc: Double;
  begin
    lSc := (aColor shr aShift) and $FF;
    lDc := (aDest shr aShift) and $FF;
    Result := Cardinal(EnsureRange(Round((lSc * lSa + lDc * lDa * (1 - lSa)) / lOa), 0, 255)) shl aShift;
  end;

begin
  if aCoverage <= 0 then
    Exit;
  lSa := Min(aCoverage, 1);
  lDa := (aDest shr 24) / 255;
  lOa := lSa + lDa * (1 - lSa);
  if lOa <= 0 then
    Exit;
  aDest := (Cardinal(Round(lOa * 255)) shl 24) or Channel(16) or Channel(8) or Channel(0);
end;

procedure DrawDot(var aPixels: TPixels; aSize: Integer; aColor: Cardinal);
var
  lCenter: Double;
  lDistance: Double;
  lInner: Double;
  lOuter: Double;
  lX: Integer;
  lY: Integer;
begin
  lInner := aSize * 0.21;
  lOuter := lInner + Max(1, aSize / 16);
  lCenter := aSize - lOuter;
  for lY := 0 to aSize - 1 do
    for lX := 0 to aSize - 1 do
    begin
      lDistance := Sqrt(Sqr(lX + 0.5 - lCenter) + Sqr(lY + 0.5 - lCenter));
      BlendPixel(aPixels[lY * aSize + lX], $FFFFFFFF, lOuter + 0.5 - lDistance);
      BlendPixel(aPixels[lY * aSize + lX], aColor, lInner + 0.5 - lDistance);
    end;
end;

function PixelsToIcon(const aPixels: TPixels; aSize: Integer): HICON;
var
  lBits: Pointer;
  lBitmapInfo: TBitmapInfo;
  lColor: HBITMAP;
  lIconInfo: TIconInfo;
  lMask: HBITMAP;
begin
  FillChar(lBitmapInfo, SizeOf(lBitmapInfo), 0);
  lBitmapInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  lBitmapInfo.bmiHeader.biWidth := aSize;
  lBitmapInfo.bmiHeader.biHeight := -aSize;
  lBitmapInfo.bmiHeader.biPlanes := 1;
  lBitmapInfo.bmiHeader.biBitCount := 32;
  lBitmapInfo.bmiHeader.biCompression := BI_RGB;
  lColor := CreateDIBSection(0, lBitmapInfo, DIB_RGB_COLORS, lBits, 0, 0);
  lMask := CreateBitmap(aSize, aSize, 1, 1, nil);
  try
    Move(aPixels[0], lBits^, aSize * aSize * SizeOf(Cardinal));
    lIconInfo.fIcon := True;
    lIconInfo.xHotspot := 0;
    lIconInfo.yHotspot := 0;
    lIconInfo.hbmMask := lMask;
    lIconInfo.hbmColor := lColor;
    Result := CreateIconIndirect(lIconInfo);
  finally
    DeleteObject(lColor);
    DeleteObject(lMask);
  end;
end;

procedure AddPixels(aImages: TCustomImageList; const aPixels: TPixels; aSize: Integer);
var
  lIcon: HICON;
begin
  lIcon := PixelsToIcon(aPixels, aSize);
  try
    ImageList_ReplaceIcon(aImages.Handle, -1, lIcon);
  finally
    DestroyIcon(lIcon);
  end;
end;

function GlyphPixels(aGlyph: Char; aSize: Integer; aColor: Cardinal): TPixels;
var
  lBits: PCardinal;
  lBitmap: HBITMAP;
  lBitmapInfo: TBitmapInfo;
  lCoverage: Cardinal;
  lDC: HDC;
  lFont: HFONT;
  lFontName: string;
  lIndex: Integer;
  lOldBitmap: HGDIOBJ;
  lOldFont: HGDIOBJ;
  lRect: TRect;
  lSource: PCardinal;
begin
  // Glyph wit op zwart tekenen (zonder ClearType), de helderheid is de dekking; daarmee de kleur invullen.
  SetLength(Result, aSize * aSize);
  FillChar(lBitmapInfo, SizeOf(lBitmapInfo), 0);
  lBitmapInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  lBitmapInfo.bmiHeader.biWidth := aSize;
  lBitmapInfo.bmiHeader.biHeight := -aSize;
  lBitmapInfo.bmiHeader.biPlanes := 1;
  lBitmapInfo.bmiHeader.biBitCount := 32;
  lBitmapInfo.bmiHeader.biCompression := BI_RGB;
  lDC := CreateCompatibleDC(0);
  lBitmap := CreateDIBSection(lDC, lBitmapInfo, DIB_RGB_COLORS, Pointer(lBits), 0, 0);
  if Screen.Fonts.IndexOf('Segoe Fluent Icons') >= 0 then
    lFontName := 'Segoe Fluent Icons'
  else
    lFontName := 'Segoe MDL2 Assets';
  lFont := CreateFont(-aSize, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, DEFAULT_PITCH, PChar(lFontName));
  lOldBitmap := SelectObject(lDC, lBitmap);
  lOldFont := SelectObject(lDC, lFont);
  try
    lRect := Rect(0, 0, aSize, aSize);
    FillRect(lDC, lRect, GetStockObject(BLACK_BRUSH));
    SetBkMode(lDC, TRANSPARENT);
    SetTextColor(lDC, RGB(255, 255, 255));
    DrawText(lDC, @aGlyph, 1, lRect, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
    GdiFlush;
    lSource := lBits;
    for lIndex := 0 to aSize * aSize - 1 do
    begin
      lCoverage := (lSource^ shr 8) and $FF; // groenkanaal: grijswaarde
      Result[lIndex] := 0;
      BlendPixel(Result[lIndex], aColor, lCoverage / 255);
      Inc(lSource);
    end;
  finally
    SelectObject(lDC, lOldFont);
    SelectObject(lDC, lOldBitmap);
    DeleteObject(lFont);
    DeleteObject(lBitmap);
    DeleteDC(lDC);
  end;
end;

function TintedPixels(const aPixels: TPixels; aColor: Cardinal): TPixels;
var
  lIndex: Integer;
  lLight: Double;
  lPixel: Cardinal;

  function Channel(aShift: Integer): Cardinal;
  begin
    // Kleur van de status, met de helderheid van het origineel: de vorm van het icoon blijft zichtbaar.
    Result := Cardinal(EnsureRange(Round(((aColor shr aShift) and $FF) * (0.55 + 0.6 * lLight)), 0, 255)) shl aShift;
  end;

begin
  SetLength(Result, Length(aPixels));
  for lIndex := 0 to High(aPixels) do
  begin
    lPixel := aPixels[lIndex];
    lLight := (((lPixel shr 16) and $FF) * 0.30 + ((lPixel shr 8) and $FF) * 0.59 + (lPixel and $FF) * 0.11) / 255;
    Result[lIndex] := (lPixel and $FF000000) or Channel(16) or Channel(8) or Channel(0);
  end;
end;

procedure BuildNodeImages(aImages: TCustomImageList; aPPI: Integer);
const
  cConnecting = $FFE8A317;
  cConnected = $FF2EA043;
  cError = $FFD73A49;
  cFavorite = $FFF2B90F;
  cRecent = $FF4A90D9;
  cServerDefault = $FF2F7FD8; // blauw: geen ping (of nog niet geprobeerd)
  cServerOnline = $FF2EA043;  // groen: gepingd, bereikbaar
  cServerOffline = $FFD73A49; // rood: gepingd, niet bereikbaar
  cServerWrongHost = $FFE8870E; // oranje: andere computer op dat adres
var
  lBase: TPixels;
  lIcon: HICON;
  lPixels: TPixels;
  lSize: Integer;

  procedure AddServerWithDot(aColor: Cardinal);
  begin
    lPixels := Copy(lBase);
    DrawDot(lPixels, lSize, aColor);
    AddPixels(aImages, lPixels, lSize);
  end;

begin
  lSize := MulDiv(16, Max(aPPI, 96), 96);
  aImages.Clear;
  aImages.ColorDepth := cd32Bit;
  aImages.SetSize(lSize, lSize);

  lIcon := LoadStockIcon(SIID_FOLDER, lSize);
  try
    AddPixels(aImages, IconToPixels(lIcon, lSize), lSize);  // ciGroup
  finally
    DestroyIcon(lIcon);
  end;

  lIcon := LoadStockIcon(SIID_SERVER, lSize);
  try
    lBase := IconToPixels(lIcon, lSize);
  finally
    DestroyIcon(lIcon);
  end;
  AddPixels(aImages, TintedPixels(lBase, cServerDefault), lSize);  // ciServer (blauw)
  AddServerWithDot(cConnecting);     // ciServerConnecting
  AddServerWithDot(cConnected);      // ciServerConnected
  AddServerWithDot(cError);          // ciServerError
  AddPixels(aImages, GlyphPixels(#$E735, lSize, cFavorite), lSize);  // ciFavorites (FavoriteStarFill)
  AddPixels(aImages, GlyphPixels(#$E81C, lSize, cRecent), lSize);    // ciRecent (History)
  AddPixels(aImages, TintedPixels(lBase, cServerOffline), lSize);     // ciServerOffline (rood)
  AddPixels(aImages, TintedPixels(lBase, cServerOnline), lSize);      // ciServerOnline (groen)
  AddPixels(aImages, TintedPixels(lBase, cServerWrongHost), lSize);   // ciServerWrongHost (oranje)
end;

end.
