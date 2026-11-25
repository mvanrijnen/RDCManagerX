unit RdcmX.Lang;

(*
  UI language: English or Dutch.

  The source texts in the code and in the DFMs are Dutch. English comes from a gettext-style catalogue,
  Source\Lang\en.po, embedded as RCDATA LANG_EN (Source\Lang.rc). Keep it up to date with Tools\i18n.py:
    python Tools\i18n.py update   (adds new texts, drops texts that no longer exist)
    python Tools\i18n.py check    (fails when a text has no English translation)

  - _('Dutch text') returns the text in the active language. Use it for every user-visible literal in code,
    also format strings: Format(_('%s is online (%d ms)'), [...]). The extraction tool only finds literals
    inside _( ), and only constant arguments (literals, #nn characters and +).
  - TranslateComponent translates the DFM texts of a form: Caption, Hint, TextHint, Title, Filter, Items, and
    Text/Caption of collection items (status bar panels, list view columns). Only stored values are translated,
    so a control linked to an action keeps following its action. Every form calls it from Loaded.
  - The language is chosen once at startup (ApplyStartupLanguage in the dpr, before CreateForm), like the theme.
    Changing it in Options applies at the next start.
  - Without a catalogue (Dutch, or the tests) every function returns the source text unchanged.

  The catalogue is read-only after startup, so _ is safe to call from background threads.
*)

interface

uses
  System.Classes, System.Generics.Collections;

type
  TRdcLanguage = (rlSystem, rlEnglish, rlDutch);

const
  cRdcLanguageNames: array[TRdcLanguage] of string = ('system', 'en', 'nl');

function RdcLanguageFromName(const aName: string): TRdcLanguage;
/// <summary>'nl' when the Windows display language is Dutch, otherwise 'en'.</summary>
function SystemLanguageCode: string;
/// <summary>'en' or 'nl' for a language setting (rlSystem follows Windows).</summary>
function ResolveLanguageCode(aLanguage: TRdcLanguage): string;
/// <summary>Activates a language ('en' or 'nl'). 'en' loads the embedded catalogue; without it the UI stays Dutch.</summary>
procedure SetUiLanguage(const aCode: string);
/// <summary>The active language: 'en' or 'nl'.</summary>
function UiLanguageCode: string;
/// <summary>The text in the active language; the Dutch source text when there is no translation.</summary>
function _(const aText: string): string;
/// <summary>Translates the stored DFM texts of aComponent and everything it owns.</summary>
procedure TranslateComponent(aComponent: TComponent);
/// <summary>Language from the app settings; call in the dpr before Application.CreateForm.</summary>
procedure ApplyStartupLanguage;
/// <summary>Reads a .po catalogue (msgid/msgstr with continuation lines) into aCatalogue. Entries with an empty
/// msgstr and the header are skipped. Exposed for the tests.</summary>
procedure ParsePoCatalogue(const aText: string; aCatalogue: TDictionary<string, string>);

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.TypInfo,
  RdcmX.AppSettings;

const
  // Language code -> RCDATA resource with its catalogue. Dutch is the source language and has none.
  cCatalogueCodes: array[0..0] of string = ('en');
  cCatalogueResources: array[0..0] of string = ('LANG_EN');
  cTextProperties: array[0..4] of string = ('Caption', 'Hint', 'TextHint', 'Title', 'Filter');

var
  GCatalogue: TDictionary<string, string>;
  GLanguageCode: string = 'nl';

function RdcLanguageFromName(const aName: string): TRdcLanguage;
begin
  for Result := Low(TRdcLanguage) to High(TRdcLanguage) do
    if SameText(cRdcLanguageNames[Result], aName) then
      Exit;
  Result := rlSystem;
end;

function SystemLanguageCode: string;
begin
  if (GetUserDefaultUILanguage and $3FF) = LANG_DUTCH then
    Result := 'nl'
  else
    Result := 'en';
end;

function ResolveLanguageCode(aLanguage: TRdcLanguage): string;
begin
  case aLanguage of
    rlEnglish:
      Result := 'en';
    rlDutch:
      Result := 'nl';
  else
    Result := SystemLanguageCode;
  end;
end;

function UnescapePo(const aText: string): string;
var
  lBuilder: TStringBuilder;
  lIndex: Integer;
begin
  lBuilder := TStringBuilder.Create(Length(aText));
  try
    lIndex := 1;
    while lIndex <= Length(aText) do
    begin
      if (aText[lIndex] = '\') and (lIndex < Length(aText)) then
      begin
        Inc(lIndex);
        case aText[lIndex] of
          'n': lBuilder.Append(#10);
          'r': lBuilder.Append(#13);
          't': lBuilder.Append(#9);
        else
          lBuilder.Append(aText[lIndex]); // \" and \\
        end;
      end
      else
        lBuilder.Append(aText[lIndex]);
      Inc(lIndex);
    end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

/// <summary>The contents of a quoted PO string ("..."), unescaped; '' when the line is not one.</summary>
function QuotedPoValue(const aLine: string): string;
var
  lLine: string;
begin
  lLine := Trim(aLine);
  if (Length(lLine) >= 2) and (lLine[1] = '"') and (lLine[Length(lLine)] = '"') then
    Result := UnescapePo(Copy(lLine, 2, Length(lLine) - 2))
  else
    Result := '';
end;

procedure ParsePoCatalogue(const aText: string; aCatalogue: TDictionary<string, string>);
type
  TPart = (ppNone, ppId, ppStr);
var
  lId: string;
  lLine: string;
  lLines: TStringList;
  lPart: TPart;
  lStr: string;

  procedure Flush;
  begin
    if (lPart <> ppNone) and (lId <> '') and (lStr <> '') then
      aCatalogue.AddOrSetValue(lId, lStr);
    lId := '';
    lStr := '';
    lPart := ppNone;
  end;

begin
  lLines := TStringList.Create;
  try
    lLines.Text := aText;
    lPart := ppNone;
    for lLine in lLines do
    begin
      if lLine.StartsWith('msgid ') then
      begin
        Flush;
        lPart := ppId;
        lId := QuotedPoValue(Copy(lLine, 7, MaxInt));
      end
      else if lLine.StartsWith('msgstr ') then
      begin
        lPart := ppStr;
        lStr := QuotedPoValue(Copy(lLine, 8, MaxInt));
      end
      else if Trim(lLine).StartsWith('"') then
      begin
        case lPart of
          ppId: lId := lId + QuotedPoValue(lLine);
          ppStr: lStr := lStr + QuotedPoValue(lLine);
        end;
      end
      else if Trim(lLine) = '' then
        Flush;
      // Comments (#) are ignored.
    end;
    Flush;
  finally
    lLines.Free;
  end;
end;

function LoadCatalogueResource(const aResource: string): string;
var
  lBytes: TBytes;
  lStream: TResourceStream;
begin
  Result := '';
  if FindResource(HInstance, PChar(aResource), RT_RCDATA) = 0 then
    Exit;
  lStream := TResourceStream.Create(HInstance, aResource, RT_RCDATA);
  try
    SetLength(lBytes, lStream.Size);
    if Length(lBytes) > 0 then
      lStream.ReadBuffer(lBytes[0], Length(lBytes));
  finally
    lStream.Free;
  end;
  Result := TEncoding.UTF8.GetString(lBytes);
  if Result.StartsWith(#$FEFF) then
    Delete(Result, 1, 1);
end;

procedure SetUiLanguage(const aCode: string);
var
  lIndex: Integer;
  lText: string;
begin
  FreeAndNil(GCatalogue);
  GLanguageCode := 'nl';
  for lIndex := Low(cCatalogueCodes) to High(cCatalogueCodes) do
    if SameText(cCatalogueCodes[lIndex], aCode) then
    begin
      lText := LoadCatalogueResource(cCatalogueResources[lIndex]);
      if lText = '' then
        Exit;
      GCatalogue := TDictionary<string, string>.Create;
      ParsePoCatalogue(lText, GCatalogue);
      GLanguageCode := cCatalogueCodes[lIndex];
      Exit;
    end;
end;

function UiLanguageCode: string;
begin
  Result := GLanguageCode;
end;

function _(const aText: string): string;
begin
  if (GCatalogue = nil) or not GCatalogue.TryGetValue(aText, Result) then
    Result := aText;
end;

/// <summary>Removes the accelerator markers of a caption ('&Save' -> 'Save', '&&' -> '&'), like Vcl.Menus.StripHotkey
/// (not used here so the unit has no VCL dependency and also works in the console test project).</summary>
function StripAccelerators(const aText: string): string;
var
  lIndex: Integer;
begin
  Result := '';
  lIndex := 1;
  while lIndex <= Length(aText) do
  begin
    if aText[lIndex] = '&' then
    begin
      if (lIndex < Length(aText)) and (aText[lIndex + 1] = '&') then
      begin
        Result := Result + '&';
        Inc(lIndex);
      end;
    end
    else
      Result := Result + aText[lIndex];
    Inc(lIndex);
  end;
end;

/// <summary>Like _, but also finds a DFM text whose accelerator (&) differs from the catalogue.</summary>
function TranslateDfmText(const aText: string): string;
var
  lStripped: string;
begin
  Result := aText;
  if (GCatalogue = nil) or (aText = '') then
    Exit;
  if GCatalogue.TryGetValue(aText, Result) then
    Exit;
  lStripped := StripAccelerators(aText);
  if (lStripped = aText) or not GCatalogue.TryGetValue(lStripped, Result) then
    Result := aText;
end;

function IsTextProperty(const aName: string; aCollectionItem: Boolean): Boolean;
var
  lName: string;
begin
  for lName in cTextProperties do
    if SameText(lName, aName) then
      Exit(True);
  Result := aCollectionItem and SameText(aName, 'Text');
end;

procedure TranslateStrings(aOwner: TObject; aStrings: TStrings);
var
  lIndex: Integer;
  lItemIndex: Integer;
  lText: string;
begin
  // Replacing an item can reset the selection of a combo box or radio group: keep ItemIndex.
  lItemIndex := -1;
  if IsPublishedProp(aOwner, 'ItemIndex') then
    lItemIndex := GetOrdProp(aOwner, 'ItemIndex');
  aStrings.BeginUpdate;
  try
    for lIndex := 0 to aStrings.Count - 1 do
    begin
      lText := TranslateDfmText(aStrings[lIndex]);
      if lText <> aStrings[lIndex] then
        aStrings[lIndex] := lText;
    end;
  finally
    aStrings.EndUpdate;
  end;
  if (lItemIndex >= 0) and (lItemIndex < aStrings.Count) then
    SetOrdProp(aOwner, 'ItemIndex', lItemIndex);
end;

procedure TranslateObject(aObject: TObject; aCollectionItem: Boolean); forward;

procedure TranslateCollection(aCollection: TCollection);
var
  lIndex: Integer;
begin
  for lIndex := 0 to aCollection.Count - 1 do
    TranslateObject(aCollection.Items[lIndex], True);
end;

procedure TranslateObject(aObject: TObject; aCollectionItem: Boolean);
var
  lCount: Integer;
  lIndex: Integer;
  lList: PPropList;
  lName: string;
  lProp: PPropInfo;
  lText: string;
  lValue: TObject;
begin
  if (aObject = nil) or (aObject.ClassInfo = nil) then
    Exit;
  lCount := GetPropList(PTypeInfo(aObject.ClassInfo), lList);
  try
    for lIndex := 0 to lCount - 1 do
    begin
      lProp := lList[lIndex];
      lName := string(lProp.Name);
      case lProp.PropType^.Kind of
        tkUString, tkLString, tkWString, tkString:
          if (lProp.SetProc <> nil) and IsTextProperty(lName, aCollectionItem) and IsStoredProp(aObject, lProp) then
          begin
            lText := GetStrProp(aObject, lProp);
            if lText <> '' then
              SetStrProp(aObject, lProp, TranslateDfmText(lText));
          end;
        tkClass:
          begin
            lValue := GetObjectProp(aObject, lProp);
            if lValue is TStrings then
            begin
              if SameText(lName, 'Items') then
                TranslateStrings(aObject, TStrings(lValue));
            end
            else if lValue is TCollection then
              TranslateCollection(TCollection(lValue))
            else if (lValue is TComponent) and (csSubComponent in TComponent(lValue).ComponentStyle) then
              TranslateObject(lValue, False);
          end;
      end;
    end;
  finally
    FreeMem(lList);
  end;
end;

procedure TranslateComponent(aComponent: TComponent);
var
  lIndex: Integer;
begin
  if GCatalogue = nil then
    Exit;
  TranslateObject(aComponent, False);
  for lIndex := 0 to aComponent.ComponentCount - 1 do
    TranslateComponent(aComponent.Components[lIndex]);
end;

procedure ApplyStartupLanguage;
var
  lSettings: TRdcAppSettings;
begin
  lSettings := TRdcAppSettings.Create;
  try
    lSettings.Load;
    SetUiLanguage(ResolveLanguageCode(RdcLanguageFromName(lSettings.Language)));
  finally
    lSettings.Free;
  end;
end;

initialization

finalization
  FreeAndNil(GCatalogue);

end.
